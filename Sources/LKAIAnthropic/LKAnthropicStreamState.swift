//
//  LKAnthropicStreamState.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import LKAICore

/// 讀取一次串流期間累積的狀態：實際回應的模型、結束原因與用量，`message_stop` 時由它組出結束事件的內容
///
/// - Note: 只在 `LKAIAnthropic` 內使用；SSE 事件依序交給 `handle(_:)`，由它解碼並對應成要交出的對話事件
/// - Note: 用量欄位是累計值，事件回報的值覆寫先前的值；null 或沒有出現的欄位保留先前的值
/// - Note: 結束原因取最後一個不是 null 的 `stop_reason`，拒答的類別跟著它一起更新
/// - Note: 實際回應的模型以最後一個 `fallback` 區塊的 `to.model` 為準，沒有時是 `message_start` 的 `model`
/// - Note: 兩者都沒有時實際回應的模型為 nil，這不是錯誤
/// - Note: 依使用者黏著改由備援模型回答的回合沒有 `fallback` 區塊，此時 `message_start` 的 `model` 已是備援模型
/// - Note: 開啟備援時頂層用量只涵蓋最後產生回應的那一次嘗試，這裡不加總 `usage.iterations`
struct LKAnthropicStreamState {

    // MARK: - Properties

    /// 目前已知實際回應的模型；還沒有收到帶模型的 `message_start` 或 `fallback` 區塊時為 nil
    private var respondingModel: String?

    /// 最後一個不是 null 的 `stop_reason`；還沒有時為 nil
    private var stopReason: String?

    /// 拒答的類別，跟著 `stopReason` 一起更新；沒有或為 null 時為 nil
    private var refusalCategory: String?

    /// 累計的輸入 token 數，不含快取建立與讀取的部分；從未回報過時為 nil
    private var inputTokens: Int?

    /// 累計的快取建立輸入 token 數；從未回報過時為 nil
    private var cacheCreationInputTokens: Int?

    /// 累計的快取讀取輸入 token 數；從未回報過時為 nil
    private var cacheReadInputTokens: Int?

    /// 累計的輸出 token 數，含思考的部分；從未回報過時為 nil
    private var outputTokens: Int?

    /// 累計的思考輸出 token 數；從未回報過時為 nil
    private var thinkingTokens: Int?

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKAnthropicStreamState: LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件：解碼成 Anthropic 的串流事件，更新狀態，並回傳要交出的對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件，事件種類以 `data` 裡的 `type` 為準，不看事件名稱
    /// - Returns: 有文字時為只含 `.textDelta` 的陣列；`message_stop` 時為只含 `.finished` 的陣列；其餘為空陣列
    /// - Throws: `data` 解碼失敗丟 `invalidResponse`；`error` 事件丟對應的錯誤；`message_stop` 的結束原因不正常時丟對應的錯誤
    /// - Note: `error` 事件沒有 `error.type` 或類型不認得時，依 chat-client 的共同規則，
    ///   由 `LKAIError.unrecognizedStreamError(code:message:)` 回報；已交出的文字片段保留
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        let streamEvent = try decode(event)
        if case .error(let body) = streamEvent {
            throw body.error.lkaiError(statusCode: nil, retryAfter: nil)
                ?? .unrecognizedStreamError(code: body.error.type, message: body.error.message)
        }
        if case .messageStop = streamEvent {
            let completion = try makeCompletion()
            return [.finished(completion)]
        }
        guard let text = apply(streamEvent) else {
            return []
        }
        return [.textDelta(text)]
    }
}

// MARK: - Private Method

private extension LKAnthropicStreamState {

    /// 把 SSE 事件的 `data` 解碼成 Anthropic 的串流事件
    ///
    /// - Parameter event: 解析好的 SSE 事件
    /// - Returns: 解碼出的串流事件；不認得的類型是略過
    /// - Throws: `data` 不是合法的 JSON，或認得的類型欄位格式不符時丟出 `invalidResponse`
    func decode(_ event: LKAIServerSentEvent) throws(LKAIError) -> LKAnthropicStreamEvent {
        do {
            return try LKAnthropicStreamEvent(data: event.data)
        } catch {
            throw .invalidResponse(reason: "Malformed stream event: \(error)")
        }
    }

