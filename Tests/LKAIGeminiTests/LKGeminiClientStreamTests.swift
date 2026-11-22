//
//  LKGeminiClientStreamTests.swift
//  LKAIGeminiTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIGemini

/// `LKGeminiClient` 串流事件對應的單元測試，以固定的 SSE 內容驗證文字、結束原因、實際回應的模型與用量
struct LKGeminiClientStreamTests {

    // spectra-scenario: gemini-provider / Skip lifecycle and thought events
    // spectra-scenario: gemini-provider / Skip lifecycle and thought events / stream with lifecycle events and a thought step
    /// 驗證串流有生命週期事件、思考步驟與不是文字的步驟時，只交出回答步驟的文字片段，再交出完成事件
    ///
    /// - Note: 思考步驟的文字片段與 `google_search_call` 步驟的內容、結果都不交出
    /// - Note: `google_search_call` 的 `content` 與 `google_search_result` 的 `text`
    ///   都是 JSON 物件，不是陣列與字串，不論步驟類型都去解它們的實作會在這裡失敗
    @Test(.timeLimit(.minutes(1)))
    func stream_有生命週期與思考事件_只交出回答的文字片段後完成() async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .interactionCreated(),
            .interactionStatusUpdate(status: "in_progress"),
            .stepStart(index: 0, type: "thought"),
            .thoughtSignatureDelta(index: 0),
            .stepDelta(index: 0, text: "Thinking"),
            .stepStop(index: 0),
            .stepStart(index: 1, type: "model_output"),
            .stepDelta(index: 1, text: "Hel"),
            .stepDelta(index: 1, text: "lo"),
            .stepStop(index: 1),
            .stepStart(
                index: 2,
                type: "google_search_call",
                content: #"{"queries":["sky colour"]}"#
            ),
            .googleSearchResultDelta(index: 2),
            .stepStop(index: 2),
            .interactionCompleted(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            LKGeminiClientTestSupport.finishedEvent(.completed),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: gemini-provider / Deliver text carried by the start of a model output step
    // spectra-scenario: gemini-provider / Deliver text carried by the start of a model output step / text in the start of a model output step
    /// 驗證回答步驟開始時就帶著文字內容時，先交出那段文字，再依序交出後面片段的文字；思考步驟帶的摘要不交出
    @Test(.timeLimit(.minutes(1)))
    func stream_回答步驟開始時帶內容_依序交出內容與片段的文字() async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .stepStart(index: 0, type: "thought", summary: #"[{"type":"text","text":"Thinking"}]"#),
            .stepStop(index: 0),
            .stepStart(index: 1, type: "model_output", content: #"[{"type":"text","text":"Hel"}]"#),
            .stepDelta(index: 1, text: "lo"),
            .stepStop(index: 1),
            .interactionCompleted(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            LKGeminiClientTestSupport.finishedEvent(.completed),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: gemini-provider / Fail on malformed event data
    /// 驗證第一則事件的資料不是合法的 JSON 時，串流以無效回應錯誤失敗，不交出後面的文字與完成事件
    ///
    /// - Note: 損壞的事件後面接正常的文字與完成事件，略過損壞事件的實作會交出它們，測試就會失敗
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test(.timeLimit(.minutes(1)))
    func stream_事件資料損壞_丟出無效回應錯誤且不交出後面的事件() async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            LKAIServerSentEvent(event: nil, data: "not json"),
            .stepStart(index: 1, type: "model_output"),
            .stepDelta(index: 1, text: "Hel"),
            .interactionCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events.isEmpty)
        #expect(LKAIErrorTestSupport.isInvalidResponse(outcome.error))
    }

    // spectra-scenario: gemini-provider / Fail on events missing required fields
    // spectra-scenario: gemini-provider / Fail on events missing required fields / events missing required fields
    /// 驗證事件缺少必要欄位或欄位型別不對時，串流以無效回應錯誤失敗，不交出後面的文字與完成事件
    ///
    /// - Parameter brokenEvent: 有問題的事件，依序是缺少 `event_type`、`step.start` 缺少 `index`、
    ///   缺少 `step.type`、文字內容缺少 `text`，`step.delta` 缺少 `index`、缺少 `delta.type`、
    ///   文字片段缺少 `text`、`text` 不是字串，以及 `text` 是 null
    /// - Note: 有問題的事件放在回答步驟開始之後、文字片段之前，略過它的實作會交出後面的 "Hel"，測試就會失敗
    /// - Note: 最後兩列的 `index` 是 3，沒有任何 `step.start` 記錄過，也一樣要失敗
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            LKAIServerSentEvent(
                event: nil,
                data: #"{"index":2,"step":{"type":"model_output"}}"#
            ),
            LKAIServerSentEvent(
                event: "step.start",
                data: #"{"event_type":"step.start","step":{"type":"model_output"}}"#
            ),
            LKAIServerSentEvent(
                event: "step.start",
                data: #"{"event_type":"step.start","index":2,"step":{}}"#
            ),
            LKAIServerSentEvent(
                event: "step.start",
                data: #"{"event_type":"step.start","index":2,"step":{"type":"model_output","content":[{"type":"text"}]}}"#
            ),
            LKAIServerSentEvent(
                event: "step.delta",
                data: #"{"event_type":"step.delta","delta":{"type":"text","text":"x"}}"#
            ),
            LKAIServerSentEvent(
                event: "step.delta",
                data: #"{"event_type":"step.delta","index":1,"delta":{"text":"x"}}"#
            ),
            LKAIServerSentEvent(
                event: "step.delta",
                data: #"{"event_type":"step.delta","index":1,"delta":{"type":"text"}}"#
            ),
            LKAIServerSentEvent(
                event: "step.delta",
                data: #"{"event_type":"step.delta","index":3,"delta":{"type":"text","text":5}}"#
            ),
            LKAIServerSentEvent(
                event: "step.delta",
                data: #"{"event_type":"step.delta","index":3,"delta":{"type":"text","text":null}}"#
            ),
        ] as [LKAIServerSentEvent]
    )
    func stream_事件缺少必要欄位_丟出無效回應錯誤且不交出後面的事件(
        brokenEvent: LKAIServerSentEvent
    ) async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .stepStart(index: 1, type: "model_output"),
            brokenEvent,
            .stepDelta(index: 1, text: "Hel"),
            .interactionCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events.isEmpty)
        #expect(LKAIErrorTestSupport.isInvalidResponse(outcome.error))
    }

    // spectra-scenario: gemini-provider / Map terminal events
    // spectra-scenario: gemini-provider / Map terminal events / terminal events
    /// 驗證第一個 `interaction.completed` 事件決定結果：文字 "Hel" 之後，依它的狀態交出完成事件或丟出錯誤，
    /// 之後再來的 `interaction.completed` 不處理
    ///
    /// - Parameter testCase: 一列範例：第一個 `interaction.completed` 事件，以及預期的事件與錯誤
    /// - Note: 每列在第一個結束事件之後都再接一個狀態是 `completed` 的事件，
    ///   結束事件沒有結束串流時，它會多交出一個完成事件
    /// - Note: 無效回應只比對是不是無效回應，原因文字不比對
    /// - Note: 狀態是 `failed` 的六列，依 `errors` 的第一筆的代碼分類；沒有、null 與空陣列的 `errors`
    ///   都視同沒有代碼；第一筆的 `code` 是數字時，`errors` 解不出來，是無效回應
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            TerminalEventCase(
                terminalEvent: .interactionCompleted(),
                expectedEvents: [
                    .textDelta("Hel"),
                    LKGeminiClientTestSupport.finishedEvent(.completed),
                ],
                expectedError: nil
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(errors: #""none""#),
                expectedEvents: [
                    .textDelta("Hel"),
                    LKGeminiClientTestSupport.finishedEvent(.completed),
                ],
                expectedError: nil
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "incomplete"),
                expectedEvents: [
                    .textDelta("Hel"),
                    LKGeminiClientTestSupport.finishedEvent(.maxOutputTokens),
                ],
                expectedError: nil
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "requires_action"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse(containing: [])
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "cancelled"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse(containing: [])
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: nil),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse(containing: [])
            ),
            TerminalEventCase(
                terminalEvent: LKAIServerSentEvent(
                    event: "interaction.completed",
                    data: #"{"event_type":"interaction.completed"}"#
                ),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse(containing: [])
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(
                    status: "failed",
                    errors: #"[{"code":"safety","message":"Blocked."}]"#
                ),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.refused(detail: "safety"))
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(
                    status: "failed",
                    errors: #"[{"code":"api_error","message":"Internal error."}]"#
                ),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "failed"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "failed", errors: "null"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(status: "failed", errors: "[]"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
            ),
            TerminalEventCase(
                terminalEvent: .interactionCompleted(
                    status: "failed",
                    errors: #"[{"code":500,"message":"Internal error."}]"#
                ),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse(containing: [])
            ),
        ] as [TerminalEventCase]
    )
    func stream_各種結束事件_依第一個interactionCompleted交出完成事件或錯誤(
        testCase: TerminalEventCase
    ) async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .stepStart(index: 0, type: "model_output"),
            .stepDelta(index: 0, text: "Hel"),
            testCase.terminalEvent,
            .interactionCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == testCase.expectedEvents)
        switch testCase.expectedError {
        case nil:
            #expect(outcome.error == nil)

        case .some(let expectedError):
            #expect(expectedError.matches(outcome.error))
        }
    }

    // spectra-scenario: gemini-provider / Finish at the output token limit while still thinking
    /// 驗證只有思考步驟、沒有回答步驟就以 `incomplete` 結束時，非串流呼叫的結果文字是空字串，結束原因是輸出上限
    @Test(.timeLimit(.minutes(1)))
    func invoke_只有思考就達到輸出上限_文字為空且結束原因為輸出上限() async throws {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .interactionCreated(),
            .stepStart(index: 0, type: "thought"),
            .thoughtSignatureDelta(index: 0),
            .stepStop(index: 0),
            .interactionCompleted(status: "incomplete"),
        ])

        // When
        let response = try await client.invoke(LKGeminiClientTestSupport.validRequest)

        // Then
        #expect(response.text == "")
        #expect(response.completion.finishReason == .maxOutputTokens)
    }

    // spectra-scenario: gemini-provider / Report the model of the completed interaction
    /// 驗證完成事件的互動帶著 `gemini-3.6-flash` 時，串流的結束事件記錄這個模型，不取請求用的 `gemini-3.5-flash`
    ///
    /// - Note: `interaction.created` 不帶 `model`，只有 `interaction.completed` 帶，才分得出實作取的是哪一則
    @Test(.timeLimit(.minutes(1)))
    func stream_完成事件回報模型_結束事件記錄實際回應的模型() async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .interactionCreated(),
            .interactionCompleted(model: "gemini-3.6-flash"),
        ])
        let request = LKAIChatRequest(
            model: "gemini-3.5-flash",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 1024
        )
        let expectedEvents = [
            LKGeminiClientTestSupport.finishedEvent(
                .completed,
                respondingModel: "gemini-3.6-flash"
            ),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: request
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: gemini-provider / Map the usage of the completed interaction
    // spectra-scenario: gemini-provider / Map the usage of the completed interaction / usage values
    /// 驗證完成事件的 `usage` 對應成預期的用量：輸出數量是輸出加上思考，細項沒有回報時對應的數量為 nil，
    /// `usage` 是 null 或缺少輸入或輸出數量時沒有用量
    ///
    /// - Parameter testCase: 一列範例：完成事件的 `usage` JSON，以及預期的用量；nil 表示結束事件不帶用量
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            UsageCase(
                usageJSON: #"{"total_input_tokens":41,"total_cached_tokens":0,"total_output_tokens":3,"total_thought_tokens":528,"total_tokens":572}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 41,
                    outputTokens: 531,
                    cachedInputTokens: 0,
                    reasoningOutputTokens: 528
                )
            ),
            UsageCase(
                usageJSON: #"{"total_input_tokens":5000,"total_cached_tokens":2033,"total_output_tokens":10,"total_thought_tokens":0,"total_tokens":5010}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 5000,
                    outputTokens: 10,
                    cachedInputTokens: 2033,
                    reasoningOutputTokens: 0
                )
            ),
            UsageCase(
                usageJSON: #"{"total_input_tokens":12,"total_output_tokens":5,"total_tokens":17}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 12,
                    outputTokens: 5,
                    cachedInputTokens: nil,
                    reasoningOutputTokens: nil
                )
            ),
            UsageCase(usageJSON: "null", expectedUsage: nil),
            UsageCase(usageJSON: #"{"total_output_tokens":5}"#, expectedUsage: nil),
        ] as [UsageCase]
    )
    func stream_各種usage值_結束事件帶預期的用量(testCase: UsageCase) async {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .stepStart(index: 0, type: "model_output"),
            .stepDelta(index: 0, text: "Hel"),
            .interactionCompleted(usage: testCase.usageJSON),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            LKGeminiClientTestSupport.finishedEvent(.completed, usage: testCase.expectedUsage),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }
}

// MARK: - Nested Types

extension LKGeminiClientStreamTests {

    /// 結束事件範例表的一列：第一個 `interaction.completed` 事件，以及預期的事件與錯誤
    struct TerminalEventCase: Sendable {

        /// 文字 "Hel" 之後送出的第一個 `interaction.completed` 事件
        let terminalEvent: LKAIServerSentEvent

        /// 預期交出的全部事件
        let expectedEvents: [LKAIChatStreamEvent]

        /// 預期的錯誤；nil 表示預期沒有錯誤
        let expectedError: LKAIErrorTestSupport.Expectation?
    }

    /// 用量範例表的一列：完成事件的 `usage` JSON，以及預期的用量
    struct UsageCase {

        /// 放進完成事件的 `usage` JSON 文字，null 寫成 `null`
        let usageJSON: String

        /// 預期結束事件帶的用量；nil 表示結束事件不帶用量
        let expectedUsage: LKAIUsage?
    }
}
