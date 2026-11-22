//
//  LKAnthropicClientTestSupport.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport

@testable import LKAIAnthropic

/// `LKAnthropicClient` 的測試共用固定資料與 helper：合法請求、SSE 事件的建構與預期的結束事件
enum LKAnthropicClientTestSupport {

    // MARK: - Properties

    /// 共用的合法請求：模型、一則使用者訊息與輸出上限，沒有系統指示；內容與各測試要驗證的行為無關
    static let validRequest = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )
}

// MARK: - Nested Types

extension LKAnthropicClientTestSupport {

    /// SSE 的一個事件：事件名稱，以及 `data` 的 JSON 文字；下方的建構函式對應 Messages API 串流的各種事件
    struct SSEEvent {

        /// `event:` 那一行的事件名稱
        let name: String

        /// `data:` 那一行的 JSON 文字
        let data: String

        /// 建立 `message_start` 事件，內容是一則還沒有任何內容的助理訊息
        ///
        /// - Parameters:
        ///   - model: 訊息的模型識別碼
        ///   - usage: 訊息的 `usage` JSON；nil 表示不放這個鍵
        /// - Returns: `message_start` 事件
        static func messageStart(
            model: String = "claude-opus-5-5",
            usage: String? = nil
        ) -> SSEEvent {
            let usageField = optionalField("usage", usage)
            return SSEEvent(
                name: "message_start",
                data: #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"\#(model)","stop_reason":null,"stop_sequence":null\#(usageField)}}"#
            )
        }

        /// 建立開始一個文字區塊的 `content_block_start` 事件
        ///
        /// - Parameter index: 區塊的序號
        /// - Returns: `content_block_start` 事件，區塊類型是 `text`
        static func textBlockStart(index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_start",
                data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"text","text":""}}"#
            )
        }

        /// 建立一段文字的 `content_block_delta` 事件
        ///
        /// - Parameters:
        ///   - text: 這一段的文字
        ///   - index: 所屬區塊的序號
        /// - Returns: `content_block_delta` 事件，增量類型是 `text_delta`
        static func textDelta(_ text: String, index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_delta",
                data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"text_delta","text":"\#(text)"}}"#
            )
        }

        /// 建立結束一個區塊的 `content_block_stop` 事件
        ///
        /// - Parameter index: 區塊的序號
        /// - Returns: `content_block_stop` 事件
        static func blockStop(index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_stop",
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
        ) -> SSEEvent {
            let stopReasonJSON = stopReason.map { "\"\($0)\"" } ?? "null"
            let stopDetailsField = optionalField("stop_details", stopDetails)
            let usageField = optionalField("usage", usage)
            return SSEEvent(
                name: "message_delta",
                data: #"{"type":"message_delta","delta":{"stop_reason":\#(stopReasonJSON),"stop_sequence":null\#(stopDetailsField)}\#(usageField)}"#
            )
        }

        /// 建立 `message_stop` 事件，表示整則訊息結束
        ///
        /// - Returns: `message_stop` 事件
        static func messageStop() -> SSEEvent {
            SSEEvent(name: "message_stop", data: #"{"type":"message_stop"}"#)
        }

        /// 建立開始一個思考區塊的 `content_block_start` 事件
        ///
        /// - Parameter index: 區塊的序號
        /// - Returns: `content_block_start` 事件，區塊類型是 `thinking`
        static func thinkingBlockStart(index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_start",
                data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"thinking","thinking":""}}"#
            )
        }

        /// 建立思考內容為空的 `content_block_delta` 事件
        ///
        /// - Parameter index: 所屬區塊的序號
        /// - Returns: `content_block_delta` 事件，增量類型是 `thinking_delta`
        static func thinkingDelta(index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_delta",
                data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"thinking_delta","thinking":""}}"#
            )
        }

        /// 建立 `ping` 事件，用來保持連線，不帶任何內容
        ///
        /// - Returns: `ping` 事件
        static func ping() -> SSEEvent {
            SSEEvent(name: "ping", data: #"{"type": "ping"}"#)
        }

        /// 建立思考簽章的 `content_block_delta` 事件
        ///
        /// - Parameter index: 所屬區塊的序號
        /// - Returns: `content_block_delta` 事件，增量類型是 `signature_delta`
        static func signatureDelta(index: Int = 0) -> SSEEvent {
            SSEEvent(
                name: "content_block_delta",
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
        static func fallbackBlockStart(index: Int, from: String, to: String) -> SSEEvent {
            SSEEvent(
                name: "content_block_start",
                data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"fallback","from":{"model":"\#(from)"},"to":{"model":"\#(to)"}}}"#
            )
        }

        /// 組出 JSON 物件裡可有可無的欄位，前面帶逗號，接在其他欄位之後
        ///
        /// - Parameters:
        ///   - name: 欄位名稱
        ///   - json: 欄位值的 JSON；nil 表示不放這個欄位
        /// - Returns: `,"名稱":值`；沒有值時為空字串
        private static func optionalField(_ name: String, _ json: String?) -> String {
            guard let json else {
                return ""
            }
            return ",\"\(name)\":\(json)"
        }
    }
}

// MARK: - Internal Method

extension LKAnthropicClientTestSupport {

    /// 建立一個用固定 SSE 事件回應的 client：替身把事件逐行推送後結束
    ///
    /// - Parameter events: 依序送出的 SSE 事件
    /// - Returns: 呼叫時會得到這些事件的 client
    static func makeClient(events: [SSEEvent]) -> LKAnthropicClient {
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: lines(of: events))
        mock.finish()
        return LKAnthropicClient(apiKey: "test-key", httpClient: mock)
    }

    /// 把 SSE 事件轉成逐行內容：每個事件是 `event:`、`data:` 與一個空行三行
    ///
    /// - Parameter events: 依序排列的 SSE 事件
    /// - Returns: 不含 CR 與 LF 的每一行
    static func lines(of events: [SSEEvent]) -> [String] {
        events.flatMap { ["event: \($0.name)", "data: \($0.data)", ""] }
    }

    /// 建立預期的結束事件，用來寫期望值；模型預設是 `message_start` 預設的模型
    ///
    /// - Parameters:
    ///   - finishReason: 預期的結束原因
    ///   - usage: 預期的用量；預設沒有
    ///   - respondingModel: 預期實際回應的模型
    /// - Returns: 帶著這些內容的結束事件
    static func finishedEvent(
        _ finishReason: LKAIFinishReason,
        usage: LKAIUsage? = nil,
        respondingModel: String = "claude-opus-5-5"
    ) -> LKAIChatStreamEvent {
        .finished(
            LKAIChatCompletion(
                finishReason: finishReason,
                usage: usage,
                respondingModel: respondingModel
            )
        )
    }
}
