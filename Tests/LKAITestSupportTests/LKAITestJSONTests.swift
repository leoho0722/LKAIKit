//
//  LKAITestJSONTests.swift
//  LKAITestSupportTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAITestSupport
import Testing

/// `LKAITestJSON` 的單元測試，檢查可有可無的欄位怎麼組，以及布林欄位怎麼取
///
/// - Note: `jsonObject` 與 `jsonFragment` 只轉呼叫 `JSONSerialization`，不另外寫測試
struct LKAITestJSONTests {

    /// 驗證 `optionalField(_:_:)` 有值時組出前面帶逗號的 `,"名稱":值`，沒有值時回傳空字串
    ///
    /// - Parameter testCase: 這一列的欄位名稱、欄位值的 JSON 與預期的文字
    @Test(arguments: [
        OptionalFieldCase(
            name: "usage",
            json: #"{"input_tokens":1}"#,
            expectedText: #","usage":{"input_tokens":1}"#
        ),
        OptionalFieldCase(name: "usage", json: nil, expectedText: ""),
    ])
    func optionalField_欄位值有值或為nil_有值組出逗號開頭的欄位且nil為空字串(
        testCase: OptionalFieldCase
    ) {
        // Given
        let name = testCase.name

        // When
        let actualText = LKAITestJSON.optionalField(name, testCase.json)

        // Then
        #expect(actualText == testCase.expectedText)
    }

    /// 驗證 `booleanField(_:in:)` 只接受 JSON 布林：`true` 與 `false` 照原值交出，
    /// 數字 `1`、字串 `"true"` 與欄位不存在都丟出錯誤
    ///
    /// - Parameter testCase: 這一列的 JSON 文字與預期的結果
    /// - Note: 數字 `1` 與字串 `"true"` 兩列是這個 helper 存在的原因，`NSDictionary` 比對會把 `1` 當成 `true`
    @Test(arguments: [
        BooleanFieldCase(json: #"{"model":"m","stream":true}"#, expectedOutcome: .value(true)),
        BooleanFieldCase(json: #"{"model":"m","stream":false}"#, expectedOutcome: .value(false)),
        BooleanFieldCase(json: #"{"model":"m","stream":1}"#, expectedOutcome: .thrown),
        BooleanFieldCase(json: #"{"model":"m","stream":"true"}"#, expectedOutcome: .thrown),
        BooleanFieldCase(json: #"{"model":"m"}"#, expectedOutcome: .thrown),
    ])
    func booleanField_欄位的各種值_只有JSON布林照原值交出其餘丟出錯誤(
        testCase: BooleanFieldCase
    ) {
        // Given
        let data = Data(testCase.json.utf8)

        // When
        let actualOutcome: BooleanFieldCase.Outcome
        do {
            actualOutcome = try .value(LKAITestJSON.booleanField("stream", in: data))
        } catch {
            actualOutcome = .thrown
        }

        // Then
        #expect(actualOutcome == testCase.expectedOutcome)
    }
}

// MARK: - Nested Types

extension LKAITestJSONTests {

    /// `optionalField(_:_:)` 範例表的一列：欄位名稱、欄位值的 JSON，以及預期的文字
    struct OptionalFieldCase: Sendable {

        /// 欄位名稱
        let name: String

        /// 欄位值的 JSON；nil 表示不放這個欄位
        let json: String?

        /// 預期組出的文字
        let expectedText: String
    }

    /// `booleanField(_:in:)` 範例表的一列：JSON 文字，以及讀 `stream` 欄位預期的結果
    struct BooleanFieldCase: Sendable {

        /// 要讀取的 JSON 文字，最外層是物件
        let json: String

        /// 預期的結果
        let expectedOutcome: Outcome

        /// 讀 `stream` 欄位的結果：取得的布林值，或丟出錯誤
        enum Outcome: Equatable, Sendable {

            /// 取得布林值
            ///
            /// - Parameter value: 取得的布林值
            case value(Bool)

            /// 丟出錯誤
            case thrown
        }
    }
}
