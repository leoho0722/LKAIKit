//
//  LKAIErrorTestSupportTests.swift
//  LKAITestSupportTests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore
import LKAITestSupport
import Testing

/// `LKAIErrorTestSupport` 的單元測試，檢查預期的錯誤結果與實際丟出的錯誤是否相符的判斷
struct LKAIErrorTestSupportTests {

    /// 驗證 `matches(_:)` 只有在錯誤與預期相符時回傳 `true`：指定的錯誤要相等，預期無效回應時錯誤要是無效回應，
    /// 而且說明文字含全部指定的片段；沒有錯誤一律不符合，即使預期的片段清單是空的
    ///
    /// - Parameter testCase: 這一列的預期結果、實際丟出的錯誤與預期的判斷結果
    @Test(arguments: [
        MatchCase(
            expectation: .error(.invalidAPIKey),
            error: .invalidAPIKey,
            expectedResult: true
        ),
        MatchCase(
            expectation: .error(.invalidAPIKey),
            error: .permissionDenied,
            expectedResult: false
        ),
        MatchCase(
            expectation: .invalidResponse(containing: ["unknown_error", "Something went wrong."]),
            error: .invalidResponse(reason: "unknown_error: Something went wrong."),
            expectedResult: true
        ),
        MatchCase(
            expectation: .invalidResponse(containing: ["unknown_error", "Other message."]),
            error: .invalidResponse(reason: "unknown_error: Something went wrong."),
            expectedResult: false
        ),
        MatchCase(
            expectation: .invalidResponse(containing: ["unknown_error"]),
            error: .invalidAPIKey,
            expectedResult: false
        ),
        MatchCase(
            expectation: .invalidResponse(containing: []),
            error: .invalidResponse(reason: "Any reason."),
            expectedResult: true
        ),
        MatchCase(
            expectation: .invalidResponse(containing: []),
            error: nil,
            expectedResult: false
        ),
    ])
    func matches_各種錯誤與預期的組合_只有相符時為true(testCase: MatchCase) {
        // Given
        let expectation = testCase.expectation

        // When
        let actualResult = expectation.matches(testCase.error)

        // Then
        #expect(actualResult == testCase.expectedResult)
    }
}

// MARK: - Nested Types

extension LKAIErrorTestSupportTests {

    /// 一列測試參數：預期的錯誤結果、實際丟出的錯誤，以及預期的判斷結果
    struct MatchCase: Sendable {

        /// 測試預期的錯誤結果
        let expectation: LKAIErrorTestSupport.Expectation

        /// 實際丟出的錯誤；nil 表示沒有丟出錯誤
        let error: LKAIError?

        /// `matches(_:)` 預期的判斷結果
        let expectedResult: Bool
    }
}
