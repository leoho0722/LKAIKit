//
//  LKAIServerSentEvent+GeminiEvents.swift
//  LKAIGeminiTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport

// MARK: - Internal Method

/// Gemini Interactions API 串流各種事件的建構函式，給 `LKAIGeminiTests` 組出替身要推送的 SSE 事件
///
/// - Note: SSE 的 `event:` 名稱與 `data` 的 `event_type` 相同
extension LKAIServerSentEvent {

    /// 建立 `interaction.created` 事件，內容是一個剛建立、還在進行中的互動
    ///
    /// - Parameter model: 互動的 `model`；nil 表示不放這個鍵，預設不放
    /// - Returns: `interaction.created` 事件
    static func interactionCreated(model: String? = nil) -> LKAIServerSentEvent {
        let modelField = LKAITestJSON.optionalField("model", model.map { "\"\($0)\"" })
        return LKAIServerSentEvent(
            event: "interaction.created",
            data: #"{"event_type":"interaction.created","interaction":{"id":"int_1","status":"in_progress"\#(modelField)}}"#
        )
    }

    /// 建立 `interaction.status_update` 事件，表示互動的狀態改變
    ///
    /// - Parameter status: 新的狀態，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `interaction.status_update` 事件
    static func interactionStatusUpdate(status: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "interaction.status_update",
            data: #"{"event_type":"interaction.status_update","interaction_id":"int_1","status":"\#(status)"}"#
        )
    }

    /// 建立 `step.start` 事件，表示一個步驟開始
    ///
    /// - Parameters:
    ///   - index: 步驟的 `index`
    ///   - type: 步驟的 `step.type`，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    ///   - content: 步驟的 `content` JSON；nil 表示不放這個鍵，要放物件或陣列時照 JSON 寫
    ///   - summary: 步驟的 `summary` JSON；nil 表示不放這個鍵
    /// - Returns: `step.start` 事件
    static func stepStart(
        index: Int,
        type: String,
        content: String? = nil,
        summary: String? = nil
    ) -> LKAIServerSentEvent {
        let contentField = LKAITestJSON.optionalField("content", content)
        let summaryField = LKAITestJSON.optionalField("summary", summary)
        return LKAIServerSentEvent(
            event: "step.start",
            data: #"{"event_type":"step.start","index":\#(index),"step":{"type":"\#(type)"\#(contentField)\#(summaryField)}}"#
        )
    }

    /// 建立一段文字的 `step.delta` 事件，片段類型是 `text`
    ///
    /// - Parameters:
    ///   - index: 片段所屬步驟的 `index`
    ///   - text: 這一段的文字，直接放進 JSON 字串，所以不能含 `"` 或 `\`
    /// - Returns: `step.delta` 事件，`delta.type` 是 `text`
    static func stepDelta(index: Int, text: String) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "step.delta",
            data: #"{"event_type":"step.delta","index":\#(index),"delta":{"type":"text","text":"\#(text)"}}"#
        )
    }

    /// 建立思考簽章的 `step.delta` 事件，片段類型是 `thought_signature`
    ///
    /// - Parameter index: 片段所屬步驟的 `index`
    /// - Returns: `step.delta` 事件，`delta.type` 是 `thought_signature`，不帶 `text`
    static func thoughtSignatureDelta(index: Int) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "step.delta",
            data: #"{"event_type":"step.delta","index":\#(index),"delta":{"type":"thought_signature","signature":"c2lnbmF0dXJl"}}"#
        )
    }

    /// 建立 Google 搜尋結果的 `step.delta` 事件，片段類型是 `google_search_result`
    ///
    /// - Parameter index: 片段所屬步驟的 `index`
    /// - Returns: `step.delta` 事件；`delta.text` 是 JSON 物件 `{"items":[]}`，不是字串
    static func googleSearchResultDelta(index: Int) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "step.delta",
            data: #"{"event_type":"step.delta","index":\#(index),"delta":{"type":"google_search_result","text":{"items":[]}}}"#
        )
    }

    /// 建立 `step.stop` 事件，表示一個步驟結束
    ///
    /// - Parameter index: 結束的步驟的 `index`
    /// - Returns: `step.stop` 事件
    static func stepStop(index: Int) -> LKAIServerSentEvent {
        LKAIServerSentEvent(
            event: "step.stop",
            data: #"{"event_type":"step.stop","index":\#(index)}"#
        )
    }

    /// 建立 `interaction.completed` 事件，內容是結束時的互動
    ///
    /// - Parameters:
    ///   - status: 互動的 `status`；nil 表示不放這個鍵，預設是 `completed`
    ///   - model: 互動的 `model`；nil 表示不放這個鍵，預設是 `gemini-3.5-flash-lite`
    ///   - usage: 互動的 `usage` JSON；nil 表示不放這個鍵，要測 null 時傳 `"null"`
    ///   - errors: 互動的 `errors` JSON；nil 表示不放這個鍵
    /// - Returns: `interaction.completed` 事件
    static func interactionCompleted(
        status: String? = "completed",
        model: String? = "gemini-3.5-flash-lite",
        usage: String? = nil,
        errors: String? = nil
    ) -> LKAIServerSentEvent {
        let statusField = LKAITestJSON.optionalField("status", status.map { "\"\($0)\"" })
        let modelField = LKAITestJSON.optionalField("model", model.map { "\"\($0)\"" })
        let usageField = LKAITestJSON.optionalField("usage", usage)
        let errorsField = LKAITestJSON.optionalField("errors", errors)
        return LKAIServerSentEvent(
            event: "interaction.completed",
            data: #"{"event_type":"interaction.completed","interaction":{"id":"int_1"\#(statusField)\#(modelField)\#(usageField)\#(errorsField)}}"#
        )
    }
}
