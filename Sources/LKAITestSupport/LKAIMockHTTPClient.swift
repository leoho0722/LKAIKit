//
//  LKAIMockHTTPClient.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import Synchronization

/// 測試用的假 HTTP client：記錄收到的請求，回出預先設定的狀態碼與標頭，逐行內容由測試推送並決定何時結束
///
/// - Note: 只給本 package 的測試使用；`LKAITestSupport` 不屬於任何 product，不會進入函式庫的建置
/// - Note: 以 `Mutex` 保護可變狀態，不用樣板的 `@unchecked Sendable`：client 的背景 task 與測試會同時存取它
/// - Note: 一個替身只支援一次 `fetch` 的逐行內容，每個測試各自建立替身
package final class LKAIMockHTTPClient: Sendable {

    // MARK: - Properties

    /// `fetch` 回傳的狀態碼
    private let statusCode: Int

    /// `fetch` 回傳的標頭
    private let headers: [String: String]

    /// 逐行內容的來源，`fetch` 回傳的回應包的就是它
    private let stream: AsyncThrowingStream<String, any Error>

    /// 推送逐行內容的入口，測試透過它決定每一行與何時結束
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation

    /// 保護所有可變狀態的鎖，狀態在 `State` 內
    private let state = Mutex(State())

    // MARK: - Init

    /// 建立替身；逐行內容的來源在這裡就準備好，測試可以在 `fetch` 之前或之後推送
    ///
    /// - Parameters:
    ///   - statusCode: `fetch` 回傳的狀態碼
    ///   - headers: `fetch` 回傳的標頭
    /// - Note: 來源的 `onTermination` 只弱參照替身，避免替身與來源互相持有而無法釋放
    package init(
        statusCode: Int = 200,
        headers: [String: String] = ["content-type": "text/event-stream"]
    ) {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        self.statusCode = statusCode
        self.headers = headers
        self.stream = stream
        self.continuation = continuation
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

        /// 逐行內容的來源是否因迭代的 task 被取消或串流被釋放而終止
        var isCancelled = false
    }
}

// MARK: - Computed Properties

extension LKAIMockHTTPClient {

    /// 依序收到的請求
    package var requests: [URLRequest] {
        state.withLock {
            $0.requests
        }
    }

    /// 逐行內容的來源是否因迭代的 task 被取消或串流被釋放而終止；正常結束時為 `false`
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

    /// 記錄請求；設定了 `failFetch(with:)` 就丟出那個錯誤，否則回傳預先設定的狀態碼、標頭與逐行內容
    ///
    /// - Parameter request: 要送出的請求，會被記錄
    /// - Returns: 帶著預先設定的狀態碼與標頭，逐行內容是替身唯一的那一份來源
    /// - Throws: 設定了 `failFetch(with:)` 時丟出其中的錯誤
    package func fetch(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse {
        let failure = state.withLock {
            $0.requests.append(request)
            return $0.fetchError
        }
        if let failure {
            throw failure
        }
        return LKAIHTTPResponse(
            statusCode: statusCode,
            headers: headers,
            lines: LKAIHTTPLines(stream)
        )
    }
}
