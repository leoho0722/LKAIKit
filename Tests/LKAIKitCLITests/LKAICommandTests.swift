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

/// `LKAICommand` 的單元測試
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
        let output = try runLKAI(arguments: arguments)

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
        let output = try runLKAI(arguments: ["--version"])

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
        let output = try runLKAI(arguments: [argument])

        // Then
        let lines = output.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        #expect(firstLine == expectedFirstLine)
        #expect(output.standardOutput.isEmpty)
        #expect(output.terminationStatus == 64)
    }
}

// MARK: - Nested Types

extension LKAICommandTests {

    /// 只用來讓 `Bundle(for:)` 找出測試 bundle 的空型別，因為該 API 只接受 class
    private final class BundleLocator {

    }

    /// 一次 `lkai` 行程結束後留下的標準輸出、標準錯誤與退出碼
    struct CommandOutput {

        /// 行程寫到標準輸出的全部文字
        let standardOutput: String

        /// 行程寫到標準錯誤的全部文字
        let standardError: String

        /// 行程的退出碼
        let terminationStatus: Int32
    }
}

// MARK: - Private Method

private extension LKAICommandTests {

    /// 以 `Process` 執行建置出的 `lkai`，標準輸出與標準錯誤各接一條 `Pipe` 分開收集
    ///
    /// - Parameter arguments: 傳給 `lkai` 的命令列引數
    /// - Returns: 行程結束後讀到的標準輸出、標準錯誤與退出碼
    /// - Throws: 行程無法啟動或輸出讀取失敗時丟出
    /// - Note: 執行檔取自測試 bundle 所在的資料夾；找不到時讓測試失敗，不略過
    func runLKAI(arguments: [String]) throws -> CommandOutput {
        let testBundleURL = Bundle(for: BundleLocator.self).bundleURL
        let executableURL = testBundleURL.deletingLastPathComponent().appending(path: "lkai")
        try #require(
            FileManager.default.isExecutableFile(atPath: executableURL.path),
            "找不到 lkai 執行檔：\(executableURL.path)"
        )

        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        try process.run()
        process.waitUntilExit()

        // 輸出只有幾行，行程結束後再讀不會塞滿 Pipe；沒有內容時以空資料處理
        let standardOutputData = try standardOutputPipe.fileHandleForReading.readToEnd() ?? Data()
        let standardErrorData = try standardErrorPipe.fileHandleForReading.readToEnd() ?? Data()
        return CommandOutput(
            standardOutput: String(decoding: standardOutputData, as: UTF8.self),
            standardError: String(decoding: standardErrorData, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }
}
