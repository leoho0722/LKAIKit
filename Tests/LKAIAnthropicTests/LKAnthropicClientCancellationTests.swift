//
//  LKAnthropicClientCancellationTests.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIAnthropic

/// `LKAnthropicClient` 取消行為的單元測試：取消迭代的 task、釋放串流、取消等待中的非串流呼叫
///
/// - Note: 替身送出一段文字後不結束，讓串流停在等待更多資料；取消是非同步的，要等替身偵測到才檢查
struct LKAnthropicClientCancellationTests {

    // MARK: - Properties

    /// 多個測試共用的合法請求，內容與取消行為無關
    private let validRequest = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )

    // spectra-scenario: chat-client / Cancel a streaming call
    /// 驗證串流送出一段文字後取消迭代的 task，迭代沒有錯誤就結束，而且底層請求被取消
    @Test(.timeLimit(.minutes(1)))
    func stream_送出一段文字後取消迭代的task_迭代正常結束且底層請求被取消() async throws {
        // Given
        let mock = makePendingMock()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Hel")]
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            await collectOutcome(from: client) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        let outcome = await iterationTask.value
        try await waitUntil { mock.isCancelled }

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
        #expect(mock.isCancelled)
    }

    // spectra-scenario: chat-client / Release a stream after leaving the loop
    /// 驗證迭代到第一段文字就離開迴圈、並釋放串流後，底層請求被取消，過程中沒有取消任何 task
    @Test(.timeLimit(.minutes(1)))
    func stream_離開迴圈並釋放串流_底層請求被取消() async throws {
        // Given
        let mock = makePendingMock()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedEvent = LKAIChatStreamEvent.textDelta("Hel")

        // When
        let firstEvent = try await receiveFirstEvent(of: client)
        try await waitUntil { mock.isCancelled }

        // Then
        #expect(firstEvent == expectedEvent)
        #expect(mock.isCancelled)
    }

    // spectra-scenario: chat-client / Cancel a non-streaming call
    /// 驗證等待中的非串流呼叫被取消時，丟出 `cancelled`，不回傳已收到的部分文字
    ///
    /// - Note: 等替身收到請求後才取消，確保取消發生在請求送出之後
    @Test(.timeLimit(.minutes(1)))
    func invoke_等待中取消task_丟出cancelled錯誤() async throws {
        // Given
        let mock = makePendingMock()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedError = LKAIError.cancelled
        let invokeTask = Task {
            await invokeError(on: client)
        }

        // When
        try await waitUntil { mock.requests.count == 1 }
        invokeTask.cancel()
        let actualError = await invokeTask.value

        // Then
        #expect(actualError == expectedError)
    }

    /// 驗證收到 `message_stop` 並交出結束事件後，串流正常結束，client 放開回應，底層請求被取消
    ///
    /// - Note: 替身推送完整的事件後不結束；少了「結束事件之後放開回應」的行為，替身一直等不到取消
    @Test(.timeLimit(.minutes(1)))
    func stream_收到messageStop並交出結束事件_放開回應且底層請求被取消() async throws {
        // Given
        let mock = makeStoppedMock()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedFinishedEvent = LKAIChatStreamEvent.finished(
            LKAIChatCompletion(
                finishReason: .completed,
                usage: nil,
                respondingModel: "claude-opus-5-5"
            )
        )
        let expectedEvents = [LKAIChatStreamEvent.textDelta("Hel"), expectedFinishedEvent]

        // When
        let outcome = await collectOutcome(from: client)
        try await waitUntil { mock.isCancelled }

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
        #expect(mock.isCancelled)
    }
}

// MARK: - Nested Types

extension LKAnthropicClientCancellationTests {

    /// 迭代完一條串流後的結果：收到的全部事件，以及串流丟出的錯誤
    struct StreamOutcome {

        /// 依收到的順序排列的全部事件
        let events: [LKAIChatStreamEvent]

        /// 串流丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }
}

// MARK: - Private Method

private extension LKAnthropicClientCancellationTests {

    /// 建立一個送出一段文字後不結束的替身：message_start、文字區塊開始與 "Hel" 的文字增量，之後不再有資料
    ///
    /// - Returns: 回應停在等待更多資料的替身
    func makePendingMock() -> LKAIMockHTTPClient {
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-5-5","stop_reason":null,"stop_sequence":null}}"#,
            "",
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#,
            "",
        ])
        return mock
    }

    /// 迭代 client 的串流到結束，收集事件並記下丟出的錯誤
    ///
    /// - Parameters:
    ///   - client: 要呼叫的 client
    ///   - onEvent: 每收到一個事件就呼叫一次；不需要時省略
    /// - Returns: 收到的全部事件，以及串流丟出的錯誤；正常結束時錯誤為 nil
    func collectOutcome(
        from client: LKAnthropicClient,
        onEvent: (LKAIChatStreamEvent) -> Void = { _ in }
    ) async -> StreamOutcome {
        var events: [LKAIChatStreamEvent] = []
        var actualError: LKAIError?
        do {
            for try await event in client.stream(validRequest) {
                events.append(event)
                onEvent(event)
            }
        } catch {
            actualError = error
        }
        return StreamOutcome(events: events, error: actualError)
    }

    /// 最多等 2 秒，每 10 毫秒檢查一次條件，條件成立就立刻返回；取消是非同步的，所以要等替身偵測到
    ///
    /// - Parameter condition: 要等它成立的條件
    /// - Throws: 測試的 task 在等待中被取消時丟出
    /// - Note: 條件一直沒有成立時，等滿就返回，由呼叫端接著的斷言失敗
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 取得串流的第一個事件就離開迴圈，函式返回時串流跟著釋放
    ///
    /// - Parameter client: 要呼叫的 client
    /// - Returns: 串流的第一個事件；串流沒有任何事件就結束時為 nil
    /// - Throws: 串流在第一個事件之前失敗時丟出
    func receiveFirstEvent(
        of client: LKAnthropicClient
    ) async throws(LKAIError) -> LKAIChatStreamEvent? {
        let stream = client.stream(validRequest)
        for try await event in stream {
            return event
        }
        return nil
    }

    /// 以非串流呼叫 client 並記下丟出的錯誤
    ///
    /// - Parameter client: 要呼叫的 client
    /// - Returns: 呼叫丟出的錯誤；順利得到結果時為 nil
    func invokeError(on client: LKAnthropicClient) async -> LKAIError? {
        var actualError: LKAIError?
        do {
            _ = try await client.invoke(validRequest)
        } catch {
            actualError = error
        }
        return actualError
    }

    /// 建立一個推送完整事件後不結束的替身：`makePendingMock()` 的內容之後，再送出結束原因與 `message_stop`
    ///
    /// - Returns: 已送出 `message_stop`，但連線還沒結束的替身
    func makeStoppedMock() -> LKAIMockHTTPClient {
        let mock = makePendingMock()
        mock.yield(lines: [
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}"#,
            "",
            "event: message_stop",
            #"data: {"type":"message_stop"}"#,
            "",
        ])
        return mock
    }
}
