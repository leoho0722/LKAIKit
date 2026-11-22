//
//  LKOpenAIStreamState.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 讀取一次串流期間累積的狀態：收到的拒答文字，`response.completed` 與 `response.incomplete` 時由它組出結束事件的內容或丟出錯誤
///
/// - Note: 只在 `LKAIOpenAI` 內使用；SSE 事件依序交給 `handle(_:)`，由它解碼並對應成要交出的對話事件
/// - Note: 串流中的 `error` 事件與 `response.failed` 依 `code` 分類成錯誤丟出，分類規則見 `LKOpenAIErrorBody.Detail`
/// - Note: `response.failed` 沒有 `response.error` 時，當成服務暫時無法使用，狀態碼 500
/// - Note: 結束資訊只取自結束事件的 `response` 物件，其他事件不帶用量與模型
/// - Note: OpenAI 回報的輸入與輸出總數本來就包含快取與推理，所以直接使用，不再相加
/// - Note: 拒答文字有任何 `response.refusal.delta` 時，以 delta 依序串接
/// - Note: 一則 delta 都沒有時，拒答文字改用 `response.refusal.done` 依序串接
/// - Note: 拒答文字不為空時，結束事件不論是 `response.completed` 或 `response.incomplete` 都丟出拒答錯誤，原因是拒答文字
/// - Note: OpenAI 不回報 context window 塞滿，生成途中塞滿時回報的原因是 `max_output_tokens`
/// - Note: 結束事件的結束原因因此不會是 `.contextWindowExceeded`
struct LKOpenAIStreamState {

    // MARK: - Properties

    /// 依收到的順序記下的 `response.refusal.delta` 的 `delta`；一則都沒有收到時為空陣列
    private var refusalDeltas: [String] = []

    /// 依收到的順序記下的 `response.refusal.done` 的 `refusal`；一則都沒有收到時為空陣列
    private var refusalDones: [String] = []

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKOpenAIStreamState: LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件：解碼成 OpenAI 的串流事件，更新狀態，並回傳要交出的對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件，事件種類以 `data` 裡的 `type` 為準，不看事件名稱
    /// - Returns: 有文字時為只含 `.textDelta` 的陣列；正常結束時為只含 `.finished` 的陣列；其餘為空陣列
    /// - Throws: `data` 解碼失敗丟 `invalidResponse`；
    ///   結束事件時拒答文字不為空，或 `response.incomplete` 的原因是 `content_filter` 丟 `refused`；
    ///   `response.incomplete` 的原因不認得或沒有原因丟 `invalidResponse`；
    ///   `error` 事件與 `response.failed` 丟 `code` 對應的錯誤，不認得的代碼丟 `invalidResponse`
    /// - Note: 拒答事件只累積文字，不交出事件；已交出的文字片段保留
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        switch try decode(event) {
        case .outputTextDelta(let text):
            return [.textDelta(text)]

        case .refusalDelta(let text):
            refusalDeltas.append(text)
            return []

        case .refusalDone(let text):
            refusalDones.append(text)
            return []

        case .completed(let response):
            let completion = try makeCompletedCompletion(from: response)
            return [.finished(completion)]

        case .incomplete(let response):
            let completion = try makeIncompleteCompletion(from: response)
            return [.finished(completion)]

        case .failed(let response):
            throw response.error?.streamError ?? .serviceUnavailable(statusCode: 500)

        case .error(let detail):
            throw detail.streamError

        case .ignored:
            return []
        }
    }
}

// MARK: - Private Method

private extension LKOpenAIStreamState {

    /// 目前收到的拒答文字：有任何 `response.refusal.delta` 時是 delta 依序串接，否則是 `response.refusal.done` 依序串接
    ///
    /// - Note: 以陣列記錄，「有沒有收到 delta」才不會和「delta 是空字串」混在一起
    var refusalText: String {
        if refusalDeltas.isEmpty {
            return refusalDones.joined()
        }
        return refusalDeltas.joined()
    }

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

    /// 依 `response.completed` 的回應物件組出結束事件的內容，`handle(_:)` 收到 `response.completed` 時呼叫
    ///
    /// - Parameter response: `response.completed` 帶的回應物件
    /// - Returns: 結束原因為完成，帶著用量與實際回應的模型的結束資訊
    /// - Throws: 拒答文字不為空時丟出 `refused`，原因是拒答文字
    func makeCompletedCompletion(
        from response: LKOpenAIStreamEvent.Response
    ) throws(LKAIError) -> LKAIChatCompletion {
        try throwIfRefused()
        return makeCompletion(from: response, finishReason: .completed)
    }

    /// 檢查拒答文字，不為空時丟出拒答錯誤
    ///
    /// - Throws: 拒答文字不為空時丟出 `refused`，原因是拒答文字
    func throwIfRefused() throws(LKAIError) {
        let text = refusalText
        if !text.isEmpty {
            throw .refused(detail: text)
        }
    }

    /// 依回應物件組出結束事件的內容，`completed` 與 `incomplete` 共用
    ///
    /// - Parameters:
    ///   - response: 結束事件帶的回應物件
    ///   - finishReason: 結束原因，由呼叫端依事件種類決定
    /// - Returns: 帶著結束原因、用量與實際回應的模型的結束資訊
    func makeCompletion(
        from response: LKOpenAIStreamEvent.Response,
        finishReason: LKAIFinishReason
    ) -> LKAIChatCompletion {
        LKAIChatCompletion(
            finishReason: finishReason,
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

    /// 依 `response.incomplete` 的回應物件組出結束事件的內容，`handle(_:)` 收到 `response.incomplete` 時呼叫
    ///
    /// - Parameter response: `response.incomplete` 帶的回應物件
    /// - Returns: 結束原因為輸出上限，帶著用量與實際回應的模型的結束資訊
    /// - Throws: 拒答文字不為空時丟出 `refused`，原因是拒答文字；其餘錯誤見 `makeFinishReason(fromIncompleteReason:)`
    func makeIncompleteCompletion(
        from response: LKOpenAIStreamEvent.Response
    ) throws(LKAIError) -> LKAIChatCompletion {
        try throwIfRefused()
        let finishReason = try makeFinishReason(
            fromIncompleteReason: response.incompleteDetails?.reason
        )
        return makeCompletion(from: response, finishReason: finishReason)
    }

    /// 把 `incomplete_details.reason` 對應成結束原因
    ///
    /// - Parameter reason: `incomplete_details.reason`；沒有 `incomplete_details` 或沒有原因時為 nil
    /// - Returns: `max_output_tokens` 對應輸出上限
    /// - Throws: `content_filter` 丟 `refused`，原因是固定字串 `content_filter`；其他值或沒有原因丟 `invalidResponse`
    /// - Note: 生成途中塞滿 context window 時 OpenAI 也回報 `max_output_tokens`，所以不會有 context window 的結束原因
    func makeFinishReason(
        fromIncompleteReason reason: String?
    ) throws(LKAIError) -> LKAIFinishReason {
        guard let reason else {
            throw .invalidResponse(reason: "The response was incomplete without a reason")
        }
        switch reason {
        case "max_output_tokens":
            return .maxOutputTokens

        case "content_filter":
            throw .refused(detail: "content_filter")

        default:
            throw .invalidResponse(reason: "Unexpected incomplete reason: \(reason)")
        }
    }
}