    /// 依累積的狀態組出結束事件的內容，`handle(_:)` 收到 `message_stop` 時呼叫
    ///
    /// - Returns: 帶著結束原因、用量與實際回應的模型的結束資訊
    /// - Throws: 結束原因是 `refusal` 時丟出 `refused`，原因是拒答的類別；沒有結束原因或不認得時丟出 `invalidResponse`
    func makeCompletion() throws(LKAIError) -> LKAIChatCompletion {
        let finishReason = try makeFinishReason()
        return LKAIChatCompletion(
            finishReason: finishReason,
            usage: makeUsage(),
            respondingModel: respondingModel
        )
    }

    /// 把 Anthropic 的 `stop_reason` 對應成結束原因
    ///
    /// - Returns: 對應的結束原因；`end_turn` 與 `stop_sequence` 是完成，`max_tokens` 是輸出上限
    /// - Throws: `refusal` 丟 `refused`；沒有結束原因或不認得的值（例如 `tool_use`）丟 `invalidResponse`
    /// - Note: `model_context_window_exceeded` 對應 context window 滿了的結束原因
    func makeFinishReason() throws(LKAIError) -> LKAIFinishReason {
        guard let stopReason else {
            throw .invalidResponse(reason: "The stream reported no stop reason")
        }
        switch stopReason {
        case "end_turn", "stop_sequence":
            return .completed

        case "max_tokens":
            return .maxOutputTokens

        case "model_context_window_exceeded":
            return .contextWindowExceeded

        case "refusal":
            throw .refused(detail: refusalCategory)

        default:
            throw .invalidResponse(reason: "Unexpected stop reason: \(stopReason)")
        }
    }

    /// 把累計的用量組成統一口徑的用量
    ///
    /// - Returns: 輸入含快取建立與讀取，輸出含思考；從頭到尾沒有回報輸入或輸出 token 時為 nil
    func makeUsage() -> LKAIUsage? {
        guard let inputTokens, let outputTokens else {
            return nil
        }
        let cacheCreationCount = cacheCreationInputTokens ?? 0
        let cacheReadCount = cacheReadInputTokens ?? 0
        return LKAIUsage(
            inputTokens: inputTokens + cacheCreationCount + cacheReadCount,
            outputTokens: outputTokens,
            cachedInputTokens: cacheReadInputTokens,
            reasoningOutputTokens: thinkingTokens
        )
    }

    /// 套用一個串流事件：更新回應的模型、結束原因與用量，並把要交給 App 的文字交還給呼叫端
    ///
    /// - Parameter event: 剛收到的串流事件
    /// - Returns: 這個事件帶來的一段文字；沒有文字時為 nil
    /// - Note: `message_stop` 與 `error` 不在這裡處理，由 `handle(_:)` 在收到時分別改呼叫 `makeCompletion()` 或丟出錯誤
    mutating func apply(_ event: LKAnthropicStreamEvent) -> String? {
        switch event {
        case .messageStart(let model, let usage):
            if let model {
                respondingModel = model
            }
            merge(usage)
            return nil

        case .fallback(let toModel):
            respondingModel = toModel
            return nil

        case .textDelta(let text):
            return text

        case .messageDelta(let stopReason, let refusalCategory, let usage):
            if let stopReason {
                self.stopReason = stopReason
                self.refusalCategory = refusalCategory
            }
            merge(usage)
            return nil

        // message_stop 與 error 由 handle(_:) 先處理，不會到這裡；列在這裡只是讓 switch 窮舉
        case .messageStop, .error, .ignored:
            return nil
        }
    }

    /// 把事件回報的用量併入累計值：有值的欄位覆寫，null 或沒有出現的欄位保留先前的值
    ///
    /// - Parameter usage: 事件回報的用量；事件沒有用量時為 nil
    mutating func merge(_ usage: LKAnthropicStreamEvent.Usage?) {
        guard let usage else {
            return
        }
        inputTokens = usage.inputTokens ?? inputTokens
        cacheCreationInputTokens = usage.cacheCreationInputTokens ?? cacheCreationInputTokens
        cacheReadInputTokens = usage.cacheReadInputTokens ?? cacheReadInputTokens
        outputTokens = usage.outputTokens ?? outputTokens
        thinkingTokens = usage.outputTokensDetails?.thinkingTokens ?? thinkingTokens
    }
}
