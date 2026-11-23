//
//  LKAICommandTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/21.
//

import ArgumentParser
import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAICommand` 的單元測試：在同一個行程內直接呼叫 `parseAsRoot` 與 `run`
///
/// - Note: 以行程執行 `lkai` 的測試在 `LKAICommandProcessTests`
struct LKAICommandTests {

    // spectra-scenario: cli-root-command / Run the executable without arguments
    /// 驗證不帶參數解析出的指令執行 `run()` 時，丟出說明請求，訊息有一行以 `USAGE: lkai `（含結尾空格）開頭，
    /// 退出碼為成功
    @Test
    func run_不帶參數_拋出說明請求且退出碼為成功() async throws {
        // Given
        let parsedCommand = try LKAICommand.parseAsRoot([])
        var command = try #require(parsedCommand as? any AsyncParsableCommand)
        var actualError: (any Error)?

        // When
        do {
            try await command.run()
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let message = LKAICommand.fullMessage(for: error)
        #expect(message.split(separator: "\n").contains { $0.hasPrefix("USAGE: lkai ") })
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
    }

    // spectra-scenario: cli-root-command / Request help with the long flag
    // spectra-scenario: cli-root-command / Request help with the short flag
    /// 驗證 `--help` 與 `-h` 解析後執行指令，得到有一行以 `USAGE: lkai `（含結尾空格）開頭且列出 `--version` 的說明，
    /// 退出碼為成功
    ///
    /// - Parameter argument: 要求說明的命令列旗標
    @Test(arguments: ["--help", "-h"])
    func parseAsRoot_要求說明_訊息列出用法與version選項且退出碼為成功(argument: String) throws {
        // Given
        var command = try LKAICommand.parseAsRoot([argument])
        var actualError: (any Error)?

        // When
        do {
            try command.run()
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let message = LKAICommand.fullMessage(for: error)
        #expect(message.split(separator: "\n").contains { $0.hasPrefix("USAGE: lkai ") })
        #expect(message.contains("--version"))
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
    }

    // spectra-scenario: cli-root-command / Request the version
    /// 驗證 `--version` 得到的訊息就是 `LKAIKitInfo.version` 本身、沒有多餘文字，且以成功的退出碼結束
    @Test
    func parseAsRoot_要求版本_訊息等於套件版本且退出碼為成功() throws {
        // Given
        let expectedVersion = LKAIKitInfo.version
        var actualError: (any Error)?

        // When
        do {
            _ = try LKAICommand.parseAsRoot(["--version"])
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(LKAICommand.fullMessage(for: error) == expectedVersion)
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
    }

    // spectra-scenario: cli-root-command / Reject undefined input
    // spectra-scenario: cli-root-command / Reject undefined input / unknown option and unexpected argument
    /// 驗證未定義的選項或引數會被拒絕，錯誤訊息的第一行指出是哪一個輸入，且以驗證失敗的退出碼結束
    ///
    /// - Parameters:
    ///   - argument: 指令沒有定義的選項或引數
    ///   - expectedFirstLine: 錯誤訊息的第一行，與 spec 範例的 stderr 第一行逐字相同
    @Test(
        arguments: zip(
            ["--bogus", "foo"],
            ["Error: Unknown option '--bogus'", "Error: Unexpected argument 'foo'"]
        )
    )
    func parseAsRoot_未定義的輸入_訊息指出該輸入且退出碼為驗證失敗(argument: String, expectedFirstLine: String) throws {
        // Given
        var actualError: (any Error)?

        // When
        do {
            _ = try LKAICommand.parseAsRoot([argument])
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let message = LKAICommand.fullMessage(for: error)
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        #expect(firstLine == expectedFirstLine)
        #expect(LKAICommand.exitCode(for: error) == ExitCode.validationFailure)
    }

    // spectra-scenario: cli-root-command / Request the version with the short flag
    /// 驗證 `-v` 得到的訊息就是 `LKAIKitInfo.version` 本身、沒有多餘文字，且以成功的退出碼結束
    @Test
    func parseAsRoot_短旗標要求版本_訊息等於套件版本且退出碼為成功() throws {
        // Given
        let expectedVersion = LKAIKitInfo.version
        var actualError: (any Error)?

        // When
        do {
            _ = try LKAICommand.parseAsRoot(["-v"])
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(LKAICommand.fullMessage(for: error) == expectedVersion)
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
    }

    // spectra-scenario: cli-output-language / Translated command text
    /// 驗證輸出語言是 `zh-TW` 時，說明的簡介與 `--provider` 的說明都是 `zh-Hant` 的翻譯
    ///
    /// - Note: 以 `LKAIOutputLanguage.$current` 綁定語言，說明以固定的寬度產生，期望值以 `LKAICLIText` 查出
    @Test
    func helpMessage_輸出語言為zhTW_簡介與provider說明是正體中文() {
        // Given
        let expectedAbstract = LKAICLIText.helpAbstract.string(in: .zhTW)
        let expectedProviderHelp = LKAICLIText.helpProvider.string(in: .zhTW)

        // When
        let message = LKAIOutputLanguage.$current.withValue(.zhTW) {
            LKAICommand.helpMessage(columns: LKAICommandTestSupport.helpColumns)
        }

        // Then
        #expect(message.contains(expectedAbstract))
        #expect(message.contains(expectedProviderHelp))
    }

    // spectra-scenario: cli-chat / List every environment variable in the help
    /// 驗證兩種輸出語言的說明，都含每個供應商讀取金鑰的環境變數名稱
    ///
    /// - Parameter language: 輸出語言
    @Test(arguments: LKAIOutputLanguage.allCases)
    func helpMessage_各輸出語言_列出每個供應商的環境變數(language: LKAIOutputLanguage) {
        // Given

        // When
        let message = LKAIOutputLanguage.$current.withValue(language) {
            LKAICommand.helpMessage(columns: LKAICommandTestSupport.helpColumns)
        }

        // Then
        for provider in LKAIChatProvider.allCases {
            #expect(message.contains(provider.apiKeyEnvironmentName))
        }
    }

    // spectra-scenario: cli-chat / Name the alternatives in the prompt help
    // spectra-scenario: cli-chat / Name the alternatives in the prompt help / help languages
    /// 驗證兩種輸出語言的說明，都含 `--prompt` 的說明，而且那則說明寫明 `--prompt=` 與 `--prompt-file`
    ///
    /// - Parameter language: 輸出語言，對應範例表的兩列
    /// - Note: 說明字串以 `LKAICLIText` 查出，另外確認它本身含兩個替代寫法，再確認整份說明含有它
    @Test(arguments: LKAIOutputLanguage.allCases)
    func helpMessage_各輸出語言_prompt說明寫明以破折號開頭時的替代寫法(language: LKAIOutputLanguage) {
        // Given
        let promptHelp = LKAICLIText.helpPrompt.string(in: language)

        // When
        let message = LKAIOutputLanguage.$current.withValue(language) {
            LKAICommand.helpMessage(columns: LKAICommandTestSupport.helpColumns)
        }

        // Then
        #expect(promptHelp.contains("--prompt="))
        #expect(promptHelp.contains("--prompt-file"))
        #expect(message.contains(promptHelp))
    }

    /// 驗證每一組能解析成功、而且不含 `-h` 與 `-v` 的引數，掃描出的輸出語言都等於解析出的 `--output-language`
    ///
    /// - Parameter arguments: 命令列引數
    /// - Note: 這是回歸防護：掃描在 `LKAIOutputLanguage` 已經完成，這個測試確認它和解析器的結果一致，
    ///   往後修改選項的寫法或 parsing 策略時，兩邊不同步就會失敗
    @Test(arguments: [
        [],
        ["--output-language", "zh-TW"],
        ["--output-language=zh-TW", "--stream"],
        ["--output-language", "en-US", "--output-language", "zh-TW"],
        ["--provider", "openai", "--output-language", "zh-TW", "-p", "x"],
    ])
    func scanned_可解析的引數_與解析出的輸出語言相同(arguments: [String]) throws {
        // Given
        let parsedCommand = try LKAICommand.parseAsRoot(arguments)
        let command = try #require(parsedCommand as? LKAICommand)

        // When
        let scannedLanguage = LKAIOutputLanguage.scanned(from: arguments)

        // Then
        #expect(scannedLanguage == command.outputLanguage)
    }
}
