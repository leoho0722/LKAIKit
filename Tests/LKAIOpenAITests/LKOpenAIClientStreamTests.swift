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
    /// - Parameter malformedEvent: 損壞的第一則事件：資料不是合法的 JSON、`response.output_text.delta` 沒有 `delta`、`response.completed` 沒有 `response`
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
}

// MARK: - Nested Types

extension LKOpenAIClientStreamTests {

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
