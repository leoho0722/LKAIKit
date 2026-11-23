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
    /// 驗證不帶參數解析出的指令執行 `run()` 時，丟出說明請求，訊息有一行剛好是 `USAGE: lkai`，退出碼為成功
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
        #expect(message.split(separator: "\n").contains("USAGE: lkai"))
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
    }

    // spectra-scenario: cli-root-command / Request help with the long flag
    // spectra-scenario: cli-root-command / Request help with the short flag
    /// 驗證 `--help` 與 `-h` 解析後執行指令，得到有一行剛好是 `USAGE: lkai` 且列出 `--version` 的說明，退出碼為成功
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
        #expect(message.split(separator: "\n").contains("USAGE: lkai"))
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
}
