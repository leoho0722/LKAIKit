//
//  LKOpenAIClientErrorTests.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIOpenAI

/// `LKOpenAIClient` 的錯誤對應測試，以 `LKAIMockHTTPClient` 回出各種錯誤回應、`error` 事件與 `response.failed` 事件，不連網
struct LKOpenAIClientErrorTests {

    // MARK: - Properties

    /// HTTP 錯誤回應的範例表，每一列是一種錯誤回應與它預期的錯誤
    private static let errorResponseCases = [
        ErrorResponseCase(
            statusCode: 401,
            extraHeaders: [:],
            body: #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}}"#,
            expectedError: .invalidAPIKey
        ),
        ErrorResponseCase(
            statusCode: 403,
            extraHeaders: [:],
            body: #"{"error":{"message":"Country, region, or territory not supported","type":"request_forbidden","code":"unsupported_country_region_territory"}}"#,
            expectedError: .permissionDenied
        ),
        ErrorResponseCase(
            statusCode: 403,
            extraHeaders: [:],
            body: #"{"error":{"message":"This request was stopped by misalignment monitoring.","type":"invalid_request_error","code":"misalignment_policy_violation"}}"#,
            expectedError: .refused(detail: "misalignment_policy_violation")
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"message":"This request was flagged as potentially suspicious.","type":"invalid_request_error","code":"cyber_policy"}}"#,
            expectedError: .refused(detail: "cyber_policy")
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: ["retry-after": "20"],
            body: #"{"error":{"message":"Rate limit reached for requests","type":"requests","code":"rate_limit_exceeded"}}"#,
            expectedError: .rateLimited(retryAfter: .seconds(20))
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Please slow down.","type":"rate_limit_error","code":"slow_down"}}"#,
            expectedError: .rateLimited(retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: ["retry-after": "20"],
            body: #"{"error":{"message":"Your credit balance is exhausted.","type":"insufficient_quota","code":"credit_balance_exhausted"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Organization spend limit exceeded.","type":"requests","code":"organization_spend_limit_exceeded"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Project spend limit exceeded.","type":"requests","code":"project_spend_limit_exceeded"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Organization usage limit exceeded.","type":"requests","code":"organization_usage_limit_exceeded"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Billing hard limit reached.","type":"requests","code":"billing_hard_limit_reached"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Quota exhausted.","type":"insufficient_quota","code":null}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"type":"insufficient_quota","code":"insufficient_quota"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"message":"Your input exceeds the context window of this model.","type":"invalid_request_error","code":null}}"#,
            expectedError: .invalidRequest(
                message: "Your input exceeds the context window of this model."
            )
        ),
        ErrorResponseCase(
            statusCode: 404,
            extraHeaders: [:],
            body: #"{"error":{"message":"The model 'gpt-0' does not exist.","type":"invalid_request_error","code":"model_not_found"}}"#,
            expectedError: .invalidRequest(message: "The model 'gpt-0' does not exist.")
        ),
        ErrorResponseCase(
            statusCode: 503,
            extraHeaders: ["retry-after": "5"],
            body: #"{"error":{"message":"Model temporarily overloaded","type":"service_unavailable_error","code":"server_is_overloaded"}}"#,
            expectedError: .serviceUnavailable(statusCode: 503)
        ),
        ErrorResponseCase(
            statusCode: 500,
            extraHeaders: [:],
            body: #"{"error":{"message":"The server had an error while processing your request.","type":"server_error","code":null}}"#,
            expectedError: .serviceUnavailable(statusCode: 500)
        ),
        ErrorResponseCase(
            statusCode: 502,
            extraHeaders: [:],
            body: "<html>Bad Gateway</html>",
            expectedError: .serviceUnavailable(statusCode: 502)
        ),
    ] as [ErrorResponseCase]

    /// 串流中途 `error` 事件的範例表，每一列是事件的 `code` 與 `message`，以及預期的結果
    private static let errorEventCases = [
        ErrorEventCase(
            code: "rate_limit_exceeded",
            message: "Rate limit reached.",
            expectation: .error(.rateLimited(retryAfter: nil))
        ),
        ErrorEventCase(
            code: "slow_down",
            message: "Please slow down.",
            expectation: .error(.rateLimited(retryAfter: nil))
        ),
        ErrorEventCase(
            code: "insufficient_quota",
            message: "You exceeded your current quota.",
            expectation: .error(.quotaExceeded)
        ),
        ErrorEventCase(
            code: "server_is_overloaded",
            message: "Model temporarily overloaded",
            expectation: .error(.serviceUnavailable(statusCode: 503))
        ),
        ErrorEventCase(
            code: "server_error",
            message: "The model failed to generate a response.",
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
        ErrorEventCase(
            code: "vector_store_timeout",
            message: "Vector store timed out.",
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
        ErrorEventCase(
            code: "cyber_policy",
            message: "Request flagged.",
            expectation: .error(.refused(detail: "cyber_policy"))
        ),
        ErrorEventCase(
            code: "bio_policy",
            message: "Request blocked.",
            expectation: .error(.refused(detail: "bio_policy"))
        ),
        ErrorEventCase(
            code: "misalignment_policy_violation",
            message: "Request stopped.",
            expectation: .error(.refused(detail: "misalignment_policy_violation"))
        ),
        ErrorEventCase(
            code: "invalid_prompt",
            message: "Invalid prompt.",
            expectation: .error(.invalidRequest(message: "Invalid prompt."))
        ),
        ErrorEventCase(
            code: "new_unknown_code",
            message: "Something went wrong.",
            expectation: .invalidResponse(containing: ["new_unknown_code", "Something went wrong."])
        ),
        ErrorEventCase(
            code: nil,
            message: "Something went wrong.",
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
    ] as [ErrorEventCase]

    /// `response.failed` 事件的範例表，每一列是 `response.error` 的 JSON，以及預期的結果
    private static let failedResponseCases = [
        FailedResponseCase(
            errorJSON: #"{"code":"rate_limit_exceeded","message":"Rate limit reached."}"#,
            expectation: .error(.rateLimited(retryAfter: nil))
        ),
        FailedResponseCase(
            errorJSON: #"{"code":"server_error","message":"The model failed to generate a response."}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
        FailedResponseCase(
            errorJSON: #"{"code":"bio_policy","message":"Request blocked."}"#,
            expectation: .error(.refused(detail: "bio_policy"))
        ),
        FailedResponseCase(
            errorJSON: #"{"code":"invalid_prompt","message":"Invalid prompt."}"#,
            expectation: .error(.invalidRequest(message: "Invalid prompt."))
        ),
        FailedResponseCase(
            errorJSON: #"{"code":"new_unknown_code","message":"Something went wrong."}"#,
            expectation: .invalidResponse(containing: ["new_unknown_code", "Something went wrong."])
        ),
        FailedResponseCase(
            errorJSON: nil,
            expectation: .error(.serviceUnavailable(statusCode: 500))
        ),
    ] as [FailedResponseCase]

    // spectra-scenario: openai-provider / Classify HTTP error responses
    // spectra-scenario: openai-provider / Classify HTTP error responses / error responses
    /// 驗證非 2xx 的 Responses API 回應依 `error.code`、`error.type` 與狀態碼分類，結果與範例表預期的錯誤一致
    ///
    /// - Parameter testCase: 一列範例：狀態碼、額外的標頭、回應內容與預期的錯誤
    /// - Note: 政策性阻擋與額度的代碼優先於狀態碼，所以 403 與 429 也可能分類成拒答或額度用完
    /// - Note: 額度用完的回應即使帶 `retry-after` 標頭，也不是限流，不帶等待時間
    /// - Note: 401、403 與 429 限流、5xx 以及內容不是 JSON 的回應，走 chat-client 的預設狀態碼分類
    @Test(.timeLimit(.minutes(1)), arguments: LKOpenAIClientErrorTests.errorResponseCases)
    func invoke_HTTP錯誤回應_依錯誤內容與狀態碼分類為範例表的錯誤(testCase: ErrorResponseCase) async throws {
        // Given
        let headers = ["content-type": "application/json"]
            .merging(testCase.extraHeaders) { _, new in new }
        let mock = LKAIMockHTTPClient(statusCode: testCase.statusCode, headers: headers)
        mock.yield(testCase.body)
        mock.finish()
        let client = LKOpenAIClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKOpenAIClientTestSupport.validRequest,
            mode: .invoke
        )

        // Then
        let error = try #require(actualError)
        #expect(error == testCase.expectedError)
    }

    // spectra-scenario: openai-provider / Error event in the middle of a stream
    // spectra-scenario: openai-provider / Error event in the middle of a stream / error event codes
    /// 驗證串流中途的 `error` 事件依 `code` 分類：先交出已收到的文字，再以範例表預期的結果結束
    ///
    /// - Parameter testCase: 一列範例：`error` 事件的 `code` 與 `message`，以及預期的結果
    /// - Note: `error` 事件之後再接一個 `response.completed`，忽略 `error` 事件的實作會多交出一個完成事件，測試就會失敗
    /// - Note: 不認得的代碼只比對是無效回應，而且說明文字同時含代碼與 `message`
    @Test(.timeLimit(.minutes(1)), arguments: LKOpenAIClientErrorTests.errorEventCases)
    func stream_串流中途的error事件_先交出文字再以範例表的錯誤結束(testCase: ErrorEventCase) async throws {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .outputTextDelta("Hel"),
            .errorEvent(code: testCase.code, message: testCase.message),
            .responseCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        #expect(matches(error, testCase.expectation), "Actual error: \(error)")
    }

    // spectra-scenario: openai-provider / Failed response in the middle of a stream
    // spectra-scenario: openai-provider / Failed response in the middle of a stream / failed response errors
    /// 驗證串流中途的 `response.failed` 事件依 `response.error` 的 `code` 分類：先交出已收到的文字，再以範例表預期的結果結束
    ///
    /// - Parameter testCase: 一列範例：`response.error` 的 JSON（nil 表示沒有這個鍵），以及預期的結果
    /// - Note: `response.failed` 之後再接一個 `response.completed`
    /// - Note: 忽略 `response.failed` 的實作會多交出一個完成事件，測試就會失敗
    /// - Note: 不認得的代碼只比對是無效回應，而且說明文字同時含代碼與 `message`
    @Test(.timeLimit(.minutes(1)), arguments: LKOpenAIClientErrorTests.failedResponseCases)
    func stream_串流中途的responseFailed_先交出文字再以範例表的錯誤結束(
        testCase: FailedResponseCase
    ) async throws {
        // Given
        let client = LKOpenAIClientTestSupport.makeClient(events: [
            .outputTextDelta("Hel"),
            .responseFailed(error: testCase.errorJSON),
            .responseCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKOpenAIClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        #expect(matches(error, testCase.expectation), "Actual error: \(error)")
    }
}

// MARK: - Nested Types

extension LKOpenAIClientErrorTests {

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

    /// 串流中途 `error` 事件範例表的一列：事件的代碼與說明，以及預期的結果
    struct ErrorEventCase: Sendable {

        /// `error` 事件的 `code`；nil 表示 JSON 裡寫成 null
        let code: String?

        /// `error` 事件的 `message`
        let message: String

        /// 預期的結果
        let expectation: Expectation
    }

    /// `response.failed` 事件範例表的一列：`response.error` 的 JSON，以及預期的結果
    struct FailedResponseCase: Sendable {

        /// `response.error` 的 JSON 文字；nil 表示 `response` 裡沒有 `error` 這個鍵
        let errorJSON: String?

        /// 預期的結果
        let expectation: Expectation
    }

    /// 串流中途錯誤的預期結果：指定的錯誤，或只要求是無效回應且說明含指定的文字
    enum Expectation: Sendable {

        /// 丟出的錯誤必須等於指定的錯誤
        ///
        /// - Parameter error: 預期的錯誤
        case error(LKAIError)

        /// 丟出的錯誤必須是無效回應，而且說明文字含全部指定的文字
        ///
        /// - Parameter containing: 說明文字必須含有的文字
        case invalidResponse(containing: [String])
    }
}

// MARK: - Private Method

private extension LKOpenAIClientErrorTests {

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
