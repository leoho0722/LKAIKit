//
//  LKGeminiStreamState.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 讀取一次串流期間累積的狀態：每個步驟的類型，`interaction.completed` 時由它組出結束事件的內容或丟出錯誤
///
/// - Note: 只在 `LKAIGemini` 內使用；SSE 事件依序交給 `handle(_:)`，由它解碼並對應成要交出的對話事件
/// - Note: `step.delta` 不帶步驟類型，只帶 `index`，所以要記住 `step.start` 的 `index` 與 `step.type`
/// - Note: 只交出 `model_output` 步驟的文字；思考步驟的簽章與摘要不是給使用者看的文字
/// - Note: 沒有 `step.start` 記錄過的 `index`，它的片段不交出
/// - Note: 結束資訊只取自 `interaction.completed` 的 `interaction`，其他事件不帶用量與模型
/// - Note: Gemini 分不開生成途中塞滿 context window 與達到輸出上限，兩者都是 `incomplete`，
///   所以結束事件的結束原因不會是 `.contextWindowExceeded`
/// - Note: `failed` 狀態與 `error` 事件的錯誤對應還沒有實作，目前 `failed` 與其他狀態一樣回報 `invalidResponse`，
///   `error` 事件與不認得的事件一樣略過
struct LKGeminiStreamState {

    // MARK: - Properties

    /// 依 `step.start` 記錄的對照，步驟的 `index` 對應它的 `step.type`；還沒有收到任何 `step.start` 時為空
    private var stepTypes: [Int: String] = [:]

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKGeminiStreamState: LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件：解碼成 Gemini 的串流事件，更新狀態，並回傳要交出的對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件，事件種類以 `data` 裡的 `event_type` 為準，不看事件名稱
    /// - Returns: 有文字時為只含 `.textDelta` 的陣列；正常結束時為只含 `.finished` 的陣列；其餘為空陣列
    /// - Throws: `data` 解碼失敗丟 `invalidResponse`；
    ///   `interaction.completed` 的狀態是 `requires_action`、`cancelled`、`failed`、其他值或沒有狀態，
    ///   丟 `invalidResponse`
    /// - Note: `step.start` 帶著文字時，依序交出每一段，然後才輪到之後的 `step.delta`
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        switch try decode(event) {
        case .stepStart(let index, let type, let texts):
            stepTypes[index] = type
            return texts.map { LKAIChatStreamEvent.textDelta($0) }

        case .stepDelta(let index, let text):
            guard stepTypes[index] == "model_output", let text else {
                return []
            }
            return [.textDelta(text)]

        case .completed(let interaction):
            let completion = try makeCompletion(from: interaction)
            return [.finished(completion)]

        case .ignored:
            return []
        }
    }
}

// MARK: - Private Method

private extension LKGeminiStreamState {

    /// 把 SSE 事件的 `data` 解碼成 Gemini 的串流事件
    ///
    /// - Parameter event: 解析好的 SSE 事件
    /// - Returns: 解碼出的串流事件；不認得的類型是略過
    /// - Throws: `data` 不是合法的 JSON，或認得的類型欄位格式不符時丟出 `invalidResponse`
    func decode(_ event: LKAIServerSentEvent) throws(LKAIError) -> LKGeminiStreamEvent {
        do {
            return try LKGeminiStreamEvent(data: event.data)
        } catch {
            throw .invalidResponse(reason: "Malformed stream event: \(error)")
        }
    }

    /// 依 `interaction.completed` 的互動組出結束事件的內容，`handle(_:)` 收到 `interaction.completed` 時呼叫
    ///
    /// - Parameter interaction: `interaction.completed` 帶的互動
    /// - Returns: 帶著結束原因、用量與實際回應的模型的結束資訊
    /// - Throws: 狀態不是 `completed` 或 `incomplete` 時丟出 `invalidResponse`
    func makeCompletion(
        from interaction: LKGeminiStreamEvent.Interaction
    ) throws(LKAIError) -> LKAIChatCompletion {
        let finishReason = try makeFinishReason(fromStatus: interaction.status)
        return LKAIChatCompletion(
            finishReason: finishReason,
            usage: makeUsage(from: interaction.usage),
            respondingModel: interaction.model
        )
    }

    /// 把互動的狀態對應成結束原因
    ///
    /// - Parameter status: 互動的 `status`；沒有狀態時為 nil
    /// - Returns: `completed` 對應完成，`incomplete` 對應輸出上限
    /// - Throws: 其他狀態或沒有狀態丟 `invalidResponse`
    /// - Note: 生成途中塞滿 context window 時 Gemini 也回報 `incomplete`，所以不會有 context window 的結束原因
    func makeFinishReason(fromStatus status: String?) throws(LKAIError) -> LKAIFinishReason {
        guard let status else {
            throw .invalidResponse(reason: "The interaction completed without a status")
        }
        switch status {
        case "completed":
            return .completed

        case "incomplete":
            return .maxOutputTokens

        default:
            throw .invalidResponse(reason: "Unexpected interaction status: \(status)")
        }
    }

    /// 把互動的用量組成統一口徑的用量
    ///
    /// - Parameter usage: 互動的 `usage`；為 null 或沒有這個欄位時為 nil
    /// - Returns: 輸入照原值，輸出是輸出加上思考，快取與思考的細項沒有回報時為 nil；
    ///   `usage` 為 nil，或缺少輸入或輸出總數時為 nil
    /// - Note: 沒有回報思考的 token 數時，計算輸出總數以 0 相加，推理的數量仍是 nil
    func makeUsage(from usage: LKGeminiStreamEvent.Usage?) -> LKAIUsage? {
        guard let usage,
              let inputTokens = usage.totalInputTokens,
              let outputTokens = usage.totalOutputTokens else {
            return nil
        }
        return LKAIUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens + (usage.totalThoughtTokens ?? 0),
            cachedInputTokens: usage.totalCachedTokens,
            reasoningOutputTokens: usage.totalThoughtTokens
        )
    }
}
