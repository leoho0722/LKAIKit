//
//  LKAIHTTPLinesTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Testing

@testable import LKAICore

/// `LKAIHTTPLines` 的單元測試，直接以 `AsyncThrowingStream` 建立來源，驗證錯誤轉換與取消規則
struct LKAIHTTPLinesTests {

    /// 驗證來源丟出 `CancellationError` 或 `cancelled` 時，已送出的行照常交出，`lines` 再正常結束
    ///
    /// - Parameter thrownError: 來源丟出的取消類錯誤
    @Test(arguments: [
        CancellationError(),
        LKAIError.cancelled,
    ] as [any Error & Sendable])
    func init_來源丟出取消類的錯誤_已送出的行照常交出後正常結束(thrownError: any Error & Sendable) async {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: thrownError)
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await LKAIHTTPLinesTestSupport.collectLines(from: lines)

        // Then
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }

    /// 驗證來源丟出不是 `LKAIError` 的錯誤時，`lines` 先交出已送出的行，再降級成無效回應錯誤
    ///
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test
    func init_來源丟出不是對話錯誤的錯誤_降級為無效回應錯誤() async throws {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: UnrelatedError())
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await LKAIHTTPLinesTestSupport.collectLines(from: lines)

        // Then
        let error = try #require(outcome.error)
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(outcome.lines == expectedLines)
        #expect(isInvalidResponse)
    }

    /// 驗證來源丟出 `LKAIError`（`cancelled` 除外）時，`lines` 先交出已送出的行，再原樣丟出同一個錯誤
    @Test
    func init_來源丟出對話錯誤_原樣丟出() async throws {
        // Given
        let expectedLines = ["a"]
        let expectedError = LKAIError.rateLimited(retryAfter: nil)
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: expectedError)
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await LKAIHTTPLinesTestSupport.collectLines(from: lines)

        // Then
        let error = try #require(outcome.error)
        #expect(outcome.lines == expectedLines)
        #expect(error == expectedError)
    }

    /// 驗證迭代的 task 被取消之後來源才丟出錯誤，`lines` 仍正常結束，取消後不論錯誤是什麼都不當成失敗
    ///
    /// - Parameter thrownError: 取消後來源丟出的錯誤，包含對話錯誤與不是對話錯誤的錯誤
    /// - Note: 來源在 `onTermination` 裡才結束，重現「取消的空檔中來源丟出錯誤」；少了取消規則，錯誤會漏到消費端
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            LKAIError.rateLimited(retryAfter: nil),
            UnrelatedError(),
        ] as [any Error & Sendable]
    )
    func init_先取消迭代的task再由來源丟出錯誤_正常結束且沒有錯誤(thrownError: any Error & Sendable) async {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
        sourceContinuation.onTermination = { termination in
            if case .cancelled = termination {
                sourceContinuation.finish(throwing: thrownError)
            }
        }
        sourceContinuation.yield("a")
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let lines = LKAIHTTPLines(source)
        let iterationTask = Task {
            await LKAIHTTPLinesTestSupport.collectLines(from: lines) { _ in
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
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }
}

// MARK: - Nested Types

extension LKAIHTTPLinesTests {

    /// 不是對話錯誤的錯誤，用來確認未知的錯誤會降級成無效回應
    struct UnrelatedError: Error {

    }
}
