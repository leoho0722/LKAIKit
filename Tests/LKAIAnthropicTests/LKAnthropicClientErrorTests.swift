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
            expectedError: .serviceUnavailable(statusCode: 529, retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 500,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"api_error","message":"Internal server error"}}"#,
            expectedError: .serviceUnavailable(statusCode: 500, retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 504,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#,
            expectedError: .serviceUnavailable(statusCode: 504, retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 529,
            extraHeaders: ["retry-after": "10"],
            body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            expectedError: .serviceUnavailable(statusCode: 529, retryAfter: .seconds(10))
        ),
        ErrorResponseCase(
            statusCode: 500,
            extraHeaders: ["retry-after": "3"],
            body: #"{"type":"error","error":{"type":"api_error","message":"Internal server error"}}"#,
            expectedError: .serviceUnavailable(statusCode: 500, retryAfter: .seconds(3))
        ),
        ErrorResponseCase(
            statusCode: 504,
            extraHeaders: ["retry-after": "7"],
            body: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#,
            expectedError: .serviceUnavailable(statusCode: 504, retryAfter: .seconds(7))
        ),
        ErrorResponseCase(
            statusCode: 409,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"type":"conflict_error","message":"Conflict"}}"#,
            expectedError: .invalidRequest(message: nil)
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"type":"error","error":{"message":"Bad request"}}"#,
            expectedError: .invalidRequest(message: nil)
        ),
        ErrorResponseCase(
            statusCode: 502,
            extraHeaders: [:],
            body: "<html>Bad Gateway</html>",
            expectedError: .serviceUnavailable(statusCode: 502, retryAfter: nil)
        ),
    ] as [ErrorResponseCase]

    /// 串流中途 `error` 事件的範例表，每一列是 `error` 事件的 data 與它預期的結果
    private static let errorEventCases = [
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 529, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"api_error","message":"Internal server error"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 504, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"type":"new_unknown_error","message":"Something went wrong."}}"#,
            expectation: .invalidResponse(
                containing: ["new_unknown_error", "Something went wrong."]
            )
        ),
        ErrorEventCase(
            data: #"{"type":"error","error":{"message":"Something went wrong."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"type":"error"}"#,
            expectation: .invalidResponse(containing: [])
        ),
        ErrorEventCase(data: "not json", expectation: .invalidResponse(containing: [])),
    ] as [ErrorEventCase]

    // spectra-scenario: anthropic-provider / Classify HTTP error responses
    // spectra-scenario: anthropic-provider / Classify HTTP error responses / error responses
    /// 驗證非 2xx 的 Messages API 回應依 `error.type` 與標頭分類，結果與範例表預期的錯誤一致
    ///
    /// - Parameter testCase: 一列範例：狀態碼、額外的標頭、回應內容與預期的錯誤
    /// - Note: 409 `conflict_error` 不在分類規則列出的 `error.type` 裡，依預設分類為沒有訊息的無效請求
    /// - Note: `error` 物件沒有 `error.type` 的 400 也依預設分類，所以 `error.message` 不放進無效請求
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
    /// - Note: 不認得的 `error.type` 只比對是無效回應，而且說明文字同時含 `error.type` 與 `error.message`
    /// - Note: data 不是 JSON，以及沒有 `error` 物件的列，只比對是無效回應，原因文字不比對
    @Test(.timeLimit(.minutes(1)), arguments: LKAnthropicClientErrorTests.errorEventCases)
    func stream_串流中途的error事件_先交出文字再以範例表的錯誤結束(testCase: ErrorEventCase) async throws {
        // Given
        let client = LKAnthropicClientTestSupport.makeClient(events: [
            .messageStart(),
            .textBlockStart(),
            .textDelta("Hel"),
            .init(event: "error", data: testCase.data),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKAnthropicClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        #expect(matches(error, testCase.expectation), "Actual error: \(error)")
    }

    /// 驗證連線失敗時，串流與非串流呼叫都丟出 `transport`，並保留底層 `URLError` 的代碼
    ///
    /// - Parameter mode: 呼叫方式，串流或非串流
    @Test(.timeLimit(.minutes(1)), arguments: LKAIChatClientProtocolTestSupport.CallMode.allCases)
    func stream與invoke_連線失敗_丟出transport且保留底層錯誤代碼(
        mode: LKAIChatClientProtocolTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.failFetch(with: .transport(underlying: URLError(.notConnectedToInternet)))
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: mode
        )

        // Then
        let error = try #require(actualError)
        let code: URLError.Code? = if case .transport(let underlying) = error {
            underlying.code
        } else {
            nil
        }
        #expect(code == .notConnectedToInternet)
    }

    /// 驗證串流送出文字後連線中斷，先交出已收到的文字，再丟出 `transport`，並保留底層代碼
    ///
    /// - Note: 中斷的錯誤要用 `LKAIError.transport` 送出，裸的 `URLError` 會被降級成無效回應
    @Test(.timeLimit(.minutes(1)))
    func stream_送出文字後連線中斷_先交出文字再丟出transport且保留底層錯誤代碼() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.yield(lines: LKAIServerSentEventTestSupport.lines(of: [
            .messageStart(),
            .textBlockStart(),
            .textDelta("Hel"),
        ]))
        mock.finish(throwing: LKAIError.transport(underlying: URLError(.networkConnectionLost)))
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKAnthropicClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        let code: URLError.Code? = if case .transport(let underlying) = error {
            underlying.code
        } else {
            nil
        }
        #expect(code == .networkConnectionLost)
    }

    /// 驗證讀取非 2xx 回應的錯誤內容時連線中斷，兩種呼叫都丟出 `transport`，並保留底層代碼
    ///
    /// - Parameter mode: 呼叫方式，串流或非串流
    @Test(.timeLimit(.minutes(1)), arguments: LKAIChatClientProtocolTestSupport.CallMode.allCases)
    func stream與invoke_讀取錯誤內容時連線中斷_丟出transport且保留底層錯誤代碼(
        mode: LKAIChatClientProtocolTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient(
            statusCode: 500,
            headers: ["content-type": "application/json"]
        )
        mock.yield(#"{"type":"error","error":{"type":"api_error","#)
        mock.finish(throwing: LKAIError.transport(underlying: URLError(.networkConnectionLost)))
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: mode
        )

        // Then
        let error = try #require(actualError)
        let code: URLError.Code? = if case .transport(let underlying) = error {
            underlying.code
        } else {
            nil
        }
        #expect(code == .networkConnectionLost)
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

    /// `error` 事件的預期結果：指定的錯誤，或只要求是無效回應且說明含指定的文字
    enum Expectation: Sendable {

        /// 丟出的錯誤必須等於指定的錯誤
        ///
        /// - Parameter error: 預期的錯誤
        case error(LKAIError)

        /// 丟出的錯誤必須是無效回應，而且說明文字含全部指定的文字
        ///
        /// - Parameter containing: 說明文字必須含有的文字；傳空陣列表示不比對說明文字
        case invalidResponse(containing: [String])
    }
}

// MARK: - Private Method

private extension LKAnthropicClientErrorTests {

    /// 判斷丟出的錯誤是否符合預期的結果
    ///
    /// - Parameters:
    ///   - error: 實際丟出的錯誤
    ///   - expectation: 預期的結果
    /// - Returns: 符合時為 `true`；預期無效回應時，錯誤必須是無效回應，而且說明文字含全部指定的文字
    func matches(_ error: LKAIError, _ expectation: Expectation) -> Bool {
        switch expectation {
        case .error(let expectedError):
            return error == expectedError

        case .invalidResponse(let fragments):
            guard case .invalidResponse(let reason) = error else {
                return false
            }
            return fragments.allSatisfy { reason.contains($0) }
        }
    }
}
