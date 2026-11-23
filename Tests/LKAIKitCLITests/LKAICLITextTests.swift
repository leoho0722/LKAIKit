//
//  LKAICLITextTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Testing

@testable import LKAIKitCLI

/// `LKAICLIText` 的單元測試：每個字串在兩種輸出語言都查得到，帶參數的字串代入後含有該參數
struct LKAICLITextTests {

    // MARK: - Properties

    /// 字串內有 `%@`、需要代入參數的 case；新增帶 `%@` 的 case 時要加進來
    private static let parameterizedTexts: [LKAICLIText] = [
        .helpDiscussion,
        .errorUnsupportedPromptFile,
        .errorUnreadablePromptFile,
        .errorBlankPromptFile,
        .errorMissingAPIKey,
    ]

    // spectra-scenario: cli-output-language / Provide both translations for every CLI string
    /// 驗證每個 case 在 `en` 與 `zh-Hant` 都查到不為空、也不等於 key 本身的字串
    ///
    /// - Parameters:
    ///   - text: 要查的字串
    ///   - language: 輸出語言
    @Test(arguments: LKAICLIText.allCases, LKAIOutputLanguage.allCases)
    func string_每個case在兩種語言_不為空也不等於key(
        text: LKAICLIText,
        language: LKAIOutputLanguage
    ) {
        // Given

        // When
        let actualText = text.string(in: language)

        // Then
        #expect(!actualText.isEmpty)
        #expect(actualText != text.rawValue)
    }

    /// 驗證帶 `%@` 的字串代入參數後，內容含有該參數，而且 `%@` 已被取代
    ///
    /// - Parameters:
    ///   - text: 帶 `%@` 的字串
    ///   - language: 輸出語言
    @Test(arguments: LKAICLITextTests.parameterizedTexts, LKAIOutputLanguage.allCases)
    func string_帶參數的字串_代入參數後含有該參數(
        text: LKAICLIText,
        language: LKAIOutputLanguage
    ) {
        // Given
        let argument = "FIRST_ENV, SECOND_ENV"

        // When
        let actualText = text.string(in: language, argument)

        // Then
        #expect(actualText.contains(argument))
        #expect(!actualText.contains("%@"))
    }

    /// 驗證每個 case 在所有輸出語言查到的字串兩兩不同
    ///
    /// - Parameter text: 要查的字串
    /// - Note: 語言資料夾不見或改名時，查詢會靜默退回預設語言，期望值也跟著退回，原本「不為空、
    ///   不等於 key」的測試擋不下來；只有比較各語言的字串，才發現得了
    /// - Note: 比較的是 String Catalog 的實際值，不在測試裡寫死翻譯；帶 `%@` 的字串不代入參數，
    ///   直接比較樣板
    @Test(arguments: LKAICLIText.allCases)
    func string_每個case在各輸出語言_字串兩兩不同(text: LKAICLIText) {
        // Given
        let languages = LKAIOutputLanguage.allCases

        // When
        let actualTexts = languages.map { text.string(in: $0) }

        // Then
        #expect(Set(actualTexts).count == languages.count)
    }

    /// 驗證每個 case 在兩種語言的字串都不含 `LKAI_`：環境變數的名稱由程式從供應商清單組出來代入，
    /// 不寫在 String Catalog
    ///
    /// - Parameters:
    ///   - text: 要檢查的字串
    ///   - language: 輸出語言
    /// - Note: 先要求字串不為空，免得查到空字串時，下面的比對沒檢查任何內容就通過
    @Test(arguments: LKAICLIText.allCases, LKAIOutputLanguage.allCases)
    func string_每個case在兩種語言_不含LKAI_開頭的環境變數名稱(
        text: LKAICLIText,
        language: LKAIOutputLanguage
    ) throws {
        // Given

        // When
        let actualText = text.string(in: language)

        // Then
        try #require(!actualText.isEmpty, "查到空字串，沒有內容可以檢查")
        #expect(!actualText.contains("LKAI_"))
    }
}
