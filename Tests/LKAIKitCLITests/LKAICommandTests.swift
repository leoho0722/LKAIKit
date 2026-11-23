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

    // spectra-scenario: cli-chat / Map the provider to its client
    /// 驗證 `--provider` 的三種值，交給 `makeClient` 的輸入的供應商與金鑰都正確
    ///
    /// - Parameters:
    ///   - providerValue: `--provider` 的值
    ///   - expectedProvider: 預期的供應商
    /// - Note: 範例表的 client 型別與 `description` 由 `LKAIChatProviderTests` 驗證，這裡確認選項接到正確的供應商
    @Test(arguments: [
        ("anthropic", .anthropic),
        ("openai", .openai),
        ("google", .google),
    ] as [(String, LKAIChatProvider)])
    func execute_指定供應商_交給makeClient的輸入有對應的供應商與金鑰(
        providerValue: String,
        expectedProvider: LKAIChatProvider
    ) async throws {
        // Given
        let arguments = ["--provider", providerValue, "-m", "x", "-p", "hi", "--apiKey", "sk-test"]

        // When
        let inputs = try await executeCommand(arguments, client: makeSucceedingClient())

        // Then
        let input = try #require(inputs.first)
        #expect(inputs.count == 1)
        #expect(input.provider == expectedProvider)
        #expect(input.apiKey.unredactedValue == "sk-test")
    }

    // spectra-scenario: cli-chat / Configure the timeout
    // spectra-scenario: cli-chat / Configure the timeout / timeout values
    /// 驗證沒給 `--timeout` 時請求逾時是 60 秒，給了就是該秒數
    ///
    /// - Parameters:
    ///   - timeoutArguments: 要加在基本引數後面的 `--timeout` 引數；沒給時為空陣列
    ///   - expectedInterval: 預期的請求逾時，單位為秒，對應範例表的三列
    /// - Note: 逾時以交給 `makeClient` 的輸入所產生的 session 設定確認，不連網
    @Test(arguments: [
        ([], 60),
        (["--timeout", "300"], 300),
        (["--timeout", "1"], 1),
    ] as [([String], TimeInterval)])
    func execute_逾時選項_session設定的請求逾時等於範例表的值(
        timeoutArguments: [String],
        expectedInterval: TimeInterval
    ) async throws {
        // Given
        let arguments = ["--provider", "openai", "-m", "x", "-p", "hi", "--apiKey", "sk-test"]
            + timeoutArguments

        // When
        let inputs = try await executeCommand(arguments, client: makeSucceedingClient())

        // Then
        let input = try #require(inputs.first)
        #expect(input.makeSessionConfiguration().timeoutIntervalForRequest == expectedInterval)
    }

    // spectra-scenario: cli-chat / Pass a prompt that begins with a dash
    // spectra-scenario: cli-chat / Pass a prompt that begins with a dash / dash-prefixed prompt text
    /// 驗證以 `-` 開頭的提示詞，在解析器接受的寫法下原樣成為請求的訊息文字
    ///
    /// - Parameters:
    ///   - promptArguments: 提示詞的引數：`-p -`、`--prompt=- item`、`--prompt=--- a/file`
    ///   - expectedText: 預期的訊息文字
    /// - Note: 範例表中被解析器拒絕的兩列，由 `LKAICommandProcessTests` 以行程驗證
    @Test(arguments: [
        (["-p", "-"], "-"),
        (["--prompt=- item"], "- item"),
        (["--prompt=--- a/file"], "--- a/file"),
    ] as [([String], String)])
    func execute_以破折號開頭的提示詞_原樣成為訊息文字(
        promptArguments: [String],
        expectedText: String
    ) async throws {
        // Given
        let arguments = ["--provider", "openai", "-m", "x", "--apiKey", "sk-test"] + promptArguments
        let client = makeSucceedingClient()

        // When
        try await executeCommand(arguments, client: client)

        // Then
        let request = try #require(client.invokeReceivedRequests.first)
        #expect(request.messages == [LKAIMessage(role: .user, text: expectedText)])
    }

    // spectra-scenario: cli-output-language / Send the same request in both languages
    /// 驗證輸出語言是 `en-US` 或 `zh-TW`，送給 client 的請求都相同，而且都沒有系統指示
    @Test
    func execute_輸出語言不同_送出的請求相同且沒有系統指示() async throws {
        // Given
        let baseArguments = [
            "--provider", "anthropic", "-m", "claude-opus-5-5", "-p", "hi", "--apiKey", "sk-test",
        ]
        let englishClient = makeSucceedingClient()
        let chineseClient = makeSucceedingClient()

        // When
        let englishArguments = baseArguments + ["--output-language", "en-US"]
        let chineseArguments = baseArguments + ["--output-language", "zh-TW"]
        try await executeCommand(englishArguments, client: englishClient)
        try await executeCommand(chineseArguments, client: chineseClient)

        // Then
        let englishRequest = try #require(englishClient.invokeReceivedRequests.first)
        let chineseRequest = try #require(chineseClient.invokeReceivedRequests.first)
        #expect(englishRequest == chineseRequest)
        #expect(englishRequest.systemPrompt == nil)
    }

    /// 驗證結果對應成退出碼：回答完成時 `execute` 不丟出，被截斷時丟出 `ExitCode(2)`，
    /// 對話失敗時丟出 `ExitCode.failure`（1）
    ///
    /// - Parameter testCase: 一列範例：client 的 `invoke(_:)` 結果，以及預期的退出碼
    /// - Note: 預期的退出碼 0 表示沒有丟出任何錯誤；丟出不是 `ExitCode` 的錯誤時，實際值是 -1
    @Test(arguments: [
        ExitCodeCase(
            invokeResult: .success(
                LKAIChatResponse(
                    text: "OK",
                    completion: LKAIChatCompletion(
                        finishReason: .completed,
                        usage: nil,
                        respondingModel: nil
                    )
                )
            ),
            expectedCode: 0
        ),
        ExitCodeCase(
            invokeResult: .success(
                LKAIChatResponse(
                    text: "Partial",
                    completion: LKAIChatCompletion(
                        finishReason: .maxOutputTokens,
                        usage: nil,
                        respondingModel: nil
                    )
                )
            ),
            expectedCode: 2
        ),
        ExitCodeCase(invokeResult: .failure(.invalidAPIKey), expectedCode: 1),
    ])
    func execute_對話結果_對應成退出碼(testCase: ExitCodeCase) async {
        // Given
        let arguments = ["--provider", "openai", "-m", "x", "-p", "hi", "--apiKey", "sk-test"]
        let client = MockChatClient(invokeResult: testCase.invokeResult)
        var actualError: (any Error)?

        // When
        do {
            try await executeCommand(arguments, client: client)
        } catch {
            actualError = error
        }

        // Then
        let actualCode = actualError.map { ($0 as? ExitCode)?.rawValue ?? -1 } ?? 0
        #expect(actualCode == testCase.expectedCode)
    }

    /// 驗證加 `--stream` 時只呼叫 client 的 `stream(_:)`，沒加時只呼叫 `invoke(_:)`
    ///
    /// - Parameters:
    ///   - extraArguments: 要加在基本引數後面的引數：`--stream` 或沒有
    ///   - expectedStreamCalls: 預期 `stream(_:)` 被呼叫的次數
    ///   - expectedInvokeCalls: 預期 `invoke(_:)` 被呼叫的次數
    @Test(arguments: [
        (["--stream"], 1, 0),
        ([], 0, 1),
    ] as [([String], Int, Int)])
    func execute_是否加stream_只呼叫對應的方法(
        extraArguments: [String],
        expectedStreamCalls: Int,
        expectedInvokeCalls: Int
    ) async throws {
        // Given
        let arguments = ["--provider", "openai", "-m", "x", "-p", "hi", "--apiKey", "sk-test"]
            + extraArguments
        let client = makeSucceedingClient()

        // When
        try await executeCommand(arguments, client: client)

        // Then
        #expect(client.streamReceivedRequests.count == expectedStreamCalls)
        #expect(client.invokeReceivedRequests.count == expectedInvokeCalls)
    }

    // spectra-scenario: cli-chat / Only a non-chat option is given
    /// 驗證四個對話選項都沒給時，不論其他選項有沒有給，`execute` 都丟出說明請求，退出碼為成功，
    /// 而且沒有建立 client
    ///
    /// - Parameter arguments: 命令列引數，不含 `--provider`、`-m`、`-p`、`-f`
    /// - Note: 這是回歸防護：骨架對任何輸入都丟出說明請求，所以實作前就會通過；
    ///   實作後要確認四個選項都沒給時仍是這個行為
    @Test(arguments: [
        [],
        ["--stream"],
        ["--timeout", "5"],
        ["--apiKey", "sk-test"],
        ["--max-output-tokens", "10"],
        ["--output-language", "zh-TW"],
    ])
    func execute_四個對話選項都沒給_丟出說明請求且不建立client(arguments: [String]) async throws {
        // Given
        let command = try makeCommand(arguments)
        var didMakeClient = false
        var actualError: (any Error)?

        // When
        do {
            try await command.execute(
                environment: [:],
                makeClient: { _ in
                    didMakeClient = true
                    return MockChatClient()
                },
                output: ChatRunRecorder().output
            )
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(LKAICommand.fullMessage(for: error).contains("USAGE: lkai"))
        #expect(LKAICommand.exitCode(for: error) == ExitCode.success)
        #expect(!didMakeClient)
    }
}

