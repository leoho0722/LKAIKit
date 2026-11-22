//
//  LKOpenAIStreamState.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 讀取一次串流期間的事件對應：交出回答的文字片段，並在 `response.completed` 組出結束事件的內容
///
/// - Note: 只在 `LKAIOpenAI` 內使用；SSE 事件依序交給 `handle(_:)`，由它解碼並對應成要交出的對話事件
/// - Note: 結束資訊只取自 `response.completed` 的 `response` 物件，其他事件不帶用量與模型
/// - Note: OpenAI 回報的輸入與輸出總數本來就包含快取與推理，所以直接使用，不再相加
/// - Note: 結束原因目前一律是完成
struct LKOpenAIStreamState {

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKOpenAIStreamState: LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件：解碼成 OpenAI 的串流事件，並回傳要交出的對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件，事件種類以 `data` 裡的 `type` 為準，不看事件名稱
    /// - Returns: `response.output_text.delta` 時為只含 `.textDelta` 的陣列；`response.completed` 時為只含 `.finished` 的陣列；其餘為空陣列
    /// - Throws: `data` 解碼失敗時丟出 `invalidResponse`
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        switch try decode(event) {
        case .outputTextDelta(let text):
            return [.textDelta(text)]

        case .completed(let response):
            return [.finished(makeCompletion(from: response))]

        case .ignored:
            return []
        }
    }
}

// MARK: - Private Method

private extension LKOpenAIStreamState {

    /// 把 SSE 事件的 `data` 解碼成 OpenAI 的串流事件
    ///
    /// - Parameter event: 解析好的 SSE 事件
    /// - Returns: 解碼出的串流事件；不認得的類型是略過
    /// - Throws: `data` 不是合法的 JSON，或認得的類型欄位格式不符時丟出 `invalidResponse`
    func decode(_ event: LKAIServerSentEvent) throws(LKAIError) -> LKOpenAIStreamEvent {
        do {
            return try LKOpenAIStreamEvent(data: event.data)
        } catch {
            throw .invalidResponse(reason: "Malformed stream event: \(error)")
        }
    }

    /// 依 `response.completed` 的回應物件組出結束事件的內容
    ///
    /// - Parameter response: `response.completed` 帶的回應物件
    /// - Returns: 結束原因為完成，帶著用量與實際回應的模型的結束資訊
    func makeCompletion(from response: LKOpenAIStreamEvent.Response) -> LKAIChatCompletion {
        LKAIChatCompletion(
            finishReason: .completed,
            usage: makeUsage(from: response.usage),
            respondingModel: response.model
        )
    }

    /// 把回應物件的用量組成統一口徑的用量
    ///
    /// - Parameter usage: 回應物件的 `usage`；為 null 或沒有這個欄位時為 nil
    /// - Returns: 輸入、輸出總數照原值，快取與推理的細項沒有回報時為 nil；`usage` 為 nil，或缺少輸入或輸出總數時為 nil
    func makeUsage(from usage: LKOpenAIStreamEvent.Usage?) -> LKAIUsage? {
        guard let usage,
              let inputTokens = usage.inputTokens,
              let outputTokens = usage.outputTokens else {
            return nil
        }
        return LKAIUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: usage.inputTokensDetails?.cachedTokens,
            reasoningOutputTokens: usage.outputTokensDetails?.reasoningTokens
        )
    }
}
