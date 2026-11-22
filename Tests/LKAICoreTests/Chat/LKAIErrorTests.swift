//
//  LKAIErrorTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import Testing

@testable import LKAICore

/// `LKAIError` 的單元測試
struct LKAIErrorTests {

    // MARK: - Properties

    /// 十種錯誤各取一個值，給逐一檢查說明的測試當參數
    private static let errorKinds: [LKAIError] = [
        .invalidAPIKey,
        .permissionDenied,
        .rateLimited(retryAfter: .seconds(30)),
        .quotaExceeded,
        .serviceUnavailable(statusCode: 529, retryAfter: nil),
        .invalidRequest(message: "bad"),
        .refused(detail: "cyber"),
        .cancelled,
        .transport(underlying: URLError(.notConnectedToInternet)),
        .invalidResponse(reason: "bad data"),
    ]

    // spectra-scenario: chat-client / Report whether an error is retryable
    // spectra-scenario: chat-client / Report whether an error is retryable / retryability by error kind
    /// 驗證每一種錯誤的 `isRetryable` 都與範例表一致：限流、服務不可用、傳輸失敗可重試，其餘不可
    ///
    /// - Parameters:
    ///   - error: 要檢查的錯誤
    ///   - expectedIsRetryable: 範例表列出的可否重試
    /// - Note: 範例表之外多加「限流且沒有等待時間」一列，確認可否重試不取決於有沒有等待時間
    @Test(arguments: [
        (.invalidAPIKey, false),
        (.permissionDenied, false),
        (.rateLimited(retryAfter: .seconds(30)), true),
        (.rateLimited(retryAfter: nil), true),
        (.quotaExceeded, false),
        (.serviceUnavailable(statusCode: 529, retryAfter: nil), true),
        (.invalidRequest(message: "bad"), false),
        (.refused(detail: "cyber"), false),
        (.cancelled, false),
        (.transport(underlying: URLError(.notConnectedToInternet)), true),
        (.invalidResponse(reason: "bad data"), false),
    ] as [(LKAIError, Bool)])
    func isRetryable_各種錯誤種類_與範例表的可否重試一致(error: LKAIError, expectedIsRetryable: Bool) {
        // Given

        // When
        let isRetryable = error.isRetryable

        // Then
        #expect(isRetryable == expectedIsRetryable)
    }

    // spectra-scenario: chat-client / Classify HTTP error statuses
    // spectra-scenario: chat-client / Classify HTTP error statuses / status codes
    /// 驗證依狀態碼與 `retry-after` 標頭分類出範例表的錯誤；標頭只有純 ASCII 數字才算等待秒數
    ///
    /// - Parameter testCase: 一列範例：回應的狀態碼、標頭原始值與預期的錯誤
    /// - Note: 範例表之外多加邊界列：帶正負號、前後空白、全形數字、空字串與超出範圍的標頭，以及 4xx、5xx 範圍的邊界
    @Test(arguments: [
        StatusCase(statusCode: 401, retryAfter: nil, expectedError: .invalidAPIKey),
        StatusCase(statusCode: 403, retryAfter: nil, expectedError: .permissionDenied),
        StatusCase(statusCode: 402, retryAfter: nil, expectedError: .quotaExceeded),
        StatusCase(
            statusCode: 429,
            retryAfter: "30",
            expectedError: .rateLimited(retryAfter: .seconds(30))
        ),
        StatusCase(statusCode: 429, retryAfter: nil, expectedError: .rateLimited(retryAfter: nil)),
        StatusCase(statusCode: 429, retryAfter: "-1", expectedError: .rateLimited(retryAfter: nil)),
        StatusCase(
            statusCode: 429,
            retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT",
            expectedError: .rateLimited(retryAfter: nil)
        ),
        StatusCase(statusCode: 429, retryAfter: "+5", expectedError: .rateLimited(retryAfter: nil)),
        StatusCase(
            statusCode: 429,
            retryAfter: " 30",
            expectedError: .rateLimited(retryAfter: nil)
        ),
        StatusCase(
            statusCode: 429,
            retryAfter: "30 ",
            expectedError: .rateLimited(retryAfter: nil)
        ),
        StatusCase(
            statusCode: 429,
            retryAfter: "99999999999999999999",
            expectedError: .rateLimited(retryAfter: nil)
        ),
        StatusCase(
            statusCode: 429,
            retryAfter: "0",
            expectedError: .rateLimited(retryAfter: .seconds(0))
        ),
        StatusCase(statusCode: 429, retryAfter: "", expectedError: .rateLimited(retryAfter: nil)),
        StatusCase(statusCode: 429, retryAfter: "３０", expectedError: .rateLimited(retryAfter: nil)),
        StatusCase(statusCode: 400, retryAfter: nil, expectedError: .invalidRequest(message: nil)),
        StatusCase(statusCode: 404, retryAfter: nil, expectedError: .invalidRequest(message: nil)),
        StatusCase(statusCode: 499, retryAfter: nil, expectedError: .invalidRequest(message: nil)),
        StatusCase(
            statusCode: 500,
            retryAfter: nil,
            expectedError: .serviceUnavailable(statusCode: 500, retryAfter: nil)
        ),
        StatusCase(
            statusCode: 503,
            retryAfter: nil,
            expectedError: .serviceUnavailable(statusCode: 503, retryAfter: nil)
        ),
        StatusCase(
            statusCode: 529,
            retryAfter: nil,
            expectedError: .serviceUnavailable(statusCode: 529, retryAfter: nil)
        ),
        StatusCase(
            statusCode: 599,
            retryAfter: nil,
            expectedError: .serviceUnavailable(statusCode: 599, retryAfter: nil)
        ),
    ])
    func init_狀態碼與retryAfter標頭_分類為範例表的錯誤(testCase: StatusCase) {
        // Given

        // When
        let error = LKAIError(httpStatusCode: testCase.statusCode, retryAfter: testCase.retryAfter)

        // Then
        #expect(error == testCase.expectedError)
    }