// MARK: - Nested Types

extension LKAICommandTests {

    /// 退出碼對應的一列範例：client 的 `invoke(_:)` 結果，以及預期的退出碼
    struct ExitCodeCase: Sendable {

        /// client 的 `invoke(_:)` 要回傳的結果
        let invokeResult: Result<LKAIChatResponse, LKAIError>

        /// 預期的退出碼；0 表示沒有丟出錯誤
        let expectedCode: Int32
    }
}

// MARK: - Private Method

private extension LKAICommandTests {

    /// 解析命令列引數，轉成 `LKAICommand`
    ///
    /// - Parameter arguments: 命令列引數
    /// - Returns: 解析出的指令
    /// - Throws: 解析失敗時丟出解析器的錯誤；解析出的不是 `LKAICommand` 時讓測試失敗
    func makeCommand(_ arguments: [String]) throws -> LKAICommand {
        let parsedCommand = try LKAICommand.parseAsRoot(arguments)
        return try #require(parsedCommand as? LKAICommand)
    }

    /// 組出 `invoke(_:)` 與 `stream(_:)` 都成功完成的替身 client
    ///
    /// - Returns: 兩種方式都回答 `OK`、結束原因為 `completed` 的替身 client
    func makeSucceedingClient() -> MockChatClient {
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: nil
        )
        return MockChatClient(
            invokeResult: .success(LKAIChatResponse(text: "OK", completion: completion)),
            streamEvents: [.textDelta("OK"), .finished(completion)]
        )
    }

    /// 解析引數後呼叫 `execute`，由替身 client 回答，輸出寫進記錄器，並記下 `makeClient` 收到的輸入
    ///
    /// - Parameters:
    ///   - arguments: 命令列引數
    ///   - client: 替身 client
    ///   - environment: 傳給 `execute` 的環境變數，預設是空的
    /// - Returns: `makeClient` 依序收到的輸入
    /// - Throws: 解析失敗，或 `execute` 丟出錯誤時原樣丟出
    @discardableResult
    func executeCommand(
        _ arguments: [String],
        client: MockChatClient,
        environment: [String: String] = [:]
    ) async throws -> [LKAIChatInput] {
        let command = try makeCommand(arguments)
        var receivedInputs: [LKAIChatInput] = []
        try await command.execute(
            environment: environment,
            makeClient: { input in
                receivedInputs.append(input)
                return client
            },
            output: ChatRunRecorder().output
        )
        return receivedInputs
    }
}
