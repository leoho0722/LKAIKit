//
//  LKAnthropicClientErrorTests.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIAnthropic

/// `LKAnthropicClient` 的錯誤對應測試，以 `LKAIMockHTTPClient` 回出各種錯誤回應與錯誤事件，不連網
struct LKAnthropicClientErrorTests {

    // MARK: - Properties

    /// HTTP 錯誤回應的範例表，每一列是一種錯誤回應與它預期的錯誤
    private static let errorResponseCases = [
        ErrorResponseCase(
            statusCode: 401,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
            expectedError: .invalidAPIKey
        ),
        ErrorResponseCase(
            statusCode: 403,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"permission_error","message":"Forbidden"}}"#,
            expectedError: .permissionDenied
        ),
        ErrorResponseCase(
            statusCode: 402,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"billing_error","message":"Billing problem"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: ["retry-after": "20"],
            body: #"{"type":"error","error":{"type":"rate_limit_error","message":"Too many requests"}}"#,
            expectedError: .rateLimited(retryAfter: .seconds(20))
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"rate_limit_error","message":"You have reached your API usage limits.","details":{"error_code":"enforced_spend_limit_reached"}},"request_id":"req_1"}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: too large"}}"#,
            expectedError: .invalidRequest(message: "max_tokens: too large")
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"invalid_request_error","message":"You have reached your specified API usage limits. You will regain access on 2026-12-01 at 00:00 UTC."}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"invalid_request_error","message":"You have reached your specified workspace API usage limits. You will regain access on 2026-12-01 at 00:00 UTC."}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 529,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            expectedError: .serviceUnavailable(statusCode: 529)
        ),
        ErrorResponseCase(
            statusCode: 500,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"api_error","message":"Internal server error"}}"#,
            expectedError: .serviceUnavailable(statusCode: 500)
        ),
        ErrorResponseCase(
            statusCode: 504,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#,
            expectedError: .serviceUnavailable(statusCode: 504)
        ),
        ErrorResponseCase(
            statusCode: 409,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"conflict_error","message":"Conflict"}}"#,
            expectedError: .invalidRequest(message: nil)
        ),
        ErrorResponseCase(
            statusCode: 502,
            extraHeaders: [:],
            body: "<html>Bad Gateway</html>",
            expectedError: .serviceUnavailable(statusCode: 502)
        ),
    ] as [ErrorResponseCase]

    /// 串流中途 `error` 事件的範例表，每一列是 `error` 事件的 data 與它預期的結果
    private static let errorEventCases = [
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 529))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"api_error","message":"Internal server error"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 504))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"new_unknown_error","message":"Something new"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
        ErrorEventCase(data: "not json", expectation: .invalidResponse),
    ] as [ErrorEventCase]

    // spectra-scenario: anthropic-provider / Classify HTTP error responses
    // spectra-scenario: anthropic-provider / Classify HTTP error responses / error responses
    /// 驗證非 2xx 的 Messages API 回應依 `error.type` 與標頭分類，結果與範例表預期的錯誤一致
    ///
    /// - Parameter testCase: 一列範例：狀態碼、額外的標頭、回應內容與預期的錯誤
    /// - Note: 409 `conflict_error` 不在分類規則列出的 `error.type` 裡，依預設分類為沒有訊息的無效請求
    @Test(.timeLimit(.minutes(1)), arguments: LKAnthropicClientErrorTests.errorResponseCases)
    func invoke_HTTP錯誤回應_依error類型分類為範例表的錯誤(testCase: ErrorResponseCase) async throws {
        // Given
        let headers = ["content-type": "application/json"]
            .merging(testCase.extraHeaders) { _, new in new }
        let mock = LKAIMockHTTPClient(statusCode: testCase.statusCode, headers: headers)
        mock.yield(testCase.body)
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        var actualError: LKAIError?

        // When
        do {
            _ = try await client.invoke(LKAnthropicClientTestSupport.validRequest)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == testCase.expectedError)
    }

    // spectra-scenario: anthropic-provider / Error event in the middle of a stream
    // spectra-scenario: anthropic-provider / Error event in the middle of a stream / error events
    /// 驗證串流中途的 `error` 事件依 `error.type` 分類：先交出已收到的文字，再以範例表預期的結果結束
    ///
    /// - Parameter testCase: 一列範例：`error` 事件的 data，以及預期的結果
    /// - Note: 只有 data 不是 JSON 那一列只比對是無效回應，原因文字不比對
    @Test(.timeLimit(.minutes(1)), arguments: LKAnthropicClientErrorTests.errorEventCases)
    func stream_串流中途的error事件_先交出文字再以範例表的錯誤結束(testCase: ErrorEventCase) async throws {
        // Given
        let client = LKAnthropicClientTestSupport.makeClient(events: [
            .messageStart(),
            .textBlockStart(),
            .textDelta("Hel"),
            .init(name: "error", data: testCase.data),
        ])

        // When
        let outcome = await LKAnthropicClientTestSupport.collectOutcome(from: client)

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        switch testCase.expectation {
        case .error(let expectedError):
            #expect(error == expectedError)

        case .invalidResponse:
            let isInvalidResponse = if case .invalidResponse = error {
                true
            } else {
                false
            }
            #expect(isInvalidResponse)
        }
    }

    /// 驗證連線失敗時，串流與非串流呼叫都丟出 `transport`，並保留底層 `URLError` 的代碼
    ///
    /// - Parameter mode: 呼叫方式，串流或非串流
    @Test(.timeLimit(.minutes(1)), arguments: LKAnthropicClientTestSupport.CallMode.allCases)
    func stream與invoke_連線失敗_丟出transport且保留底層錯誤代碼(
        mode: LKAnthropicClientTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.failFetch(with: .transport(underlying: URLError(.notConnectedToInternet)))
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAnthropicClientTestSupport.callError(on: client, mode: mode)

        // Then
        let error = try #require(actualError)
        let code: URLError.Code? = if case .transport(let underlying) = error {
            underlying.code
        } else {
            nil
        }
        #expect(code == .notConnectedToInternet)
    }
}

// MARK: - Nested Types

extension LKAnthropicClientErrorTests {

    /// HTTP 錯誤回應範例表的一列：狀態碼、額外的標頭、回應內容，以及預期的錯誤
    struct ErrorResponseCase: Sendable {

        /// HTTP 狀態碼
        let statusCode: Int

        /// 除了 `content-type`（一律為 application/json）以外的標頭，例如 `retry-after`
        let extraHeaders: [String: String]

        /// 回應內容，推送成一行
        let body: String

        /// 預期丟出的錯誤
        let expectedError: LKAIError
    }

    /// 串流中途 `error` 事件範例表的一列：事件的 data，以及預期的結果
    struct ErrorEventCase: Sendable {

        /// `error` 事件的 data，一段 JSON 文字
        let data: String

        /// 預期的結果
        let expectation: Expectation
    }

    /// `error` 事件的預期結果：指定的錯誤，或只要求是無效回應
    enum Expectation: Sendable {

        /// 丟出的錯誤必須等於指定的錯誤
        case error(LKAIError)

        /// 丟出的錯誤必須是無效回應，原因文字不比對
        case invalidResponse
    }
}
