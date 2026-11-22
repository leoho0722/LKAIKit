//
//  LKAITestJSONTests.swift
//  LKAITestSupportTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAITestSupport
import Testing

/// `LKAITestJSON` 的單元測試，檢查可有可無的欄位怎麼組、布林欄位怎麼取，以及解析失敗的問題記在哪裡
///
/// - Note: `jsonObject` 與 `jsonFragment` 只轉呼叫 `JSONSerialization`，成功解析的結果不另外寫測試
/// - Note: `jsonObject` 解析失敗時問題記在哪裡，由下面的測試檢查；`jsonFragment` 不會失敗，不測
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

    /// 驗證 `jsonObject(from:)` 的文字版與 `Data` 版，遇到最外層不是物件的 JSON 時，
    /// 失敗的問題記在呼叫端的測試檔，看得出是哪個測試，而不是記在 helper 自己的檔案
    ///
    /// - Parameter variant: 要呼叫的版本，文字版或 `Data` 版
    /// - Note: 傳入最外層是陣列的 `[1]`，helper 內的 `#require` 會記下問題並丟出錯誤
    /// - Note: `withKnownIssue` 只把 `#require` 記下的預期失敗，而且記在 `LKAITestJSONTests.swift`
    ///   的問題當成已知問題；問題記在別的檔案時，它不放過，而且會另外回報沒有等到預期的問題
    /// - Note: 限定問題的種類，是因為 helper 若改成直接丟一般錯誤，`withKnownIssue` 會把它記成
    ///   「捕捉到錯誤」的問題，位置是這個檔案裡的 `withKnownIssue` 呼叫，只比對檔名會放過它
    @Test(arguments: JSONObjectVariant.allCases)
    func jsonObject_最外層不是物件_問題記在呼叫端的測試檔(variant: JSONObjectVariant) throws {
        // Given
        let invalidJSON = "[1]"

        // When

        // Then
        // `withKnownIssue` 一次執行動作並比對問題記在哪個檔案，所以兩段寫在同一個呼叫
        try withKnownIssue {
            _ = try variant.parse(invalidJSON)
        } matching: { issue in
            guard case .expectationFailed = issue.kind else {
                return false
            }
            return issue.sourceLocation?.fileName == "LKAITestJSONTests.swift"
        }
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

    /// `jsonObject(from:)` 的兩個版本，參數化測試的一列
    enum JSONObjectVariant: CaseIterable, Sendable {

        /// 文字版，傳入 JSON 文字
        case text

        /// `Data` 版，傳入 JSON 資料
        case data

        /// 以這個版本解析 JSON 文字
        ///
        /// - Parameter json: JSON 文字，最外層必須是物件
        /// - Returns: 解析出的 JSON 物件
        /// - Throws: 文字不是合法的 JSON，或最外層不是物件時丟出
        func parse(_ json: String) throws -> NSDictionary {
            switch self {
            case .text:
                return try LKAITestJSON.jsonObject(from: json)

            case .data:
                return try LKAITestJSON.jsonObject(from: Data(json.utf8))
            }
        }
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
