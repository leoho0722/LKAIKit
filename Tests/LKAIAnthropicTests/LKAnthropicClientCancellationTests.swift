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
            await LKAIChatClientProtocolTestSupport.collectOutcome(
                from: client,
                request: LKAnthropicClientTestSupport.validRequest
            ) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        let outcome = await iterationTask.value
        try await LKAITestWaiting.waitUntil { mock.isCancelled }

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
        let firstEvent = try await LKAIChatClientProtocolTestSupport.receiveFirstEvent(
            of: client,
            request: LKAnthropicClientTestSupport.validRequest
        )
        try await LKAITestWaiting.waitUntil { mock.isCancelled }

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
            await LKAIChatClientProtocolTestSupport.callError(
                on: client,
                request: LKAnthropicClientTestSupport.validRequest,
                mode: .invoke
            )
        }

        // When
        try await LKAITestWaiting.waitUntil { mock.requests.count == 1 }
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
        let expectedFinishedEvent = LKAnthropicClientTestSupport.finishedEvent(.completed)
        let expectedEvents = [LKAIChatStreamEvent.textDelta("Hel"), expectedFinishedEvent]

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKAnthropicClientTestSupport.validRequest
        )
        try await LKAITestWaiting.waitUntil { mock.isCancelled }

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
        #expect(mock.isCancelled)
    }
}

// MARK: - Private Method

private extension LKAnthropicClientCancellationTests {

    /// 建立一個送出一段文字後不結束的替身：message_start、文字區塊開始與 "Hel" 的文字增量，之後不再有資料
    ///
    /// - Returns: 回應停在等待更多資料的替身
    func makePendingMock() -> LKAIMockHTTPClient {
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: LKAIServerSentEventTestSupport.lines(of: [
            .messageStart(),
            .textBlockStart(),
            .textDelta("Hel"),
        ]))
        return mock
    }

    /// 建立一個推送完整事件後不結束的替身：`makePendingMock()` 的內容之後，再送出結束原因與 `message_stop`
    ///
    /// - Returns: 已送出 `message_stop`，但連線還沒結束的替身
    func makeStoppedMock() -> LKAIMockHTTPClient {
        let mock = makePendingMock()
        mock.yield(lines: LKAIServerSentEventTestSupport.lines(of: [
            .messageDelta(stopReason: "end_turn"),
            .messageStop(),
        ]))
        return mock
    }
}
