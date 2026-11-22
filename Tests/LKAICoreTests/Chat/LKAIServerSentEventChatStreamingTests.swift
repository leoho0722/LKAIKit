//
//  LKAIServerSentEventChatStreamingTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import Synchronization
import Testing

@testable import LKAICore

/// `LKAIServerSentEventChatStreaming` 的單元測試，以假的 HTTP client、mapper 與供應商驗證共同流程
struct LKAIServerSentEventChatStreamingTests {

    /// 驗證交出 `.finished` 後不再處理後續事件與第二則 SSE 事件，串流正常結束
    ///
    /// - Note: mapper 每次都回傳 `[.textDelta("Hel"), .finished, .textDelta("lo")]`
    /// - Note: `.textDelta("lo")` 與第二則 SSE 事件都不應被處理
    @Test(.timeLimit(.minutes(1)))
    func makeStream_一則事件回傳文字結束與文字_交出到結束事件為止且不再讀取() async {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: nil
        )
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Hel"), .finished(completion)]
        let counter = CallCounter()
        let provider = FakeProvider(completion: completion, counter: counter)
        let request = LKAIChatRequest(
            model: "test-model",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 16
        )

        // When
        let outcome = await collectOutcome(of: provider.makeStream(for: request))

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
        #expect(counter.count == 1)
    }
}

// MARK: - Nested Types

extension LKAIServerSentEventChatStreamingTests {

    /// 迭代完一條串流後的結果：收到的全部事件，以及串流丟出的錯誤
    struct Outcome {

        /// 依收到的順序排列的全部事件
        let events: [LKAIChatStreamEvent]

        /// 串流丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }

    /// 記錄 mapper 被呼叫幾次；供應商必須是 `Sendable`，計數放在這裡，以 `Mutex` 保護
    final class CallCounter: Sendable {

        /// 以 `Mutex` 保護的計數值
        private let value = Mutex(0)

        /// mapper 目前被呼叫的次數
        var count: Int {
            value.withLock { $0 }
        }

        /// 把呼叫次數加一
        func increment() {
            value.withLock { $0 += 1 }
        }
    }

    /// 假的 HTTP client：不連網，固定回傳狀態碼 200 與兩則 SSE 事件的逐行內容
    struct FakeHTTPClient: LKAIHTTPClientProtocol {

        /// 送出請求，回傳帶著固定逐行內容的回應；請求的內容不檢查
        ///
        /// - Parameter request: 要送出的請求，不檢查內容
        /// - Returns: 狀態碼 200、沒有標頭，逐行內容是 `data: first`、空行、`data: second`、空行
        func fetch(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse {
            let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            continuation.yield("data: first")
            continuation.yield("")
            continuation.yield("data: second")
            continuation.yield("")
            continuation.finish()
            return LKAIHTTPResponse(
                statusCode: 200,
                headers: [:],
                lines: LKAIHTTPLines(stream)
            )
        }
    }

    /// 假的 mapper：每處理一則 SSE 事件計數加一，固定回傳一段文字、結束事件與另一段文字
    struct FakeMapper: LKAIServerSentEventMapping {

        /// 結束事件的內容
        let completion: LKAIChatCompletion

        /// 記錄呼叫次數的計數
        let counter: CallCounter

        /// 處理一則 SSE 事件，固定回傳一段文字、結束事件與另一段文字
        ///
        /// - Parameter event: 剛解析出的 SSE 事件，內容不檢查
        /// - Returns: `[.textDelta("Hel"), .finished(completion), .textDelta("lo")]`
        /// - Throws: 不會丟出
        func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
            counter.increment()
            return [.textDelta("Hel"), .finished(completion), .textDelta("lo")]
        }
    }

    /// 假的供應商：HTTP client 與 mapper 都是假的，網址與錯誤分類是固定的
    struct FakeProvider: LKAIServerSentEventChatStreaming {

        /// 送出請求的假 HTTP client
        let httpClient: any LKAIHTTPClientProtocol = FakeHTTPClient()

        /// 結束事件的內容
        let completion: LKAIChatCompletion

        /// 記錄 mapper 呼叫次數的計數
        let counter: CallCounter

        /// 以固定的網址組出請求，不依對話請求的內容改變網址
        ///
        /// - Parameter request: 要送出的對話請求，不影響網址
        /// - Returns: 指向假網址的請求
        /// - Throws: 網址無法建立時丟出 `invalidRequest`
        func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest {
            guard let url = URL(string: "https://example.com") else {
                throw .invalidRequest(message: "invalid test URL")
            }
            return URLRequest(url: url)
        }

        /// 假的供應商不分類錯誤回應，讓共同流程改用狀態碼的預設分類
        ///
        /// - Parameters:
        ///   - statusCode: 回應的 HTTP 狀態碼
        ///   - headers: 回應標頭
        ///   - body: 錯誤內容
        /// - Returns: 一律為 nil
        func httpError(
            statusCode: Int,
            headers: [String: String],
            body: String
        ) -> LKAIError? {
            nil
        }

        /// 建立一份新的假 mapper，計數共用同一個計數型別
        ///
        /// - Returns: 假的 mapper
        func makeEventMapper() -> any LKAIServerSentEventMapping {
            FakeMapper(completion: completion, counter: counter)
        }
    }
}

// MARK: - Private Method

private extension LKAIServerSentEventChatStreamingTests {

    /// 逐一收下串流交出的事件，並記下串流是正常結束還是丟出了錯誤
    ///
    /// - Parameter stream: 要迭代的串流
    /// - Returns: 收到的全部事件，以及串流丟出的錯誤；正常結束時錯誤為 nil
    func collectOutcome(of stream: LKAIChatStream) async -> Outcome {
        var events: [LKAIChatStreamEvent] = []
        var actualError: LKAIError?
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            actualError = error
        }
        return Outcome(events: events, error: actualError)
    }
}
