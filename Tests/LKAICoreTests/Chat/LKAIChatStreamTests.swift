//
//  LKAIChatStreamTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIChatStream` 的單元測試，以自己寫的來源序列驗證串流如何交出事件與錯誤
struct LKAIChatStreamTests {

    // spectra-scenario: chat-client / Build a stream from scripted events
    // spectra-scenario: chat-client / Build a stream from scripted events / source behaviors
    /// 驗證來源依序送出文字增量與完成事件後結束，串流照同樣的順序交出兩個事件，然後正常結束
    @Test
    func init_來源送出文字與完成事件後結束_依序交出兩個事件後正常結束() async {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: nil
        )
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("A"), .finished(completion)]
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("A"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let stream = LKAIChatStream(source)

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Build a stream from scripted events
    // spectra-scenario: chat-client / Build a stream from scripted events / source behaviors
    /// 驗證來源送出一段文字後丟出對話錯誤，串流先交出那段文字，再丟出同一個錯誤，不改寫也不吞掉
    ///
    /// - Parameter sourceError: 來源丟出的對話錯誤；範例表是限流，其餘確認各種對話錯誤都原樣交出
    @Test(arguments: [
        .invalidAPIKey,
        .rateLimited(retryAfter: .seconds(30)),
        .serviceUnavailable(statusCode: 529),
        .invalidResponse(reason: "bad data"),
    ] as [LKAIError])
    func init_來源送出文字後丟出對話錯誤_先交出文字再丟出同一個錯誤(sourceError: LKAIError) async throws {
        // Given
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("A")]
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("A"))
        sourceContinuation.finish(throwing: sourceError)
        let stream = LKAIChatStream(source)

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        let error = try #require(outcome.error)
        #expect(outcome.events == expectedEvents)
        #expect(error == sourceError)
    }

    // spectra-scenario: chat-client / Build a stream from scripted events
    // spectra-scenario: chat-client / Build a stream from scripted events / source behaviors
    /// 驗證來源丟出不是對話錯誤的錯誤時，串流降級成無效回應錯誤，不讓未知的錯誤直接漏給 App
    ///
    /// - Note: 只比對是不是無效回應，不比對原因文字，spec 沒有規定它
    @Test
    func init_來源丟出不是對話錯誤的錯誤_降級為無效回應錯誤() async throws {
        // Given
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.finish(throwing: UnrelatedError())
        let stream = LKAIChatStream(source)

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        let error = try #require(outcome.error)
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(isInvalidResponse)
        #expect(outcome.events.isEmpty)
    }

    // spectra-scenario: chat-client / Build a stream from scripted events
    // spectra-scenario: chat-client / Build a stream from scripted events / source behaviors
    /// 驗證來源丟出 `CancellationError` 或對話錯誤的 `cancelled` 時，串流視為被取消而不是失敗，正常結束
    ///
    /// - Parameter thrownError: 來源丟出的取消類錯誤
    @Test(arguments: [
        CancellationError(),
        LKAIError.cancelled,
    ] as [any Error & Sendable])
    func init_來源丟出取消類的錯誤_正常結束且沒有錯誤(thrownError: any Error & Sendable) async {
        // Given
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.finish(throwing: thrownError)
        let stream = LKAIChatStream(source)

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        #expect(outcome.events.isEmpty)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Build a stream from scripted events
    // spectra-scenario: chat-client / Build a stream from scripted events / source behaviors
    /// 驗證迭代的 task 被取消之後來源才丟出錯誤，串流仍正常結束，取消後不論錯誤是什麼都不當成失敗
    ///
    /// - Parameter thrownError: 取消後來源丟出的錯誤；範例表是限流，另加一個不是對話錯誤的錯誤
    /// - Note: 來源在 `onTermination` 裡才結束，重現「取消的空檔中來源丟出錯誤」；少了取消規則，錯誤會漏到消費端
    @Test(arguments: [
        LKAIError.rateLimited(retryAfter: .seconds(30)),
        UnrelatedError(),
    ] as [any Error & Sendable])
    func init_先取消迭代的task再由來源丟出錯誤_正常結束且沒有錯誤(thrownError: any Error & Sendable) async {
        // Given
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("A")]
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.onTermination = { termination in
            if case .cancelled = termination {
                sourceContinuation.finish(throwing: thrownError)
            }
        }
        sourceContinuation.yield(.textDelta("A"))
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let stream = LKAIChatStream(source)
        let iterationTask = Task {
            await collectOutcome(of: stream) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        let outcome = await iterationTask.value

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }
}

// MARK: - Nested Types

extension LKAIChatStreamTests {

    /// 建構 `LKAIChatStream` 時接收的來源序列型別，寫短一點方便閱讀
    typealias Source = AsyncThrowingStream<LKAIChatStreamEvent, any Error>

    /// 迭代完一條串流後的結果：收到的全部事件，以及串流丟出的錯誤
    struct Outcome {

        /// 依收到的順序排列的全部事件
        let events: [LKAIChatStreamEvent]

        /// 串流丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }

    /// 不是對話錯誤的錯誤，用來確認串流會把未知的錯誤降級成無效回應
    struct UnrelatedError: Error {

    }
}

// MARK: - Private Method

private extension LKAIChatStreamTests {

    /// 逐一收下串流交出的事件，並記下串流是正常結束還是丟出了錯誤
    ///
    /// - Parameters:
    ///   - stream: 要迭代的串流
    ///   - onEvent: 每收到一個事件就呼叫一次；不需要時省略
    /// - Returns: 收到的全部事件，以及串流丟出的錯誤；正常結束時錯誤為 nil
    func collectOutcome(
        of stream: LKAIChatStream,
        onEvent: (LKAIChatStreamEvent) -> Void = { _ in }
    ) async -> Outcome {
        var events: [LKAIChatStreamEvent] = []
        var actualError: LKAIError?
        do {
            for try await event in stream {
                events.append(event)
                onEvent(event)
            }
        } catch {
            actualError = error
        }
        return Outcome(events: events, error: actualError)
    }
}
