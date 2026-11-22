//
//  LKAIServerSentEvent+OpenAIEvents.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

// MARK: - Internal Method

/// OpenAI Responses API 串流各種事件的建構函式，給 `LKAIOpenAITests` 組出替身要推送的 SSE 事件
extension LKAIServerSentEvent {

    /// 建立 `response.created` 事件，內容是一個剛建立、還在進行中的回應，用量是 null
    ///
    /// - Returns: `response.created` 事件；回應的模型是請求用的 `gpt-6-luna`，與完成事件的模型不同
    static func responseCreated() -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.created",
            data: #"{"type":"response.created","response":{"id":"resp_1","object":"response","status":"in_progress","model":"gpt-6-luna","output":[],"usage":null},"sequence_number":0}"#
        )
    }

    /// 建立 `response.in_progress` 事件，表示回應正在進行，用量是 null
    ///
    /// - Returns: `response.in_progress` 事件；回應的模型是請求用的 `gpt-6-luna`，與完成事件的模型不同
    static func responseInProgress() -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.in_progress",
            data: #"{"type":"response.in_progress","response":{"id":"resp_1","object":"response","status":"in_progress","model":"gpt-6-luna","output":[],"usage":null},"sequence_number":1}"#
        )
    }

    /// 建立 `response.output_item.added` 事件，表示加入一則還沒有內容的助理訊息
    ///
    /// - Returns: `response.output_item.added` 事件
    static func outputItemAdded() -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.output_item.added",
            data: #"{"type":"response.output_item.added","output_index":0,"item":{"id":"msg_1","type":"message","status":"in_progress","role":"assistant","content":[]},"sequence_number":2}"#
        )
    }

    /// 建立推理摘要文字的 `response.reasoning_summary_text.delta` 事件
    ///
    /// - Parameter text: 這一段的推理摘要文字，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `response.reasoning_summary_text.delta` 事件
    static func reasoningSummaryTextDelta(_ text: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.reasoning_summary_text.delta",
            data: #"{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","output_index":0,"summary_index":0,"delta":"\#(text)","sequence_number":3}"#
        )
    }

    /// 建立一段回答文字的 `response.output_text.delta` 事件
    ///
    /// - Parameter text: 這一段的文字，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `response.output_text.delta` 事件；另帶 `logprobs` 與 `obfuscation`，用來確認不認得的欄位會被略過
    static func outputTextDelta(_ text: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.output_text.delta",
            data: #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"\#(text)","sequence_number":4,"logprobs":[],"obfuscation":"a1b2c3"}"#
        )
    }

    /// 建立 `response.output_text.done` 事件，表示這一段回答文字結束，並帶著完整文字
    ///
    /// - Returns: `response.output_text.done` 事件；完整文字是 "Hello"，這個事件不該再交出一次文字
    static func outputTextDone() -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.output_text.done",
            data: #"{"type":"response.output_text.done","item_id":"msg_1","output_index":0,"content_index":0,"text":"Hello","sequence_number":6,"logprobs":[]}"#
        )
    }

    /// 建立一段拒答文字的 `response.refusal.delta` 事件
    ///
    /// - Parameter text: 這一段的拒答文字，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `response.refusal.delta` 事件
    static func refusalDelta(_ text: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.refusal.delta",
            data: #"{"type":"response.refusal.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"\#(text)","sequence_number":1}"#
        )
    }

    /// 建立 `response.refusal.done` 事件，表示拒答文字結束，並帶著完整的拒答文字
    ///
    /// - Parameter text: 完整的拒答文字，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `response.refusal.done` 事件
    static func refusalDone(_ text: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "response.refusal.done",
            data: #"{"type":"response.refusal.done","item_id":"msg_1","output_index":0,"content_index":0,"refusal":"\#(text)","sequence_number":1}"#
        )
    }

    /// 建立 `response.completed` 事件，內容是完整的回應物件，狀態是完成
    ///
    /// - Parameters:
    ///   - model: 回應物件的 `model`；nil 表示不放這個鍵
    ///   - usage: 回應物件的 `usage` JSON；nil 表示不放這個鍵，要測 null 時傳 `"null"`
    /// - Returns: `response.completed` 事件
    static func responseCompleted(
        model: String? = "gpt-6-luna-2026-09-01",
        usage: String? = nil
    ) -> LKAIServerSentEvent {
        let modelField = optionalField("model", model.map { "\"\($0)\"" })
        let usageField = optionalField("usage", usage)
        return LKAIServerSentEvent(
            event: "response.completed",
            data: #"{"type":"response.completed","response":{"id":"resp_1","object":"response","status":"completed"\#(modelField),"output":[{"id":"msg_1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello","annotations":[]}]}]\#(usageField)},"sequence_number":7}"#
        )
    }

    /// 建立 `response.incomplete` 事件，內容是完整的回應物件，狀態是未完成
    ///
    /// - Parameters:
    ///   - reason: 回應物件 `incomplete_details.reason` 的值；nil 表示不放 `incomplete_details` 這個鍵
    ///   - model: 回應物件的 `model`；nil 表示不放這個鍵
    ///   - usage: 回應物件的 `usage` JSON；nil 表示不放這個鍵，要測 null 時傳 `"null"`
    /// - Returns: `response.incomplete` 事件
    static func responseIncomplete(
        reason: String?,
        model: String? = "gpt-6-luna-2026-09-01",
        usage: String? = nil
    ) -> LKAIServerSentEvent {
        let incompleteDetailsField = optionalField(
            "incomplete_details",
            reason.map { #"{"reason":"\#($0)"}"# }
        )
        let modelField = optionalField("model", model.map { "\"\($0)\"" })
        let usageField = optionalField("usage", usage)
        return LKAIServerSentEvent(
            event: "response.incomplete",
            data: #"{"type":"response.incomplete","response":{"id":"resp_1","object":"response","status":"incomplete"\#(incompleteDetailsField)\#(modelField),"output":[]\#(usageField)},"sequence_number":8}"#
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
