//
//  LKAIChatStreamTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Synchronization
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

    /// 驗證生產端依序交出文字與完成事件後正常返回，串流照同樣的順序交出兩個事件，然後正常結束
    @Test
    func initProducing_生產端交出事件後正常返回_依序交出事件後正常結束() async {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: nil
        )
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Hel"), .finished(completion)]
        let stream = LKAIChatStream { yield in
            yield(.textDelta("Hel"))
            yield(.finished(completion))
        }

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        #expect(outcome.events == expectedEvents)
        #expect(outcome.error == nil)
    }

    /// 驗證生產端交出一段文字後丟出對話錯誤，串流先交出那段文字，再以同一個錯誤結束
    @Test
    func initProducing_生產端交出事件後丟出錯誤_先交出事件再以該錯誤結束() async throws {
        // Given
        let sourceError = LKAIError.serviceUnavailable(statusCode: 503)
        let expectedEvents: [LKAIChatStreamEvent] = [.textDelta("Hel")]
        let stream = LKAIChatStream { yield throws(LKAIError) in
            yield(.textDelta("Hel"))
            throw sourceError
        }

        // When
        let outcome = await collectOutcome(of: stream)

        // Then
        let error = try #require(outcome.error)
        #expect(outcome.events == expectedEvents)
        #expect(error == sourceError)
    }

    /// 驗證收到第一個事件後釋放串流，生產端的 task 被取消，並在兩秒內記錄到取消
    ///
    /// - Note: 生產端交出第一個事件後等 60 秒
    /// - Note: 取消時 `Task.sleep` 丟出 `CancellationError`，探測型別因此被標記
    @Test(.timeLimit(.minutes(1)))
    func initProducing_收到第一個事件後釋放串流_生產端的task被取消() async throws {
        // Given
        let probe = CancellationProbe()
        let expectedEvent = LKAIChatStreamEvent.textDelta("Hel")

        // When
        let firstEvent = try await receiveFirstEvent(of: makeWaitingStream(probe: probe))
        let wasCancelled = try await waitUntilCancelled(of: probe)

        // Then
        #expect(firstEvent == expectedEvent)
        #expect(wasCancelled)
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

    /// 記錄生產端的 task 是否已被取消；生產端與測試跨 task 存取，所以以 `Mutex` 保護
    final class CancellationProbe: Sendable {

        /// 以 `Mutex` 保護的取消旗標
        private let cancelled = Mutex(false)

        /// 目前是否已記錄到生產端被取消
        var isCancelled: Bool {
            cancelled.withLock { $0 }
        }

        /// 記錄生產端的 task 已被取消
        func markCancelled() {
            cancelled.withLock { $0 = true }
        }
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

    /// 取得串流的第一個事件就離開迴圈，函式返回時串流跟著釋放
    ///
    /// - Parameter stream: 要迭代的串流；只在這個函式內持有，返回後由呼叫端的暫時值釋放
    /// - Returns: 串流的第一個事件；串流沒有任何事件就結束時為 nil
    /// - Throws: 串流在第一個事件之前失敗時丟出
    func receiveFirstEvent(
        of stream: LKAIChatStream
    ) async throws(LKAIError) -> LKAIChatStreamEvent? {
        for try await event in stream {
            return event
        }
        return nil
    }

    /// 建立一條生產端會卡住的串流：先交出一段文字，之後等 60 秒，被取消時把探測型別標記為已取消
    ///
    /// - Parameter probe: 記錄生產端是否被取消的探測型別
    /// - Returns: 交出一段文字後就卡住的串流
    func makeWaitingStream(probe: CancellationProbe) -> LKAIChatStream {
        LKAIChatStream { yield in
            yield(.textDelta("Hel"))
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                probe.markCancelled()
            }
        }
    }

    /// 最多等 2 秒，每 10 毫秒查一次探測型別，等生產端的 task 被取消；取消是非同步的，所以要等
    ///
    /// - Parameter probe: 要查的探測型別
    /// - Returns: 等待結束時生產端是否已被取消；等滿仍沒有取消時為 false
    /// - Throws: 測試的 task 在等待中被取消時丟出
    func waitUntilCancelled(of probe: CancellationProbe) async throws -> Bool {
        for _ in 0..<200 {
            if probe.isCancelled {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return probe.isCancelled
    }
}
