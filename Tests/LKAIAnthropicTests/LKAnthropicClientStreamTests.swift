//
//  LKAnthropicClientStreamTests.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIAnthropic

/// `LKAnthropicClient` 串流事件對應的單元測試，以固定的 SSE 內容驗證文字、結束原因、用量與實際回應的模型
struct LKAnthropicClientStreamTests {

    // MARK: - Properties

    /// 多個測試共用的合法請求，內容與事件對應無關
    private let validRequest = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )

    // spectra-scenario: chat-client / Stream a response that completes normally
    /// 驗證供應商依序產生 "Hel"、"lo" 後正常結束時，串流依序交出兩段文字與完成事件，之後正常結束
    @Test(.timeLimit(.minutes(1)))
    func stream_文字Hel與lo後正常結束_依序交出兩段文字與完成事件() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Hel"),
            textDelta("lo"),
            blockStop(),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            finishedEvent(.completed),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Skip thinking deltas and ping events
    // spectra-scenario: anthropic-provider / Skip thinking deltas and ping events / stream with thinking and ping
    /// 驗證串流有思考區塊與 `ping` 事件時，只交出文字區塊的文字，再交出完成事件，思考內容與 `ping` 都不產生事件
    @Test(.timeLimit(.minutes(1)))
    func stream_有思考區塊與ping_只交出文字區塊的文字後完成() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            thinkingBlockStart(),
            thinkingDelta(),
            blockStop(),
            ping(),
            textBlockStart(index: 1),
            textDelta("Hel", index: 1),
            textDelta("lo", index: 1),
            blockStop(index: 1),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            finishedEvent(.completed),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    /// 驗證 `signature_delta` 與不認得的事件類型都被略過，不產生事件，也不影響後面的文字與完成事件
    @Test(.timeLimit(.minutes(1)))
    func stream_有signatureDelta與不認得的事件_略過後照常交出文字() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            thinkingBlockStart(),
            thinkingDelta(),
            signatureDelta(),
            blockStop(),
            SSEEvent(name: "future_event", data: #"{"type":"future_event"}"#),
            textBlockStart(index: 1),
            textDelta("Hi", index: 1),
            blockStop(index: 1),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hi"),
            finishedEvent(.completed),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Map stop reasons
    // spectra-scenario: anthropic-provider / Map stop reasons / stop reasons
    /// 驗證 `end_turn`、`stop_sequence`、`max_tokens` 與 `model_context_window_exceeded` 各自對應的結束原因
    ///
    /// - Parameters:
    ///   - stopReason: `message_delta` 回報的 `stop_reason`
    ///   - expectedFinishReason: 結束事件預期帶的結束原因
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            ("end_turn", .completed),
            ("stop_sequence", .completed),
            ("max_tokens", .maxOutputTokens),
            ("model_context_window_exceeded", .contextWindowExceeded),
        ] as [(String, LKAIFinishReason)]
    )
    func stream_stopReason會正常完成_交出對應結束原因的結束事件(
        stopReason: String,
        expectedFinishReason: LKAIFinishReason
    ) async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(stopReason: stopReason),
            messageStop(),
        ])
        let expectedEvents = [finishedEvent(expectedFinishReason)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Map stop reasons
    // spectra-scenario: anthropic-provider / Map stop reasons / stop reasons
    /// 驗證 `refusal` 丟出拒答錯誤，原因是 `stop_details` 的類別；沒有 `stop_details` 或類別為 null 時沒有原因
    ///
    /// - Parameters:
    ///   - stopDetails: `message_delta` 的 `stop_details` JSON；nil 表示不放這個鍵
    ///   - expectedDetail: 拒答錯誤預期帶的原因
    /// - Note: 拒答不交出結束事件，所以事件陣列是空的
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            (#"{"type":"refusal","category":"cyber"}"#, "cyber"),
            (nil, nil),
            (#"{"type":"refusal","category":null}"#, nil),
        ] as [(String?, String?)]
    )
    func stream_stopReason為refusal_丟出拒答錯誤且不交出結束事件(
        stopDetails: String?,
        expectedDetail: String?
    ) async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(stopReason: "refusal", stopDetails: stopDetails),
            messageStop(),
        ])
        let expectedError = LKAIError.refused(detail: expectedDetail)

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events.isEmpty)
        #expect(outcome.error == expectedError)
    }

    // spectra-scenario: anthropic-provider / Map stop reasons
    // spectra-scenario: anthropic-provider / Map stop reasons / stop reasons
    /// 驗證不認得的 `stop_reason` 丟出無效回應錯誤，不交出結束事件，不把未知的原因當成正常完成
    ///
    /// - Parameter stopReason: `message_delta` 回報的 `stop_reason`；範例表是 `tool_use`，另加兩個不在對應表內的值
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test(
        .timeLimit(.minutes(1)),
        arguments: ["tool_use", "pause_turn", "future_reason"] as [String]
    )
    func stream_不認得的stopReason_丟出無效回應錯誤且不交出結束事件(stopReason: String) async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(stopReason: stopReason),
            messageStop(),
        ])

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events.isEmpty)
        #expect(isInvalidResponse(outcome.error))
    }

    /// 驗證串流有多個 `message_delta` 時，採用最後一個不是 null 的 `stop_reason`，後面的 null 不會蓋掉它
    @Test(.timeLimit(.minutes(1)))
    func stream_多個messageDelta_採用最後一個不是null的stopReason() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(stopReason: "max_tokens"),
            messageDelta(stopReason: "end_turn"),
            messageDelta(stopReason: nil),
            messageStop(),
        ])
        let expectedEvents = [finishedEvent(.completed)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Stream stops at the output token limit
    /// 驗證輸出達到上限時，先交出已產生的文字，再交出結束原因為輸出上限的結束事件
    @Test(.timeLimit(.minutes(1)))
    func stream_達到輸出上限_交出文字後以輸出上限結束() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Partial"),
            blockStop(),
            messageDelta(stopReason: "max_tokens"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Partial"),
            finishedEvent(.maxOutputTokens),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Stream stops when the context window is full
    /// 驗證塞滿 context window 時，先交出已產生的文字，再交出結束原因為 context window 滿了的結束事件
    @Test(.timeLimit(.minutes(1)))
    func stream_塞滿contextWindow_交出文字後以contextWindow滿了結束() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Partial"),
            blockStop(),
            messageDelta(stopReason: "model_context_window_exceeded"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Partial"),
            finishedEvent(.contextWindowExceeded),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Streaming call refused after partial text
    /// 驗證回答到一半被拒答時，先交出已產生的文字，再以拒答錯誤失敗，原因是類別 `cyber`，不交出結束事件
    @Test(.timeLimit(.minutes(1)))
    func stream_產生部分文字後拒答_交出文字後丟出拒答錯誤() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Sure"),
            blockStop(),
            messageDelta(
                stopReason: "refusal",
                stopDetails: #"{"type":"refusal","category":"cyber"}"#
            ),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Sure")]
        let expectedError = LKAIError.refused(detail: "cyber")

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == expectedError)
    }

    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events
    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events / cached prompt
    /// 驗證用量合併 `message_start` 與 `message_delta`：輸入含快取建立與讀取，輸出以後來回報的為準
    ///
    /// - Note: `message_start` 的輸入是 10、快取建立 5、快取讀取 20、輸出 1，`message_delta` 的輸出是 7
    @Test(.timeLimit(.minutes(1)))
    func stream_有快取的提示_用量的輸入加總快取且輸出取最後的值() async {
        // Given
        let client = makeClient(events: [
            messageStart(
                usage: #"{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":20,"output_tokens":1}"#
            ),
            messageDelta(stopReason: "end_turn", usage: #"{"output_tokens":7}"#),
            messageStop(),
        ])
        let expectedUsage = LKAIUsage(
            inputTokens: 35,
            outputTokens: 7,
            cachedInputTokens: 20,
            reasoningOutputTokens: nil
        )
        let expectedEvents = [finishedEvent(.completed, usage: expectedUsage)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events
    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events / thinking tokens
    /// 驗證 `output_tokens_details` 的思考 token 成為用量的推理輸出，沒有快取欄位時快取輸入為 nil
    ///
    /// - Note: `message_start` 的輸入是 12，`message_delta` 的輸出是 120、思考是 100
    @Test(.timeLimit(.minutes(1)))
    func stream_有思考token_用量帶推理輸出且沒有快取輸入() async {
        // Given
        let client = makeClient(events: [
            messageStart(usage: #"{"input_tokens":12}"#),
            messageDelta(
                stopReason: "end_turn",
                usage: #"{"output_tokens":120,"output_tokens_details":{"thinking_tokens":100}}"#
            ),
            messageStop(),
        ])
        let expectedUsage = LKAIUsage(
            inputTokens: 12,
            outputTokens: 120,
            cachedInputTokens: nil,
            reasoningOutputTokens: 100
        )
        let expectedEvents = [finishedEvent(.completed, usage: expectedUsage)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events
    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events / usage only in the delta event
    /// 驗證 `message_start` 沒有 `usage`、用量全在 `message_delta` 時，仍交出用量，null 的快取讀取視為沒有回報
    ///
    /// - Note: `message_delta` 的輸入是 12、`cache_read_input_tokens` 是 null、輸出是 30
    @Test(.timeLimit(.minutes(1)))
    func stream_用量只在messageDelta_仍交出用量且快取輸入為nil() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(
                stopReason: "end_turn",
                usage: #"{"input_tokens":12,"cache_read_input_tokens":null,"output_tokens":30}"#
            ),
            messageStop(),
        ])
        let expectedUsage = LKAIUsage(
            inputTokens: 12,
            outputTokens: 30,
            cachedInputTokens: nil,
            reasoningOutputTokens: nil
        )
        let expectedEvents = [finishedEvent(.completed, usage: expectedUsage)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events
    // spectra-scenario: anthropic-provider / Combine usage from the start and delta events / input tokens never reported
    /// 驗證從頭到尾都沒有回報輸入 token 時，結束事件不帶用量，不拿 0 或不完整的數字充數
    ///
    /// - Note: `message_start` 沒有 `usage`，`message_delta` 只回報輸出 5
    @Test(.timeLimit(.minutes(1)))
    func stream_從未回報輸入token_結束事件不帶用量() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            messageDelta(stopReason: "end_turn", usage: #"{"output_tokens":5}"#),
            messageStop(),
        ])
        let expectedEvents = [finishedEvent(.completed)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    /// 驗證 `message_delta` 的用量欄位是 null 時，保留 `message_start` 先前回報的值，只替換有新值的欄位
    ///
    /// - Note: `message_start` 的輸入是 10、輸出是 1，`message_delta` 的輸入是 null、輸出是 7
    @Test(.timeLimit(.minutes(1)))
    func stream_用量欄位為null_保留先前回報的值() async {
        // Given
        let client = makeClient(events: [
            messageStart(usage: #"{"input_tokens":10,"output_tokens":1}"#),
            messageDelta(
                stopReason: "end_turn",
                usage: #"{"input_tokens":null,"output_tokens":7}"#
            ),
            messageStop(),
        ])
        let expectedUsage = LKAIUsage(
            inputTokens: 10,
            outputTokens: 7,
            cachedInputTokens: nil,
            reasoningOutputTokens: nil
        )
        let expectedEvents = [finishedEvent(.completed, usage: expectedUsage)]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Provider reports no usage
    /// 驗證供應商完全沒有回報用量、正常結束時，結束原因是完成，而且結束事件不帶用量
    @Test(.timeLimit(.minutes(1)))
    func stream_供應商沒有回報用量_以完成結束且不帶用量() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Hi"),
            blockStop(),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hi"),
            finishedEvent(.completed),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Report the responding model of a stream
    // spectra-scenario: anthropic-provider / Report the responding model of a stream / stream without a fallback block
    /// 驗證串流沒有 `fallback` 區塊時，實際回應的模型取 `message_start` 的模型
    @Test(.timeLimit(.minutes(1)))
    func stream_沒有fallback區塊_實際回應的模型取messageStart的模型() async {
        // Given
        let client = makeClient(events: [
            messageStart(model: "claude-opus-5-5"),
            textBlockStart(),
            textDelta("Hi"),
            blockStop(),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hi"),
            finishedEvent(.completed, respondingModel: "claude-opus-5-5"),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: anthropic-provider / Report the responding model of a stream
    // spectra-scenario: anthropic-provider / Report the responding model of a stream / fallback in the middle of a stream
    /// 驗證串流途中切換到備援模型時，前後的文字都照常交出，`fallback` 區塊不產生事件，實際回應的模型是備援模型
    @Test(.timeLimit(.minutes(1)))
    func stream_串流途中切換備援_文字照常交出且回應模型為備援模型() async {
        // Given
        let client = makeClient(events: [
            messageStart(model: "claude-opus-5-5"),
            textBlockStart(),
            textDelta("Sure"),
            blockStop(),
            fallbackBlockStart(index: 1, from: "claude-opus-5-5", to: "claude-opus-4-8"),
            blockStop(index: 1),
            textBlockStart(index: 2),
            textDelta(", here", index: 2),
            blockStop(index: 2),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Sure"),
            .textDelta(", here"),
            finishedEvent(.completed, respondingModel: "claude-opus-4-8"),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    /// 驗證串流有多個 `fallback` 區塊時，實際回應的模型取最後一個區塊的 `to.model`
    @Test(.timeLimit(.minutes(1)))
    func stream_有多個fallback區塊_回應模型取最後一個區塊的to() async {
        // Given
        let client = makeClient(events: [
            messageStart(model: "claude-opus-5-5"),
            fallbackBlockStart(index: 0, from: "claude-opus-5-5", to: "claude-opus-4-8"),
            blockStop(index: 0),
            fallbackBlockStart(index: 1, from: "claude-opus-4-8", to: "claude-opus-4-7"),
            blockStop(index: 1),
            textBlockStart(index: 2),
            textDelta("Hi", index: 2),
            blockStop(index: 2),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [
            .textDelta("Hi"),
            finishedEvent(.completed, respondingModel: "claude-opus-4-7"),
        ]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Report the responding model
    /// 驗證供應商回報的模型是 `claude-opus-4-8` 時，串流的結束事件記錄這個模型
    @Test(.timeLimit(.minutes(1)))
    func stream_供應商回報模型claudeOpus48_結束事件記錄實際回應的模型() async {
        // Given
        let client = makeClient(events: [
            messageStart(model: "claude-opus-4-8"),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])
        let expectedEvents = [finishedEvent(.completed, respondingModel: "claude-opus-4-8")]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Report the responding model
    /// 驗證供應商回報的模型是 `claude-opus-4-8` 時，非串流的結果也記錄這個模型，並帶著串接好的文字
    @Test(.timeLimit(.minutes(1)))
    func invoke_供應商回報模型claudeOpus48_結果記錄實際回應的模型() async throws {
        // Given
        let client = makeClient(events: [
            messageStart(model: "claude-opus-4-8"),
            textBlockStart(),
            textDelta("Hi"),
            blockStop(),
            messageDelta(stopReason: "end_turn"),
            messageStop(),
        ])

        // When
        let response = try await client.invoke(validRequest)

        // Then
        #expect(response.text == "Hi")
        #expect(response.completion.respondingModel == "claude-opus-4-8")
    }

    // spectra-scenario: chat-client / Stream ends before a finish is reported
    /// 驗證串流沒有 `message_stop` 就結束時，已收到的文字照常交出，再以無效回應錯誤失敗，不交出結束事件
    ///
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test(.timeLimit(.minutes(1)))
    func stream_沒有messageStop就結束_交出文字後丟出無效回應錯誤() async {
        // Given
        let client = makeClient(events: [
            messageStart(),
            textBlockStart(),
            textDelta("Hel"),
        ])
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Hel")]

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(isInvalidResponse(outcome.error))
    }

    /// 驗證回應的內容是空的、沒有任何事件就結束時，以無效回應錯誤失敗，不交出任何事件
    @Test(.timeLimit(.minutes(1)))
    func stream_回應沒有任何事件_丟出無效回應錯誤() async {
        // Given
        let client = makeClient(events: [])

        // When
        let outcome = await collectOutcome(from: client)

        // Then
        #expect(outcome.events.isEmpty)
        #expect(isInvalidResponse(outcome.error))
    }
}

// MARK: - Nested Types

extension LKAnthropicClientStreamTests {

    /// SSE 的一個事件：事件名稱，以及 `data` 的 JSON 文字
    struct SSEEvent {

        /// `event:` 那一行的事件名稱
        let name: String

        /// `data:` 那一行的 JSON 文字
        let data: String
    }

    /// 迭代完一條串流後的結果：收到的全部事件，以及串流丟出的錯誤
    struct StreamOutcome {

        /// 依收到的順序排列的全部事件
        let events: [LKAIChatStreamEvent]

        /// 串流丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }
}

// MARK: - Private Method

private extension LKAnthropicClientStreamTests {

    /// 建立一個用固定 SSE 事件回應的 client：替身把事件逐行推送後結束
    ///
    /// - Parameter events: 依序送出的 SSE 事件
    /// - Returns: 呼叫時會得到這些事件的 client
    func makeClient(events: [SSEEvent]) -> LKAnthropicClient {
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: lines(of: events))
        mock.finish()
        return LKAnthropicClient(apiKey: "test-key", httpClient: mock)
    }

    /// 把 SSE 事件轉成逐行內容：每個事件是 `event:`、`data:` 與一個空行三行
    ///
    /// - Parameter events: 依序排列的 SSE 事件
    /// - Returns: 不含 CR 與 LF 的每一行
    func lines(of events: [SSEEvent]) -> [String] {
        events.flatMap { ["event: \($0.name)", "data: \($0.data)", ""] }
    }

    /// 建立 `message_start` 事件，內容是一則還沒有任何內容的助理訊息
    ///
    /// - Parameters:
    ///   - model: 訊息的模型識別碼
    ///   - usage: 訊息的 `usage` JSON；nil 表示不放這個鍵
    /// - Returns: `message_start` 事件
    func messageStart(model: String = "claude-opus-5-5", usage: String? = nil) -> SSEEvent {
        let usageField = optionalField("usage", usage)
        return SSEEvent(
            name: "message_start",
            data: #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"\#(model)","stop_reason":null,"stop_sequence":null\#(usageField)}}"#
        )
    }

    /// 組出 JSON 物件裡可有可無的欄位，前面帶逗號，接在其他欄位之後
    ///
    /// - Parameters:
    ///   - name: 欄位名稱
    ///   - json: 欄位值的 JSON；nil 表示不放這個欄位
    /// - Returns: `,"名稱":值`；沒有值時為空字串
    func optionalField(_ name: String, _ json: String?) -> String {
        guard let json else {
            return ""
        }
        return ",\"\(name)\":\(json)"
    }

    /// 建立開始一個文字區塊的 `content_block_start` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_start` 事件，區塊類型是 `text`
    func textBlockStart(index: Int = 0) -> SSEEvent {
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
    func textDelta(_ text: String, index: Int = 0) -> SSEEvent {
        SSEEvent(
            name: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"text_delta","text":"\#(text)"}}"#
        )
    }

    /// 建立結束一個區塊的 `content_block_stop` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_stop` 事件
    func blockStop(index: Int = 0) -> SSEEvent {
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
    func messageDelta(
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
    func messageStop() -> SSEEvent {
        SSEEvent(name: "message_stop", data: #"{"type":"message_stop"}"#)
    }

    /// 建立預期的結束事件，用來寫期望值；模型預設是 `message_start` 預設的模型
    ///
    /// - Parameters:
    ///   - finishReason: 預期的結束原因
    ///   - usage: 預期的用量；預設沒有
    ///   - respondingModel: 預期實際回應的模型
    /// - Returns: 帶著這些內容的結束事件
    func finishedEvent(
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

    /// 迭代 client 的串流到結束，收集事件並記下丟出的錯誤
    ///
    /// - Parameter client: 要呼叫的 client
    /// - Returns: 收到的全部事件，以及串流丟出的錯誤；正常結束時錯誤為 nil
    func collectOutcome(from client: LKAnthropicClient) async -> StreamOutcome {
        var events: [LKAIChatStreamEvent] = []
        var actualError: LKAIError?
        do {
            for try await event in client.stream(validRequest) {
                events.append(event)
            }
        } catch {
            actualError = error
        }
        return StreamOutcome(events: events, error: actualError)
    }

    /// 建立開始一個思考區塊的 `content_block_start` 事件
    ///
    /// - Parameter index: 區塊的序號
    /// - Returns: `content_block_start` 事件，區塊類型是 `thinking`
    func thinkingBlockStart(index: Int = 0) -> SSEEvent {
        SSEEvent(
            name: "content_block_start",
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"thinking","thinking":""}}"#
        )
    }

    /// 建立思考內容為空的 `content_block_delta` 事件
    ///
    /// - Parameter index: 所屬區塊的序號
    /// - Returns: `content_block_delta` 事件，增量類型是 `thinking_delta`
    func thinkingDelta(index: Int = 0) -> SSEEvent {
        SSEEvent(
            name: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"thinking_delta","thinking":""}}"#
        )
    }

    /// 建立 `ping` 事件，用來保持連線，不帶任何內容
    ///
    /// - Returns: `ping` 事件
    func ping() -> SSEEvent {
        SSEEvent(name: "ping", data: #"{"type": "ping"}"#)
    }

    /// 建立思考簽章的 `content_block_delta` 事件
    ///
    /// - Parameter index: 所屬區塊的序號
    /// - Returns: `content_block_delta` 事件，增量類型是 `signature_delta`
    func signatureDelta(index: Int = 0) -> SSEEvent {
        SSEEvent(
            name: "content_block_delta",
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"signature_delta","signature":"sig"}}"#
        )
    }

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

    /// 建立開始一個備援區塊的 `content_block_start` 事件，表示從原模型切換到備援模型
    ///
    /// - Parameters:
    ///   - index: 區塊的序號
    ///   - from: 切換前的模型識別碼
    ///   - to: 切換後的模型識別碼
    /// - Returns: `content_block_start` 事件，區塊類型是 `fallback`
    func fallbackBlockStart(index: Int, from: String, to: String) -> SSEEvent {
        SSEEvent(
            name: "content_block_start",
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"fallback","from":{"model":"\#(from)"},"to":{"model":"\#(to)"}}}"#
        )
    }
}
