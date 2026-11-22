//
//  LKAIMockHTTPClient.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import Synchronization
import Testing

/// 測試用的假 HTTP client：記錄收到的請求，回出預先設定的狀態碼與標頭，逐行內容由測試推送並決定何時結束
///
/// - Note: 只給本 package 的測試使用；`LKAITestSupport` 不屬於任何 product，不會進入函式庫的建置
/// - Note: 以 `Mutex` 保護可變狀態，不用樣板的 `@unchecked Sendable`：client 的背景 task 與測試會同時存取它
/// - Note: 逐行內容的來源只在 `fetch` 時交出一次，之後替身不再持有；第二次 `fetch` 丟出 `invalidResponse`
/// - Note: 第二次以後的 `fetch` 另以 `Issue.record` 記錄測試失敗，設定了 `failFetch` 時也一樣
/// - Note: 迭代的 task 被取消，或交出的回應被釋放時，來源以 `.cancelled` 呼叫 `onTermination`，`isCancelled` 變成 `true`
package final class LKAIMockHTTPClient: Sendable {

    // MARK: - Properties

    /// `fetch` 回傳的狀態碼
    private let statusCode: Int

    /// `fetch` 回傳的標頭
    private let headers: [String: String]

    /// 推送逐行內容的入口，測試透過它決定每一行與何時結束
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation

    /// 保護所有可變狀態的鎖，狀態在 `State` 內
    private let state: Mutex<State>

    // MARK: - Init

    /// 建立替身；逐行內容的來源在這裡就準備好，`fetch` 之前推送的行留在緩衝區，`fetch` 之後照常交出
    ///
    /// - Parameters:
    ///   - statusCode: `fetch` 回傳的狀態碼
    ///   - headers: `fetch` 回傳的標頭
    /// - Note: 來源在 `fetch` 之前由替身持有，交出後由回應持有，所以釋放回應才會觸發 `onTermination`
    /// - Note: 來源的 `onTermination` 只弱參照替身，避免替身與來源互相持有而無法釋放
    package init(
        statusCode: Int = 200,
        headers: [String: String] = ["content-type": "text/event-stream"]
    ) {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        self.statusCode = statusCode
        self.headers = headers
        self.continuation = continuation
        self.state = Mutex(State(pendingStream: stream))
        continuation.onTermination = { [weak self] termination in
            guard let self else { return }
            if case .cancelled = termination {
                state.withLock {
                    $0.isCancelled = true
                }
            }
        }
    }
}

// MARK: - Nested Types

extension LKAIMockHTTPClient {

    /// 替身的可變狀態，全部由同一個 `Mutex` 保護
    private struct State {

        /// 依序收到的請求
        var requests: [URLRequest] = []

        /// 之後的 `fetch` 要直接丟出的錯誤；沒有設定時為 nil
        var fetchError: LKAIError?

        /// 逐行內容的來源是否因迭代的 task 被取消或回應被釋放而終止
        var isCancelled = false

        /// 還沒有交出的逐行內容的來源；`fetch` 時取出並設為 nil，交出後替身不再持有
        var pendingStream: AsyncThrowingStream<String, any Error>?
    }

    /// 一次 `fetch` 在鎖內決定的結果：這是第幾次 `fetch`，以及要交給回應的來源或要丟出的錯誤
    private typealias FetchOutcome = (
        Int,
        Result<AsyncThrowingStream<String, any Error>, LKAIError>
    )
}

// MARK: - Computed Properties

extension LKAIMockHTTPClient {

    /// 依序收到的請求
    package var requests: [URLRequest] {
        state.withLock {
            $0.requests
        }
    }

    /// 逐行內容的來源是否因迭代的 task 被取消，或交出的回應被釋放而被取消；正常結束時為 `false`
    package var isCancelled: Bool {
        state.withLock {
            $0.isCancelled
        }
    }
}

// MARK: - Internal Method

extension LKAIMockHTTPClient {

    /// 讓之後的 `fetch` 在回傳回應前直接丟出指定的錯誤，模擬連線失敗
    ///
    /// - Parameter error: `fetch` 要丟出的錯誤
    package func failFetch(with error: LKAIError) {
        state.withLock {
            $0.fetchError = error
        }
    }

    /// 推送一行逐行內容
    ///
    /// - Parameter line: 要推送的一行，不含 CR 與 LF
    package func yield(_ line: String) {
        continuation.yield(line)
    }

    /// 依序推送多行逐行內容
    ///
    /// - Parameter lines: 要推送的每一行，不含 CR 與 LF
    package func yield(lines: [String]) {
        for line in lines {
            continuation.yield(line)
        }
    }

    /// 正常結束逐行內容
    package func finish() {
        continuation.finish()
    }

    /// 以指定的錯誤結束逐行內容，模擬串流中途斷線等情況
    ///
    /// - Parameter error: 逐行內容途中要丟出的錯誤
    package func finish(throwing error: any Error) {
        continuation.finish(throwing: error)
    }
}

// MARK: - LKAIHTTPClientProtocol

extension LKAIMockHTTPClient: LKAIHTTPClientProtocol {

    /// 記錄請求；設定了 `failFetch(with:)` 就丟出那個錯誤，否則把還沒有交出的逐行內容連同狀態碼與標頭交給回應
    ///
    /// - Parameter request: 要送出的請求，會被記錄
    /// - Returns: 帶著預先設定的狀態碼與標頭，逐行內容的來源交給回應，之後替身不再持有
    /// - Throws: 設定了 `failFetch(with:)` 時丟出其中的錯誤；來源已經交出過（第二次 `fetch`）時丟出 `invalidResponse`
    /// - Note: 第二次 `fetch` 丟錯而不是回傳空的逐行內容，讓誤用的測試立刻失敗
    /// - Note: 第二次以後的 `fetch` 另以 `Issue.record` 記錄測試失敗，不論是否設定了 `failFetch`
    /// - Note: 記錄放在鎖外，因為 `Issue.record` 會同步執行 `withKnownIssue` 的 `matching:`，
    ///   若判斷式讀取 `requests`，會在鎖內再次取得同一把不可重入的 `Mutex` 而死結
    package func fetch(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse {
        let (fetchCount, outcome) = state.withLock { mockState -> FetchOutcome in
            mockState.requests.append(request)
            let count = mockState.requests.count
            if let fetchError = mockState.fetchError {
                return (count, .failure(fetchError))
            }
            guard let pendingStream = mockState.pendingStream else {
                let reason = "The mock supports only one fetch with line content"
                return (count, .failure(.invalidResponse(reason: reason)))
            }
            mockState.pendingStream = nil
            return (count, .success(pendingStream))
        }
        if fetchCount > 1 {
            Issue.record(
                "LKAIMockHTTPClient fetch #\(fetchCount): each mock supports only one fetch"
            )
        }
        let source = try outcome.get()
        return LKAIHTTPResponse(
            statusCode: statusCode,
            headers: headers,
            lines: LKAIHTTPLines(source)
        )
    }
}
