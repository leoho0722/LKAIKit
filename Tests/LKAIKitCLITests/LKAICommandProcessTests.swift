//
//  LKAICommandProcessTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `lkai` 行程的測試：以行程執行建置出的 `lkai`，檢查標準輸出、標準錯誤與退出碼
///
/// - Note: 行程的環境變數由 `LKAICommandTestSupport` 決定：沒有 `LKAI_*_API_KEY`，說明的寬度固定
struct LKAICommandProcessTests {

    // spectra-scenario: cli-root-command / Run the executable without arguments
    // spectra-scenario: cli-root-command / Request help with the long flag
    // spectra-scenario: cli-root-command / Request help with the short flag
    /// 驗證不帶參數、`--help`、`-h` 時，標準輸出有一行以 `USAGE: lkai `（含結尾空格）開頭並列出 `--version`，
    /// 標準錯誤為空，退出碼為 0
    ///
    /// - Parameter arguments: 傳給 `lkai` 的命令列引數，空陣列表示不帶參數
    @Test(arguments: [[], ["--help"], ["-h"]])
    func lkai_不帶參數或要求說明_說明只印到標準輸出且退出碼為0(arguments: [String]) throws {
        // Given

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: arguments)

        // Then
        let lines = output.standardOutput.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("USAGE: lkai ") })
        #expect(output.standardOutput.contains("--version"))
        #expect(output.standardError.isEmpty)
        #expect(output.terminationStatus == 0)
    }

    // spectra-scenario: cli-root-command / Request the version
    /// 驗證 `--version` 只在標準輸出印出 `LKAIKitInfo.version` 加一個換行，標準錯誤為空，退出碼為 0
    @Test
    func lkai_要求版本_版本只印到標準輸出且退出碼為0() throws {
        // Given
        let expectedOutput = "\(LKAIKitInfo.version)\n"

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: ["--version"])

        // Then
        #expect(output.standardOutput == expectedOutput)
        #expect(output.standardError.isEmpty)
        #expect(output.terminationStatus == 0)
    }

    // spectra-scenario: cli-root-command / Reject undefined input
    // spectra-scenario: cli-root-command / Reject undefined input / unknown option and unexpected argument
    /// 驗證未定義的選項或引數只在標準錯誤印出錯誤，第一行指出該輸入，標準輸出為空，退出碼為 64
    ///
    /// - Parameters:
    ///   - argument: 指令沒有定義的選項或引數
    ///   - expectedFirstLine: 標準錯誤的第一行，與 spec 範例的 stderr 第一行逐字相同
    @Test(
        arguments: zip(
            ["--bogus", "foo"],
            ["Error: Unknown option '--bogus'", "Error: Unexpected argument 'foo'"]
        )
    )
    func lkai_未定義的輸入_錯誤只印到標準錯誤且退出碼為64(argument: String, expectedFirstLine: String) throws {
        // Given

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: [argument])

        // Then
        let lines = output.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        #expect(firstLine == expectedFirstLine)
        #expect(output.standardOutput.isEmpty)
        #expect(output.terminationStatus == 64)
    }

    // spectra-scenario: cli-root-command / Request the version with the short flag
    /// 驗證 `-v` 只在標準輸出印出 `LKAIKitInfo.version` 加一個 LF，標準錯誤為空，退出碼為 0
    @Test
    func lkai_短旗標要求版本_版本只印到標準輸出且退出碼為0() throws {
        // Given
        let expectedOutput = "\(LKAIKitInfo.version)\n"

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: ["-v"])

        // Then
        #expect(output.standardOutput == expectedOutput)
        #expect(output.standardError.isEmpty)
        #expect(output.terminationStatus == 0)
    }

    // spectra-scenario: cli-root-command / Request the version together with chat options
    /// 驗證 `-v` 與對話選項一起給時，版本旗標優先：只印出版本號，不檢查對話選項，退出碼為 0
    @Test
    func lkai_版本旗標加對話選項_只印出版本且退出碼為0() throws {
        // Given
        let expectedOutput = "\(LKAIKitInfo.version)\n"

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: ["-v", "--provider", "openai", "-m", "gpt-6-luna", "-p", "hi"]
        )

        // Then
        #expect(output.standardOutput == expectedOutput)
        #expect(output.terminationStatus == 0)
    }

    // spectra-scenario: cli-output-language / Apply the language wherever the option appears
    // spectra-scenario: cli-output-language / Apply the language wherever the option appears / option positions
    /// 驗證 `--output-language zh-TW` 不論出現在哪個位置、寫成哪一種形式，說明的簡介都是 `zh-Hant`，退出碼為 0
    ///
    /// - Parameter arguments: 傳給 `lkai` 的命令列引數，對應範例表的五列
    /// - Note: 期望的簡介以 `LKAICLIText` 查出，說明以固定的寬度產生，簡介不會折行
    @Test(arguments: [
        ["--output-language", "zh-TW", "-h"],
        ["-h", "--output-language", "zh-TW"],
        ["--output-language=zh-TW", "--help"],
        ["--output-language", "en-US", "--output-language", "zh-TW", "-h"],
        ["--output-language", "zh-TW"],
    ])
    func lkai_輸出語言選項在各種位置_說明的簡介是正體中文且退出碼為0(arguments: [String]) throws {
        // Given
        let expectedAbstract = LKAICLIText.helpAbstract.string(in: .zhTW)

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: arguments)

        // Then
        #expect(output.standardOutput.contains(expectedAbstract))
        #expect(output.terminationStatus == 0)
    }

    // spectra-scenario: cli-output-language / Reject an unsupported language
    // spectra-scenario: cli-output-language / Reject an unsupported language / unsupported values
    /// 驗證 `--output-language` 的值不支援時，標準錯誤第一行以 `Error: ` 開頭並含該值，
    /// 有一行以 `Help:` 開頭並含 `en` 的 `--output-language` 說明，標準輸出為空，退出碼為 64
    ///
    /// - Parameter arguments: 傳給 `lkai` 的命令列引數，對應範例表的兩列
    /// - Note: 期望的說明以 `LKAICLIText` 查出；`Help:` 那一行重複的是 `en` 的說明，即使前面還有合法的值
    @Test(arguments: [
        ["--output-language", "ja-JP", "--provider", "openai"],
        ["--output-language", "ja-JP", "--output-language", "zh-TW", "--provider", "openai"],
    ])
    func lkai_不支援的輸出語言_錯誤與選項說明都是英文且退出碼為64(arguments: [String]) throws {
        // Given
        let expectedHelp = LKAICLIText.helpOutputLanguage.string(in: .enUS)

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: arguments)

        // Then
        let lines = output.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        let helpLine = lines.first { $0.hasPrefix("Help:") }
        #expect(firstLine.hasPrefix("Error: "))
        #expect(firstLine.contains("ja-JP"))
        #expect(helpLine?.contains(expectedHelp) == true)
        #expect(output.standardOutput.isEmpty)
        #expect(output.terminationStatus == 64)
    }

    // spectra-scenario: cli-output-language / Keep the help headings in English
    /// 驗證輸出語言是 `zh-TW` 時，說明的標題仍是英文：有一行以 `USAGE: lkai ` 開頭，有一行剛好是 `OPTIONS:`，
    /// 而簡介是 `zh-Hant`
    @Test
    func lkai_輸出語言為zhTW的說明_標題維持英文且簡介是正體中文() throws {
        // Given
        let expectedAbstract = LKAICLIText.helpAbstract.string(in: .zhTW)

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: ["--output-language", "zh-TW", "-h"]
        )

        // Then
        let lines = output.standardOutput.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("USAGE: lkai ") })
        #expect(lines.contains("OPTIONS:"))
        #expect(output.standardOutput.contains(expectedAbstract))
    }

    // spectra-scenario: cli-output-language / Keep a parse error in English
    /// 驗證輸出語言是 `zh-TW` 時，解析錯誤仍是英文：標準錯誤第一行剛好是 `Error: Unknown option '--bogus'`，
    /// 標準輸出為空，退出碼為 64
    ///
    /// - Note: 這是回歸防護：骨架已經接受 `--output-language`，所以實作前就會通過；
    ///   往後若有人把解析器的錯誤也翻譯，這個測試會失敗
    @Test
    func lkai_輸出語言為zhTW的解析錯誤_訊息維持英文且退出碼為64() throws {
        // Given

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: ["--output-language", "zh-TW", "--bogus"]
        )

        // Then
        let lines = output.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        #expect(firstLine == "Error: Unknown option '--bogus'")
        #expect(output.standardOutput.isEmpty)
        #expect(output.terminationStatus == 64)
    }

    // spectra-scenario: cli-output-language / Use English by default even on a Chinese system
    /// 驗證沒有給 `--output-language` 時，說明的簡介是 `en`，不受系統偏好語言影響
    ///
    /// - Note: 只有系統偏好語言以 `zh-Hant` 開頭時，才驗得到「中文系統仍用英文」這個前提；
    ///   前提是否成立記在斷言的說明裡，前提不成立時測試照樣執行，不失敗也不略過
    /// - Note: 這不是實作前會失敗的測試：骨架的簡介本來就是英文，往後若說明改成跟隨系統語言才會失敗
    @Test
    func lkai_沒有給輸出語言_說明的簡介是英文且不受系統語言影響() throws {
        // Given
        let expectedAbstract = LKAICLIText.helpAbstract.string(in: .enUS)
        let preferredLanguages = Locale.preferredLanguages
        let isChineseSystem = preferredLanguages.first?.hasPrefix("zh-Hant") == true
        let comment: Comment = "系統偏好語言：\(preferredLanguages)；以 zh-Hant 開頭（前提成立）：\(isChineseSystem)"

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: ["-h"])

        // Then
        #expect(output.standardOutput.contains(expectedAbstract), comment)
    }
}
