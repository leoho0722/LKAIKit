//
//  LKOpenAIClientStreamTests.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIOpenAI

/// `LKOpenAIClient` 串流事件對應的單元測試，以固定的 SSE 內容驗證文字、實際回應的模型與用量
struct LKOpenAIClientStreamTests {

    // spectra-scenario: openai-provider / Skip lifecycle and reasoning events
    // spectra-scenario: openai-provider / Skip lifecycle and reasoning events / stream with lifecycle and reasoning events
    /// 驗證串流有生命週期事件與推理摘要事件時，只交出回答的文字片段，再交出完成事件，其他事件都不產生事件
    @Test(.timeLimit(.minutes(1)))
    func stream_有生命週期與推理事件_只交出文字片段後完成() async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .responseCreated(),
            .responseInProgress(),
            .outputItemAdded(),
            .reasoningSummaryTextDelta("Thinking"),
            .outputTextDelta("Hel"),
            .outputTextDelta("lo"),
            .outputTextDone(),
            .responseCompleted(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            LKOpenAIClientTestSupport.finishedEvent(.completed),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: openai-provider / Fail on malformed event data
    /// 驗證第一則事件的資料損壞時，串流以無效回應錯誤失敗，不交出後面的文字與完成事件
    ///
    /// - Parameter malformedEvent: 損壞的第一則事件：資料不是合法的 JSON、
    ///   `response.output_text.delta` 沒有 `delta`、`response.completed` 沒有 `response`
    /// - Note: 損壞的事件後面接正常的文字與完成事件，略過損壞事件的實作會交出它們，測試就會失敗
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            LKAIServerSentEvent(event: nil, data: "not json"),
            LKAIServerSentEvent(
                event: "response.output_text.delta",
                data: #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"sequence_number":4}"#
            ),
            LKAIServerSentEvent(
                event: "response.completed",
                data: #"{"type":"response.completed","sequence_number":9}"#
            ),
        ] as [LKAIServerSentEvent]
    )
    func stream_事件資料損壞_丟出無效回應錯誤且不交出後面的事件(
        malformedEvent: LKAIServerSentEvent
    ) async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            malformedEvent,
            .outputTextDelta("Hel"),
            .responseCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events.isEmpty)
        #expect(isInvalidResponse(outcome.error))
    }

    // spectra-scenario: openai-provider / Report the model of the finished response
    /// 驗證完成事件的回應物件帶著 `gpt-6-luna-2026-09-01` 時，串流的結束事件記錄這個模型，不取 `response.created` 的模型
    @Test(.timeLimit(.minutes(1)))
    func stream_完成事件回報模型_結束事件記錄實際回應的模型() async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .responseCreated(),
            .responseCompleted(model: "gpt-6-luna-2026-09-01"),
        ])
        let expectedEvents = [
            LKOpenAIClientTestSupport.finishedEvent(
                .completed,
                respondingModel: "gpt-6-luna-2026-09-01"
            ),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: openai-provider / Report the model of the finished response
    /// 驗證完成事件的回應物件帶著 `gpt-6-luna-2026-09-01` 時，非串流的結果也記錄這個模型，並帶著串接好的文字
    @Test(.timeLimit(.minutes(1)))
    func invoke_完成事件回報模型_結果記錄實際回應的模型() async throws {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .responseCreated(),
            .outputTextDelta("Hi"),
            .responseCompleted(model: "gpt-6-luna-2026-09-01"),
        ])

        // When
        let response = try await client.invoke(LKOpenAIClientTestSupport.validRequest)

        // Then
        #expect(response.text == "Hi")
        #expect(response.completion.respondingModel == "gpt-6-luna-2026-09-01")
    }

    /// 驗證完成事件的回應物件沒有 `model` 時，結束事件不帶回應的模型，不改取 `response.created` 的模型
    ///
    /// - Note: 對應 openai-provider 的「Responding model」需求中「回應物件沒有 `model` 時不回報模型」的分支，規格沒有為它另寫情境
    @Test(.timeLimit(.minutes(1)))
    func stream_完成事件沒有model_結束事件的回應模型為nil() async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .responseCreated(),
            .responseCompleted(model: nil),
        ])
        let expectedEvents = [
            LKOpenAIClientTestSupport.finishedEvent(.completed, respondingModel: nil),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: openai-provider / Map the usage of the finished response
    // spectra-scenario: openai-provider / Map the usage of the finished response / usage values
    /// 驗證完成事件的 `usage` 對應成預期的用量：細項沒有回報時對應的數量為 nil，`usage` 是 null 或缺少輸入或輸出數量時沒有用量
    ///
    /// - Parameter testCase: 一列範例：完成事件的 `usage` JSON，以及預期的用量；nil 表示結束事件不帶用量
    /// - Note: 輸入總數與輸出總數照 `input_tokens`、`output_tokens` 取值，不把快取與推理再加進去
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            UsageCase(
                usageJSON: #"{"input_tokens":120,"input_tokens_details":{"cached_tokens":100},"output_tokens":45,"output_tokens_details":{"reasoning_tokens":30},"total_tokens":165}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 120,
                    outputTokens: 45,
                    cachedInputTokens: 100,
                    reasoningOutputTokens: 30
                )
            ),
            UsageCase(
                usageJSON: #"{"input_tokens":12,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":17}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 12,
                    outputTokens: 5,
                    cachedInputTokens: 0,
                    reasoningOutputTokens: 0
                )
            ),
            UsageCase(
                usageJSON: #"{"input_tokens":12,"output_tokens":5,"total_tokens":17}"#,
                expectedUsage: LKAIUsage(
                    inputTokens: 12,
                    outputTokens: 5,
                    cachedInputTokens: nil,
                    reasoningOutputTokens: nil
                )
            ),
            UsageCase(usageJSON: "null", expectedUsage: nil),
            UsageCase(usageJSON: #"{"output_tokens":5}"#, expectedUsage: nil),
        ] as [UsageCase]
    )
    func stream_各種usage值_結束事件帶預期的用量(testCase: UsageCase) async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .outputTextDelta("Hel"),
            .responseCompleted(usage: testCase.usageJSON),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            LKOpenAIClientTestSupport.finishedEvent(.completed, usage: testCase.expectedUsage),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: openai-provider / Map terminal events
    // spectra-scenario: openai-provider / Map terminal events / terminal events
    // spectra-scenario: chat-client / Provider reports a full context window as the output token limit
    /// 驗證第一個結束事件決定結果：文字 "Hel" 之後，依拒答事件與結束事件交出完成事件或丟出錯誤，之後再來的 `response.completed` 不處理
    ///
    /// - Parameter testCase: 一列範例：結束事件之前的拒答事件、第一個結束事件，以及預期的事件與錯誤
    /// - Note: 每列在第一個結束事件之後都再接一個 `response.completed`，結束事件沒有結束串流時，它會多交出一個完成事件
    /// - Note: 拒答與 `content_filter` 比對完整的錯誤，兩種無效回應只比對是不是無效回應，原因文字不比對
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            TerminalEventCase(
                refusalEvents: [],
                terminalEvent: .responseCompleted(),
                expectedEvents: [
                    .textDelta("Hel"),
                    LKOpenAIClientTestSupport.finishedEvent(.completed),
                ],
                expectedError: nil
            ),
            TerminalEventCase(
                refusalEvents: [
                    .refusalDelta("I'm sorry,"),
                    .refusalDelta(" I can't help with that."),
                ],
                terminalEvent: .responseCompleted(),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.refused(detail: "I'm sorry, I can't help with that."))
            ),
            TerminalEventCase(
                refusalEvents: [.refusalDone("I can't help with that.")],
                terminalEvent: .responseCompleted(),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.refused(detail: "I can't help with that."))
            ),
            TerminalEventCase(
                refusalEvents: [.refusalDelta(""), .refusalDone("I can't help with that.")],
                terminalEvent: .responseCompleted(),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.refused(detail: "I can't help with that."))
            ),
            TerminalEventCase(
                refusalEvents: [],
                terminalEvent: .responseIncomplete(reason: "max_output_tokens"),
                expectedEvents: [
                    .textDelta("Hel"),
                    LKOpenAIClientTestSupport.finishedEvent(.maxOutputTokens),
                ],
                expectedError: nil
            ),
            TerminalEventCase(
                refusalEvents: [],
                terminalEvent: .responseIncomplete(reason: "content_filter"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .error(.refused(detail: "content_filter"))
            ),
            TerminalEventCase(
                refusalEvents: [],
                terminalEvent: .responseIncomplete(reason: "max_messages"),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse
            ),
            TerminalEventCase(
                refusalEvents: [],
                terminalEvent: .responseIncomplete(reason: nil),
                expectedEvents: [.textDelta("Hel")],
                expectedError: .invalidResponse
            ),
        ] as [TerminalEventCase]
    )
    func stream_各種結束事件_依第一個結束事件交出完成事件或錯誤(
        testCase: TerminalEventCase
    ) async {
        // Given
        let events: [LKAIServerSentEvent] = [.outputTextDelta("Hel")]
            + testCase.refusalEvents
            + [testCase.terminalEvent, .responseCompleted()]
        let client = LKOpenAIClientTestSupport.makeClient(events: events)

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == testCase.expectedEvents)
        switch testCase.expectedError {
        case nil:
            #expect(outcome.error == nil)

        case .error(let expectedError)?:
            #expect(outcome.error == expectedError)

        case .invalidResponse?:
            #expect(isInvalidResponse(outcome.error))
        }
    }

    // spectra-scenario: openai-provider / Non-streaming call refused after partial text
    /// 驗證回答到一半被拒答時，非串流呼叫以拒答錯誤失敗，原因是拒答的文字，不回傳結果
    ///
    /// - Note: 已產生的文字 "Sure" 不會出現在結果裡，因為呼叫沒有回傳結果
    @Test(.timeLimit(.minutes(1)))
    func invoke_產生部分文字後拒答_丟出拒答錯誤且不回傳結果() async throws {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .outputTextDelta("Sure"),
            .refusalDelta("I can't help with that."),
            .responseCompleted(),
        ])

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKOpenAIClientTestSupport.validRequest,
            mode: .invoke
        )

        // Then
        let error = try #require(actualError)
        #expect(error == .refused(detail: "I can't help with that."))
    }

    /// 驗證拒答同時有 delta 與 done 時，拒答文字以 delta 串接為準，不接上也不改用 done 的文字
    ///
    /// - Note: 對應 openai-provider 的「Finish and refusal mapping」需求中拒答文字的規則
    /// - Note: delta 依序串接後不為空時只用 delta；串接後為空時，才改用 `response.refusal.done`
    /// - Note: 這是實際串流最常見的形狀：幾則 delta 之後接一則 done
    /// - Note: done 刻意用與 delta 串接結果不同的文字，兩種來源都被串接，或改以 done 為準時，原因文字就會與期望值不同
    @Test(.timeLimit(.minutes(1)))
    func stream_拒答同時有delta與done_原因以delta串接為準() async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .outputTextDelta("Hel"),
            .refusalDelta("I'm sorry,"),
            .refusalDelta(" I can't help with that."),
            .refusalDone("Final refusal."),
            .responseCompleted(),
        ])
        let expectedError = LKAIError.refused(detail: "I'm sorry, I can't help with that.")

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        #expect(outcome.error == expectedError)
    }

    /// 驗證回應以輸出上限未完成且帶用量時，結束事件的結束原因是輸出上限，並帶著用量
    ///
    /// - Note: 對應 openai-provider 的「Usage mapping」需求：用量取自結束串流的事件，`response.incomplete` 也算
    /// - Note: 模擬推理模型把輸出上限全用在推理、沒有可見輸出的情況，所以事件裡沒有文字
    @Test(.timeLimit(.minutes(1)))
    func stream_以輸出上限未完成且帶用量_結束事件帶輸出上限原因與用量() async {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .responseIncomplete(
                reason: "max_output_tokens",
                usage: #"{"input_tokens":12,"output_tokens":4096,"output_tokens_details":{"reasoning_tokens":4096}}"#
            ),
        ])
        let expectedUsage = LKAIUsage(
            inputTokens: 12,
            outputTokens: 4096,
            cachedInputTokens: nil,
            reasoningOutputTokens: 4096
        )
        let expectedEvents = [
            LKOpenAIClientTestSupport.finishedEvent(.maxOutputTokens, usage: expectedUsage),
        ]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }
}

