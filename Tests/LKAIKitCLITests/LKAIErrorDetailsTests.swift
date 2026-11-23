//
//  LKAIErrorDetailsTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAIError` 在 `lkai` 的技術細節（`details`）的單元測試：每種錯誤給出什麼細節
struct LKAIErrorDetailsTests {

    // spectra-scenario: cli-chat / Report the error and its detail
    // spectra-scenario: cli-chat / Report the error and its detail / detail lines
    /// 驗證每種錯誤的 `details` 都與範例表一致，沒有細節的錯誤為 nil，細節是空字串時也視同沒有
    ///
    /// - Parameters:
    ///   - error: 要取細節的錯誤
    ///   - expectedDetails: 預期的細節，不含 `Details: ` 前綴；沒有細節時為 nil
    /// - Note: 範例表之外多加的列：細節是空字串的三種錯誤，以及另一個 `URLError` 代碼，
    ///   確認細節的代碼來自錯誤本身，不是寫死的 -1001
    @Test(arguments: [
        (.invalidRequest(message: "model not found"), "model not found"),
        (.invalidRequest(message: nil), nil),
        (.invalidRequest(message: ""), nil),
        (.refused(detail: "cyber"), "cyber"),
        (.refused(detail: nil), nil),
        (.refused(detail: ""), nil),
        (
            .invalidResponse(reason: "Stream ended before a finish event"),
            "Stream ended before a finish event"
        ),
        (.invalidResponse(reason: ""), nil),
        (.transport(underlying: URLError(.timedOut)), "URLError -1001"),
        (.transport(underlying: URLError(.notConnectedToInternet)), "URLError -1009"),
        (.rateLimited(retryAfter: .seconds(30)), "retry after 30 seconds"),
        (.rateLimited(retryAfter: nil), nil),
        (.serviceUnavailable(statusCode: 503, retryAfter: nil), "status 503"),
        (
            .serviceUnavailable(statusCode: 529, retryAfter: .seconds(10)),
            "status 529, retry after 10 seconds"
        ),
        (.invalidAPIKey, nil),
        (.permissionDenied, nil),
        (.quotaExceeded, nil),
        (.cancelled, nil),
    ] as [(LKAIError, String?)])
    func details_各種錯誤_與範例表的細節一致(error: LKAIError, expectedDetails: String?) {
        // Given

        // When
        let actualDetails = error.details

        // Then
        #expect(actualDetails == expectedDetails)
    }
}
