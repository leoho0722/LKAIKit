//
//  LKAILocalizationTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import Testing

@testable import LKAICore

/// `LKAILocalization` 的單元測試：指定語言查 String Catalog，以及查不到時的退路
///
/// - Note: 查詢對象是 `LKAICore` 既有的錯誤說明 key，`en` 與 `zh-Hant` 的文字不同
/// - Note: 期望值從 `.lproj` 子 bundle 或 bundle 預設的查詢直接取得，不經過 `LKAILocalization`
struct LKAILocalizationTests {

    // MARK: - Properties

    /// 查詢用的 key，取 `LKAICore` 既有的錯誤說明
    private let existingKey = "error.lkai.invalidAPIKey"

    /// 驗證指定 `zh-Hant` 或 `en` 時，查到的字串等於直接從該語言的資料夾查到的字串
    ///
    /// - Parameter language: 語言資料夾的名稱，不含 `.lproj`
    @Test(arguments: ["zh-Hant", "en"])
    func string_指定存在的語言_等於該語言資料夾直接查到的字串(language: String) throws {
        // Given
        let bundlePath = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        let languageBundle = try #require(Bundle(path: bundlePath))
        let expectedText = languageBundle.localizedString(
            forKey: existingKey,
            value: nil,
            table: nil
        )

        // When
        let actualText = LKAILocalization.string(
            forKey: existingKey,
            in: Bundle.module,
            localization: language
        )

        // Then
        #expect(actualText == expectedText)
    }

    /// 驗證同一個 key 指定 `en` 與 `zh-Hant` 查到的字串彼此不同，
    /// 確認指定的語言真的決定了查到哪一種文字
    @Test
    func string_指定en與zhHant_查到的字串彼此不同() {
        // Given

        // When
        let englishText = LKAILocalization.string(
            forKey: existingKey,
            in: Bundle.module,
            localization: "en"
        )
        let traditionalChineseText = LKAILocalization.string(
            forKey: existingKey,
            in: Bundle.module,
            localization: "zh-Hant"
        )

        // Then
        #expect(englishText != traditionalChineseText)
    }

    /// 驗證指定的語言沒有對應的資料夾時，改用 bundle 預設的查詢，結果等於直接以 bundle 查到的字串
    ///
    /// - Note: 預設的查詢跟隨行程的語言設定，期望值與實際值走同一條路徑，所以不論行程是什麼語言都成立
    @Test
    func string_指定不存在的語言_改用bundle預設的查詢() {
        // Given
        let expectedText = Bundle.module.localizedString(
            forKey: existingKey,
            value: nil,
            table: nil
        )

        // When
        let actualText = LKAILocalization.string(
            forKey: existingKey,
            in: Bundle.module,
            localization: "fr"
        )

        // Then
        #expect(actualText == expectedText)
    }

    /// 驗證查不到的 key 回傳 key 本身，不論指定的語言有沒有對應的資料夾
    ///
    /// - Parameter localization: 語言資料夾的名稱：兩種支援的語言，以及沒有資料夾的 `fr`
    @Test(arguments: ["zh-Hant", "en", "fr"])
    func string_查不到的key_回傳key本身(localization: String) {
        // Given
        let missingKey = "no.such.key"

        // When
        let actualText = LKAILocalization.string(
            forKey: missingKey,
            in: Bundle.module,
            localization: localization
        )

        // Then
        #expect(actualText == missingKey)
    }
}
