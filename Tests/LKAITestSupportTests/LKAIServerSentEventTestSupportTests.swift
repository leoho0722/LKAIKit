//
//  LKAIServerSentEventTestSupportTests.swift
//  LKAITestSupportTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

/// `LKAIServerSentEventTestSupport` 的單元測試，檢查 SSE 事件轉成逐行內容的結果
struct LKAIServerSentEventTestSupportTests {

    /// 驗證有名稱的事件輸出 `event:` 與 `data:` 兩行，沒有名稱的只輸出 `data:` 一行，每個事件後接一個空行，多個事件依原順序接起來
    ///
    /// - Parameter testCase: 這一列的事件與預期的逐行內容
    @Test(arguments: [
        LinesCase(
            events: [
                LKAIServerSentEvent(event: "message_start", data: #"{"type":"message_start"}"#),
            ],
            expectedLines: ["event: message_start", #"data: {"type":"message_start"}"#, ""]
        ),
        LinesCase(
            events: [LKAIServerSentEvent(event: nil, data: #"{"type":"response.created"}"#)],
            expectedLines: [#"data: {"type":"response.created"}"#, ""]
        ),
        LinesCase(
            events: [
                LKAIServerSentEvent(event: "ping", data: #"{"type":"ping"}"#),
                LKAIServerSentEvent(event: nil, data: #"{"type":"response.created"}"#),
            ],
            expectedLines: [
                "event: ping",
                #"data: {"type":"ping"}"#,
                "",
                #"data: {"type":"response.created"}"#,
                "",
            ]
        ),
    ])
    func lines_事件名稱有值或為nil_依序輸出對應的逐行內容(testCase: LinesCase) {
        // Given
        let events = testCase.events

        // When
        let actualLines = LKAIServerSentEventTestSupport.lines(of: events)

        // Then
        #expect(actualLines == testCase.expectedLines)
    }
}

// MARK: - Nested Types

extension LKAIServerSentEventTestSupportTests {

    /// 一列測試參數：依序要轉換的 SSE 事件，以及預期的逐行內容
    struct LinesCase: Sendable {

        /// 依序要轉換的 SSE 事件
        let events: [LKAIServerSentEvent]

        /// 預期的逐行內容，每一行都不含 CR 與 LF
        let expectedLines: [String]
    }
}