// MARK: - Nested Types

extension LKOpenAIClientStreamTests {

    /// 結束事件範例表的一列：結束事件之前的拒答事件、第一個結束事件，以及預期的事件與錯誤
    struct TerminalEventCase: Sendable {

        /// 文字 "Hel" 之後、第一個結束事件之前送出的拒答事件；沒有拒答時為空陣列
        let refusalEvents: [LKAIServerSentEvent]

        /// 第一個結束事件，`response.completed` 或 `response.incomplete`
        let terminalEvent: LKAIServerSentEvent

        /// 預期交出的全部事件
        let expectedEvents: [LKAIChatStreamEvent]

        /// 預期的錯誤；nil 表示預期沒有錯誤
        let expectedError: ErrorExpectation?
    }

    /// 結束事件的預期錯誤：指定的錯誤，或只要求是無效回應
    enum ErrorExpectation: Sendable {

        /// 丟出的錯誤必須等於指定的錯誤
        ///
        /// - Parameter error: 預期的錯誤
        case error(LKAIError)

        /// 丟出的錯誤必須是無效回應，原因文字不比對
        case invalidResponse
    }

    /// 用量範例表的一列：完成事件的 `usage` JSON，以及預期的用量
    struct UsageCase {

        /// 放進完成事件的 `usage` JSON 文字，null 寫成 `null`
        let usageJSON: String

        /// 預期結束事件帶的用量；nil 表示結束事件不帶用量
        let expectedUsage: LKAIUsage?
    }
}

// MARK: - Private Method

private extension LKOpenAIClientStreamTests {

    /// 判斷錯誤是不是無效回應錯誤，只看種類，不看原因文字
    ///
    /// - Parameter error: 要判斷的錯誤；沒有錯誤時為 nil
    /// - Returns: 是無效回應錯誤時為 `true`
    func isInvalidResponse(_ error: LKAIError?) -> Bool {
        if case .invalidResponse = error {
            return true
        }
        return false
    }
}
