//
//  LKAIServerSentEvent+AnthropicEvents.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

// MARK: - Internal Method

/// Anthropic Messages API 串流各種事件的建構函式，給 `LKAIAnthropicTests` 組出替身要推送的 SSE 事件
extension LKAIServerSentEvent {

    /// 建立 `message_start` 事件，內容是一則還沒有任何內容的助理訊息
    ///
    /// - Parameters:
    ///   - model: 訊息的模型識別碼
    ///   - usage: 訊息的 `usage` JSON；nil 表示不放這個鍵
    /// - Returns: `message_start` 事件
    static func messageStart(
        model: String = "claude-opus-5-5",
        usage: String? = nil
    ) -> LKAIServerSentEvent {
        let usageField = optionalField("usage", usage)
        return LKAIServerSentEvent(
            event: "message_start",
            data: #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"\#(model)","stop_reason":null,"stop_sequence":null\#(usageField)}}"#
        )
    }

    /// 建立開始一個文字區塊的 `content_block_start` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_start` 事件，區塊類型是 `text`
    static func textBlockStart(index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_start",
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"text","text":""}}"#
        )
    }

    /// 建立一段文字的 `content_block_delta` 事件
    ///
    /// - Parameters:
    ///   - text: 這一段的文字
    ///   - index: 所屬區塊的序號
    /// - Returns: `content_block_delta` 事件，增量類型是 `text_delta`
    static func textDelta(_ text: String, index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"text_delta","text":"\#(text)"}}"#
        )
    }

    /// 建立結束一個區塊的 `content_block_stop` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_stop` 事件
    static func blockStop(index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_stop",
            data: #"{"type":"content_block_stop","index":\#(index)}"#
        )
    }

    /// 建立 `message_delta` 事件，帶這則訊息最後的 `stop_reason`，以及可有可無的結束細節與用量
    ///
    /// - Parameters:
    ///   - stopReason: `stop_reason` 的值；nil 表示寫成 null
    ///   - stopDetails: `stop_details` JSON；nil 表示不放這個鍵
    ///   - usage: `usage` JSON；nil 表示不放這個鍵
    /// - Returns: `message_delta` 事件
    static func messageDelta(
        stopReason: String?,
        stopDetails: String? = nil,
        usage: String? = nil
    ) -> LKAIServerSentEvent {
        let stopReasonJSON = stopReason.map { "\"\($0)\"" } ?? "null"
        let stopDetailsField = optionalField("stop_details", stopDetails)
        let usageField = optionalField("usage", usage)
        return LKAIServerSentEvent(
            event: "message_delta",
            data: #"{"type":"message_delta","delta":{"stop_reason":\#(stopReasonJSON),"stop_sequence":null\#(stopDetailsField)}\#(usageField)}"#
        )
    }

    /// 建立 `message_stop` 事件，表示整則訊息結束
    ///
    /// - Returns: `message_stop` 事件
    static func messageStop() -> LKAIServerSentEvent {
        LKAIServerSentEvent(event: "message_stop", data: #"{"type":"message_stop"}"#)
    }

    /// 建立開始一個思考區塊的 `content_block_start` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_start` 事件，區塊類型是 `thinking`
    static func thinkingBlockStart(index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_start",
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"thinking","thinking":""}}"#
        )
    }

    /// 建立思考內容為空的 `content_block_delta` 事件
    ///
    /// - Parameter index: 所屬區塊的序號
    /// - Returns: `content_block_delta` 事件，增量類型是 `thinking_delta`
    static func thinkingDelta(index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"thinking_delta","thinking":""}}"#
        )
    }

    /// 建立 `ping` 事件，用來保持連線，不帶任何內容
    ///
    /// - Returns: `ping` 事件
    static func ping() -> LKAIServerSentEvent {
        LKAIServerSentEvent(event: "ping", data: #"{"type": "ping"}"#)
    }

    /// 建立思考簽章的 `content_block_delta` 事件
    ///
    /// - Parameter index: 所屬區塊的序號
    /// - Returns: `content_block_delta` 事件，增量類型是 `signature_delta`
    static func signatureDelta(index: Int = 0) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"signature_delta","signature":"sig"}}"#
        )
    }

    /// 建立開始一個備援區塊的 `content_block_start` 事件，表示從原模型切換到備援模型
    ///
    /// - Parameters:
    ///   - index: 區塊的序號
    ///   - from: 切換前的模型識別碼
    ///   - to: 切換後的模型識別碼
    /// - Returns: `content_block_start` 事件，區塊類型是 `fallback`
    static func fallbackBlockStart(index: Int, from: String, to: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "content_block_start",
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"fallback","from":{"model":"\#(from)"},"to":{"model":"\#(to)"}}}"#
        )
    }
}

// MARK: - Private Method

private extension LKAIServerSentEvent {

    /// 組出 JSON 物件裡可有可無的欄位，前面帶逗號，接在其他欄位之後
    ///
    /// - Parameters:
    ///   - name: 欄位名稱
    ///   - json: 欄位值的 JSON；nil 表示不放這個欄位
    /// - Returns: `,"名稱":值`；沒有值時為空字串
    static func optionalField(_ name: String, _ json: String?) -> String {
        guard let json else {
            return ""
        }
        return ",\"\(name)\":\(json)"
    }
}