    // spectra-scenario: chat-client / Classify HTTP error statuses
    // spectra-scenario: chat-client / Classify HTTP error statuses / status codes
    /// 驗證不屬於 4xx 與 5xx 的狀態碼（1xx、3xx 與 600 以上）都分類為無效回應
    ///
    /// - Parameter statusCode: 回應的 HTTP 狀態碼：範例表的 302，加上 1xx、3xx 的邊界與 5xx 之後的邊界
    /// - Note: 只比對是不是無效回應，不比對原因文字，spec 沒有規定它
    @Test(arguments: [101, 302, 399, 600])
    func init_非4xx與5xx的狀態碼_分類為無效回應(statusCode: Int) {
        // Given

        // When
        let error = LKAIError(httpStatusCode: statusCode, retryAfter: nil)

        // Then
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(isInvalidResponse)
    }

    // spectra-scenario: chat-client / Look up the description of each error kind
    // spectra-scenario: chat-client / Look up the description of each error kind / supported languages
    /// 驗證在 `en` 與 `zh-Hant` 的語言資料夾，每種錯誤都查得到非空、且不是 key 本身的說明
    ///
    /// - Parameters:
    ///   - language: 語言資料夾的名稱，不含 `.lproj`
    ///   - error: 要查說明的錯誤
    @Test(arguments: ["en", "zh-Hant"], LKAIErrorTests.errorKinds)
    func localizationKey_在支援的語言查詢_說明非空且不等於key(language: String, error: LKAIError) throws {
        // Given
        let bundlePath = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        let languageBundle = try #require(Bundle(path: bundlePath))

        // When
        let description = languageBundle.localizedString(
            forKey: error.localizationKey,
            value: nil,
            table: nil
        )

        // Then
        #expect(!description.isEmpty)
        #expect(description != error.localizationKey)
    }

    /// 驗證每種錯誤的 `errorDescription` 都有內容：不是 nil、不是空字串，也不是查不到時原樣回傳的 key
    ///
    /// - Parameter error: 要讀取說明的錯誤
    /// - Note: 走目前語言的查詢路徑，確認 `errorDescription` 讀的是 `LKAICore` 的資源
    @Test(arguments: LKAIErrorTests.errorKinds)
    func errorDescription_各種錯誤_回傳非空且不等於key的說明(error: LKAIError) throws {
        // Given

        // When
        let actualDescription = error.errorDescription

        // Then
        let description = try #require(actualDescription)
        #expect(!description.isEmpty)
        #expect(description != error.localizationKey)
    }

    // spectra-scenario: chat-client / Use English as the development language
    /// 驗證 `LKAICore` 資源的開發語言是 `en`，語言清單含 `en` 與 `zh-Hant`；其他語言的使用者因此看到英文
    @Test
    func developmentLocalization_讀取LKAICore資源_開發語言為英文且支援英文與正體中文() {
        // Given
        let resourceBundle = Bundle.module

        // When
        let developmentLocalization = resourceBundle.developmentLocalization
        let localizations = resourceBundle.localizations

        // Then
        #expect(developmentLocalization == "en")
        #expect(localizations.contains("en"))
        #expect(localizations.contains("zh-Hant"))
    }

    // spectra-scenario: chat-client / Keep provider text out of the description
    /// 驗證錯誤說明是通用訊息，不含供應商回報的訊息或拒答原因，說明本身也不是 nil
    ///
    /// - Parameters:
    ///   - error: 帶有供應商文字的錯誤
    ///   - providerText: 錯誤內帶的供應商文字，說明不得出現它
    @Test(arguments: [
        (.invalidRequest(message: "max_tokens: too large"), "max_tokens: too large"),
        (.refused(detail: "cyber"), "cyber"),
    ] as [(LKAIError, String)])
    func errorDescription_含供應商文字的錯誤_說明不含該文字(error: LKAIError, providerText: String) throws {
        // Given

        // When
        let actualDescription = error.errorDescription

        // Then
        let description = try #require(actualDescription)
        #expect(!description.contains(providerText))
    }

    /// 驗證傳輸失敗的說明不含底層 `URLError` 自帶的說明文字
    @Test
    func errorDescription_傳輸錯誤帶有底層說明_說明不含底層錯誤的文字() throws {
        // Given
        let underlying = URLError(
            .notConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "offline-detail"]
        )
        let error = LKAIError.transport(underlying: underlying)

        // When
        let actualDescription = error.errorDescription

        // Then
        let description = try #require(actualDescription)
        #expect(!description.contains("offline-detail"))
    }
}

// MARK: - Nested Types

extension LKAIErrorTests {

    /// HTTP 狀態碼分類的一列範例：回應的狀態碼與 `retry-after` 標頭，以及預期分類出的錯誤
    struct StatusCase {

        /// 回應的 HTTP 狀態碼
        let statusCode: Int

        /// `retry-after` 標頭的原始值，沒有標頭時為 nil
        let retryAfter: String?

        /// 預期分類出的錯誤
        let expectedError: LKAIError
    }
}
