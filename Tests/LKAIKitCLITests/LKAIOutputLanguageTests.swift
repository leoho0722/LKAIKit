//
//  LKAIOutputLanguageTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Testing

@testable import LKAIKitCLI

/// `LKAIOutputLanguage` 的單元測試：從命令列掃描輸出語言，以及語言對應的 String Catalog 語言資料夾
struct LKAIOutputLanguageTests {

    // spectra-scenario: cli-output-language / Apply the language wherever the option appears
    // spectra-scenario: cli-output-language / Apply the language wherever the option appears / option positions
    /// 驗證合法的 `--output-language` 不論出現在哪個位置、寫成哪一種形式，都掃描出該語言；
    /// 出現多次時取最後一次，`--` 之後的選項不算
    ///
    /// - Parameter testCase: 一列範例：命令列引數與預期掃描出的語言
    /// - Note: 前五列是 spec 範例表「option positions」的寫法，其餘是範例表之外多加的列
    /// - Note: 多加的列涵蓋指定 `en-US`、最後一次出現的值是 `en-US`、夾在其他選項之間，
    ///   以及 `--` 之後的選項不算
    @Test(arguments: [
        ScanCase(arguments: ["--output-language", "zh-TW", "-h"], expectedLanguage: .zhTW),
        ScanCase(arguments: ["-h", "--output-language", "zh-TW"], expectedLanguage: .zhTW),
        ScanCase(arguments: ["--output-language=zh-TW", "--help"], expectedLanguage: .zhTW),
        ScanCase(
            arguments: ["--output-language", "en-US", "--output-language", "zh-TW", "-h"],
            expectedLanguage: .zhTW
        ),
        ScanCase(arguments: ["--output-language", "zh-TW"], expectedLanguage: .zhTW),
        ScanCase(arguments: ["--output-language", "en-US"], expectedLanguage: .enUS),
        ScanCase(arguments: ["--output-language=en-US"], expectedLanguage: .enUS),
        ScanCase(
            arguments: ["--output-language", "zh-TW", "--output-language", "en-US"],
            expectedLanguage: .enUS
        ),
        ScanCase(
            arguments: ["--output-language=zh-TW", "--output-language", "en-US"],
            expectedLanguage: .enUS
        ),
        ScanCase(
            arguments: ["--provider", "openai", "--output-language", "zh-TW", "-m", "x"],
            expectedLanguage: .zhTW
        ),
        ScanCase(
            arguments: ["--output-language", "zh-TW", "--", "--output-language", "en-US"],
            expectedLanguage: .zhTW
        ),
    ])
    func scanned_合法的選項_掃描出最後一次出現的語言(testCase: ScanCase) {
        // Given

        // When
        let actualLanguage = LKAIOutputLanguage.scanned(from: testCase.arguments)

        // Then
        #expect(actualLanguage == testCase.expectedLanguage)
    }

    // spectra-scenario: cli-output-language / Reject an unsupported language
    // spectra-scenario: cli-output-language / Reject an unsupported language / unsupported values
    /// 驗證沒有給選項、任何一次出現的值不合法、選項沒有值，或選項在 `--` 之後時，都掃描成 `.enUS`
    ///
    /// - Parameter arguments: 命令列引數
    /// - Note: 第三、四列是 spec 範例表「unsupported values」的寫法，其餘是範例表之外多加的列
    /// - Note: 多加的列涵蓋沒有給選項、前面合法而最後不合法、前面合法而最後一個引數沒有值、
    ///   `zh-tw` 與 `ja-JP` 的大小寫與不支援的值、值是空字串、後面接的是別的選項，以及 `--` 之後的選項不算
    @Test(arguments: [
        [],
        ["--provider", "openai"],
        ["--output-language", "ja-JP", "--provider", "openai"],
        ["--output-language", "ja-JP", "--output-language", "zh-TW", "--provider", "openai"],
        ["--output-language", "zh-TW", "--output-language", "ja-JP"],
        ["--output-language"],
        ["--output-language", "zh-TW", "--output-language"],
        ["--output-language", "zh-tw"],
        ["--output-language=zh-tw"],
        ["--output-language="],
        ["--output-language", "--provider", "openai"],
        ["--", "--output-language", "zh-TW"],
    ])
    func scanned_沒有選項或選項不合法_掃描出英文(arguments: [String]) {
        // Given

        // When
        let actualLanguage = LKAIOutputLanguage.scanned(from: arguments)

        // Then
        #expect(actualLanguage == .enUS)
    }

    /// 驗證每種輸出語言對應的語言資料夾名稱：`en-US` 對應 `en`，`zh-TW` 對應 `zh-Hant`
    ///
    /// - Parameters:
    ///   - language: 輸出語言
    ///   - expectedLocalization: 預期的語言資料夾名稱，不含 `.lproj`
    @Test(arguments: [
        (.enUS, "en"),
        (.zhTW, "zh-Hant"),
    ] as [(LKAIOutputLanguage, String)])
    func localization_各輸出語言_對應語言資料夾的名稱(
        language: LKAIOutputLanguage,
        expectedLocalization: String
    ) {
        // Given

        // When
        let actualLocalization = language.localization

        // Then
        #expect(actualLocalization == expectedLocalization)
    }
}

// MARK: - Nested Types

extension LKAIOutputLanguageTests {

    /// 掃描命令列的一列範例：命令列引數，以及預期掃描出的語言
    struct ScanCase: Sendable {

        /// 命令列引數，不含執行檔的名稱
        let arguments: [String]

        /// 預期掃描出的語言
        let expectedLanguage: LKAIOutputLanguage
    }
}
