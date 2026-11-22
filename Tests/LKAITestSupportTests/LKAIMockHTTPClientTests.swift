//
//  LKAIMockHTTPClientTests.swift
//  LKAITestSupportTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

/// `LKAIMockHTTPClient` 的單元測試，直接呼叫替身的 `fetch`，檢查哪些呼叫會記錄測試失敗
struct LKAIMockHTTPClientTests {

    /// 驗證替身在第二次 `fetch` 時記錄測試失敗，且第二次 `fetch` 丟出的錯誤不因此改變
    ///
    /// - Parameter setup: 替身的設定，推送了逐行內容或設定了 `failFetch`
    /// - Note: 第二次 `fetch` 的錯誤要在 body 內接住，否則 `withKnownIssue` 會把它當成已知問題
    /// - Note: `matching:` 只接受 `Issue.record` 記錄的問題（`.unconditional`），其他問題照常失敗
    @Test(.timeLimit(.minutes(1)), arguments: MockSetup.allCases)
    func fetch_第二次呼叫_記錄問題並保留原本的錯誤(setup: MockSetup) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        switch setup {
        case .lineContent:
            mock.yield("event: ping")
            mock.finish()

        case .failFetch:
            mock.failFetch(with: .transport(underlying: URLError(.notConnectedToInternet)))
        }
        let url = try #require(URL(string: "https://example.com/v1/messages"))
        let request = URLRequest(url: url)
        _ = try? await mock.fetch(request) // 失敗可忽略，因為 failFetch 的第一次 fetch 會丟錯
        var actualError: LKAIError?

        // When
        await withKnownIssue {
            do throws(LKAIError) {
                _ = try await mock.fetch(request)
            } catch {
                actualError = error
            }
        } matching: { issue in
            if case .unconditional = issue.kind {
                return true
            }
            return false
        }

        // Then
        #expect(mock.requests.count == 2)
        let error = try #require(actualError)
        switch setup {
        case .lineContent:
            let isInvalidResponse = if case .invalidResponse = error {
                true
            } else {
                false
            }
            #expect(isInvalidResponse)

        case .failFetch:
            let code: URLError.Code? = if case .transport(let underlying) = error {
                underlying.code
            } else {
                nil
            }
            #expect(code == .notConnectedToInternet)
        }
    }

    /// 驗證只呼叫一次 `fetch` 時替身不記錄問題，回應帶著建立替身時設定的狀態碼
    ///
    /// - Note: 替身如果記錄了問題，這個測試會因未預期的測試失敗而失敗，不需要另外斷言
    @Test(.timeLimit(.minutes(1)))
    func fetch_只呼叫一次_不記錄問題並回傳設定的狀態碼() async throws {
        // Given
        let mock = LKAIMockHTTPClient(statusCode: 503)
        mock.finish()
        let url = try #require(URL(string: "https://example.com/v1/messages"))
        let request = URLRequest(url: url)

        // When
        let response = try await mock.fetch(request)

        // Then
        #expect(response.statusCode == 503)
    }
}

// MARK: - Nested Types

extension LKAIMockHTTPClientTests {

    /// 替身的兩種設定，第二次 `fetch` 的測試以參數切換
    enum MockSetup: CaseIterable, Sendable {

        /// 推送一行逐行內容後結束；第一次 `fetch` 把來源交給回應，之後的 `fetch` 因來源已交出而無效
        case lineContent

        /// 設定了 `failFetch`，每次 `fetch` 都丟出底層代碼為 `notConnectedToInternet` 的連線錯誤
        case failFetch
    }
}
