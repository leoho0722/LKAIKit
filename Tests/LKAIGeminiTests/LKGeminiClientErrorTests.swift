//
//  LKGeminiClientErrorTests.swift
//  LKAIGeminiTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIGemini

/// `LKGeminiClient` 的錯誤對應測試，以 `LKAIMockHTTPClient` 回出各種錯誤回應與 `error` 事件，不連網
struct LKGeminiClientErrorTests {

    // MARK: - Properties

    /// HTTP 錯誤回應的範例表，每一列是一種錯誤回應與它預期的錯誤
    private static let errorResponseCases = [
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"message":"Input blocked: prohibited content.","code":"prohibited_content"}}"#,
            expectedError: .refused(detail: "prohibited_content")
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"message":"The response was blocked.","code":"safety"}}"#,
            expectedError: .refused(detail: "safety")
        ),
        ErrorResponseCase(
            statusCode: 402,
            extraHeaders: [:],
            body: #"{"error":{"message":"Your Prepay credit balance is depleted.","code":"payment_required"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: ["retry-after": "20"],
            body: #"{"error":{"message":"You have exceeded your daily quota.","code":"quota_exceeded"}}"#,
            expectedError: .quotaExceeded
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: ["retry-after": "27"],
            body: #"{"error":{"message":"Rate limit exceeded. Please retry in 27s.","code":"too_many_requests"}}"#,
            expectedError: .rateLimited(retryAfter: .seconds(27))
        ),
        ErrorResponseCase(
            statusCode: 429,
            extraHeaders: [:],
            body: #"{"error":{"message":"Rate limit exceeded.","code":"rate_limit_exceeded"}}"#,
            expectedError: .rateLimited(retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"message":"max_output_tokens greater than 1048576 is not supported.","code":"invalid_request"}}"#,
            expectedError: .invalidRequest(
                message: "max_output_tokens greater than 1048576 is not supported."
            )
        ),
        ErrorResponseCase(
            statusCode: 404,
            extraHeaders: [:],
            body: #"{"error":{"message":"Model 'gemini-0' not found.","code":"not_found"}}"#,
            expectedError: .invalidRequest(message: "Model 'gemini-0' not found.")
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"code":"invalid_request"}}"#,
            expectedError: .invalidRequest(message: nil)
        ),
        ErrorResponseCase(
            statusCode: 503,
            extraHeaders: ["retry-after": "5"],
            body: #"{"error":{"message":"This model is currently experiencing high demand.","code":"service_unavailable"}}"#,
            expectedError: .serviceUnavailable(statusCode: 503, retryAfter: .seconds(5))
        ),
        ErrorResponseCase(
            statusCode: 500,
            extraHeaders: [:],
            body: #"{"error":{"message":"An internal error has occurred.","code":"api_error"}}"#,
            expectedError: .serviceUnavailable(statusCode: 500, retryAfter: nil)
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}]"#,
            expectedError: .invalidAPIKey
        ),
        ErrorResponseCase(
            statusCode: 401,
            extraHeaders: [:],
            body: #"[{"error":{"code":401,"message":"API key not valid. Please pass a valid API key.","status":"UNAUTHENTICATED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_TOKEN_TYPE_UNSUPPORTED"}]}}]"#,
            expectedError: .invalidAPIKey
        ),
        ErrorResponseCase(
            statusCode: 403,
            extraHeaders: [:],
            body: #"[{"error":{"code":403,"message":"Permission denied on the service.","status":"PERMISSION_DENIED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_DENIED"}]}}]"#,
            expectedError: .permissionDenied
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}"#,
            expectedError: .invalidAPIKey
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"[{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}]"#,
            expectedError: .invalidRequest(message: nil)
        ),
        ErrorResponseCase(
            statusCode: 400,
            extraHeaders: [:],
            body: #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]"#,
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
            data: #"{"event_type":"error","error":{"code":"safety","message":"Blocked."}}"#,
            expectation: .error(.refused(detail: "safety"))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"recitation","message":"Blocked."}}"#,
            expectation: .error(.refused(detail: "recitation"))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"rate_limit_exceeded","message":"Rate limit exceeded."}}"#,
            expectation: .error(.rateLimited(retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"too_many_requests","message":"Too many requests."}}"#,
            expectation: .error(.rateLimited(retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"quota_exceeded","message":"Daily quota exceeded."}}"#,
            expectation: .error(.quotaExceeded)
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"api_error","message":"Internal error."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"bad_gateway","message":"Bad gateway."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 502, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"service_unavailable","message":"High demand."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 503, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"gateway_timeout","message":"Deadline expired before operation could complete."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 504, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"deadline_exceeded","message":"Deadline exceeded."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 504, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"authentication","message":"API key not valid."}}"#,
            expectation: .error(.invalidAPIKey)
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"permission_denied","message":"Permission denied."}}"#,
            expectation: .error(.permissionDenied)
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"invalid_request","message":"Invalid request."}}"#,
            expectation: .error(.invalidRequest(message: "Invalid request."))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":"new_unknown_code","message":"Something went wrong."}}"#,
            expectation: .invalidResponse(containing: ["new_unknown_code", "Something went wrong."])
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":null,"message":"Something went wrong."}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{}}"#,
            expectation: .error(.serviceUnavailable(statusCode: 500, retryAfter: nil))
        ),
        ErrorEventCase(
            data: #"{"event_type":"error"}"#,
            expectation: .invalidResponse(containing: [])
        ),
        ErrorEventCase(
            data: #"{"event_type":"error","error":{"code":500,"message":"Something went wrong."}}"#,
            expectation: .invalidResponse(containing: [])
        ),
    ] as [ErrorEventCase]

    // spectra-scenario: gemini-provider / Classify HTTP error responses
    // spectra-scenario: gemini-provider / Classify HTTP error responses / error responses
    /// 驗證非 2xx 的 Interactions API 回應依兩種錯誤格式與狀態碼分類，結果與範例表預期的錯誤一致
    ///
    /// - Parameter testCase: 一列範例：狀態碼、額外的標頭、回應內容與預期的錯誤
    /// - Note: 被擋下的代碼與額度的代碼優先於狀態碼，所以 400 與 429 也可能分類成拒答或額度用完
    /// - Note: 額度用完的回應即使帶 `retry-after` 標頭，也不是限流，不帶等待時間
    /// - Note: Google 通用格式只有 `details` 裡有 `API_KEY_INVALID` 的才是無效的金鑰，其餘走預設分類
    /// - Note: 401、402、403 與 429 限流、5xx 以及內容不是 JSON 的回應，走 chat-client 的預設狀態碼分類
    @Test(.timeLimit(.minutes(1)), arguments: LKGeminiClientErrorTests.errorResponseCases)
    func invoke_HTTP錯誤回應_依錯誤內容與狀態碼分類為範例表的錯誤(testCase: ErrorResponseCase) async throws {
        // Given
        let headers = ["content-type": "application/json"]
            .merging(testCase.extraHeaders) { _, new in new }
        let mock = LKAIMockHTTPClient(statusCode: testCase.statusCode, headers: headers)
        mock.yield(testCase.body)
        mock.finish()
        let client = LKGeminiClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKGeminiClientTestSupport.validRequest,
            mode: .invoke
        )

        // Then
        let error = try #require(actualError)
        #expect(error == testCase.expectedError)
    }

    // spectra-scenario: gemini-provider / Error event in the middle of a stream
    // spectra-scenario: gemini-provider / Error event in the middle of a stream / error event data
    /// 驗證串流中途的 `error` 事件依 `error.code` 分類：先交出已收到的文字，再以範例表預期的結果結束
    ///
    /// - Parameter testCase: 一列範例：`error` 事件的 data，以及預期的結果
    /// - Note: `error` 事件之後再接一個狀態是 `completed` 的 `interaction.completed`，
    ///   忽略 `error` 事件的實作會多交出一個完成事件，測試就會失敗
    /// - Note: 不認得的代碼只比對是無效回應，而且說明文字同時含代碼與 `message`
    /// - Note: 沒有 `error` 物件，以及 `code` 是數字的列，只比對是無效回應，原因文字不比對
    @Test(.timeLimit(.minutes(1)), arguments: LKGeminiClientErrorTests.errorEventCases)
    func stream_串流中途的error事件_先交出文字再以範例表的錯誤結束(testCase: ErrorEventCase) async throws {
        // Given
        let client = LKGeminiClientTestSupport.makeClient(events: [
            .stepStart(index: 0, type: "model_output"),
            .stepDelta(index: 0, text: "Hel"),
            LKAIServerSentEvent(event: "error", data: testCase.data),
            .interactionCompleted(),
        ])

        // When
        let outcome = await LKAIChatClientProtocolTestSupport.collectOutcome(
            from: client,
            request: LKGeminiClientTestSupport.validRequest
        )

        // Then
        #expect(outcome.events == [.textDelta("Hel")])
        let error = try #require(outcome.error)
        #expect(testCase.expectation.matches(error), "Actual error: \(error)")
    }
}

// MARK: - Nested Types

extension LKGeminiClientErrorTests {

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
        let expectation: LKAIErrorTestSupport.Expectation
    }
}
