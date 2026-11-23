//
//  LKAICommandProcessTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

/// `lkai` 行程的測試：以行程執行建置出的 `lkai`，檢查標準輸出、標準錯誤與退出碼
///
/// - Note: 行程的環境變數由 `LKAICommandTestSupport` 決定：沒有 `LKAI_*_API_KEY`，說明的寬度固定
struct LKAICommandProcessTests {

    // spectra-scenario: cli-root-command / Run the executable without arguments
    // spectra-scenario: cli-root-command / Request help with the long flag
    // spectra-scenario: cli-root-command / Request help with the short flag
    /// 驗證不帶參數、`--help`、`-h` 時，標準輸出有一行剛好是 `USAGE: lkai` 並列出 `--version`，標準錯誤為空，退出碼為 0
    ///
    /// - Parameter arguments: 傳給 `lkai` 的命令列引數，空陣列表示不帶參數
    @Test(arguments: [[], ["--help"], ["-h"]])
    func lkai_不帶參數或要求說明_說明只印到標準輸出且退出碼為0(arguments: [String]) throws {
        // Given

        // When
        let output = try LKAICommandTestSupport.runLKAI(arguments: arguments)

        // Then
        #expect(output.standardOutput.split(separator: "\n").contains("USAGE: lkai"))
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
}
