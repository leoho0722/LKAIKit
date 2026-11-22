//
//  LKAnthropicClientTestSupport.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport

@testable import LKAIAnthropic

/// `LKAnthropicClient` 的測試共用固定資料與 helper：合法請求、以 SSE 事件建立 client 的 helper 與預期的結束事件
enum LKAnthropicClientTestSupport {

    // MARK: - Properties

    /// 共用的合法請求：模型、一則使用者訊息與輸出上限，沒有系統指示；內容與各測試要驗證的行為無關
    static let validRequest = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )
}

// MARK: - Internal Method

extension LKAnthropicClientTestSupport {

    /// 建立一個用固定 SSE 事件回應的 client：替身把事件逐行推送後結束
    ///
    /// - Parameter events: 依序送出的 SSE 事件
    /// - Returns: 呼叫時會得到這些事件的 client
    static func makeClient(events: [LKAIServerSentEvent]) -> LKAnthropicClient {
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: LKAIServerSentEventTestSupport.lines(of: events))
        mock.finish()
        return LKAnthropicClient(apiKey: "test-key", httpClient: mock)
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
