//
//  LKAICommandLiveTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import Testing

@testable import LKAIKitCLI

/// `lkai` 對三家真實 API 的測試：以行程執行 `lkai`，確認三家各以兩種輸出方式都能得到完整的回答
///
/// - Note: 只在設定對應的環境變數時執行，沒有設定時顯示為略過：`LKAI_ANTHROPIC_API_KEY`、
///   `LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`；三家各一個測試函式，每個函式有兩個案例
///   （沒有 `--stream`、有 `--stream`），所以沒有設定任何環境變數時共略過六個案例
/// - Note: 會連線到真實的 API 並產生少量費用，由 owner 以自己的金鑰手動執行
/// - Note: 金鑰只從環境變數讀取，也只以環境變數傳給 `lkai`，不放進命令列引數、斷言訊息與任何輸出；
///   判斷標準輸出與標準錯誤有沒有含金鑰時，先算成布林值，失敗時才不會把內容連同金鑰一起印出來
/// - Note: 不給 `--max-output-tokens` 與 `--timeout`，以預設值執行，同時確認預設的輸出上限三家都接受
/// - Note: 模型與 library 的實際 API 測試相同
struct LKAICommandLiveTests {

    // MARK: - Properties

    /// 兩個輸出方式：不加 `--stream`（`invoke`）與加 `--stream`
    private static let outputModes: [LKAIChatRunner.OutputMode] = [.invoke, .stream]

    /// 驗證 Anthropic：以預設設定要求只回一個詞，兩種輸出方式都完整回答且退出碼為 0
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    @Test(
        .enabled(if: LKAICommandLiveTests.isAPIKeyConfigured(named: "LKAI_ANTHROPIC_API_KEY")),
        .timeLimit(.minutes(2)),
        arguments: LKAICommandLiveTests.outputModes
    )
    func lkai_anthropic要求只回一個詞_輸出完整回答且退出碼為0(
        mode: LKAIChatRunner.OutputMode
    ) throws {
        // Given
        let environmentName = "LKAI_ANTHROPIC_API_KEY"
        let apiKey = try #require(ProcessInfo.processInfo.environment[environmentName])
        let environment = makeEnvironment(adding: apiKey, named: environmentName)
        let arguments = makeArguments(provider: "anthropic", model: "claude-opus-5-5", mode: mode)

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: arguments,
            environment: environment
        )

        // Then
        let checks = makeChecks(of: output, apiKey: apiKey)
        #expect(checks.exitedWithZero, checks.diagnostics)
        #expect(checks.hasEmptyStandardError, checks.diagnostics)
        #expect(checks.hasAnswer, checks.diagnostics)
        #expect(checks.endsWithLineFeed, checks.diagnostics)
        #expect(!checks.leaksAPIKey, checks.diagnostics)
    }

    /// 驗證 OpenAI：以預設設定要求只回一個詞，兩種輸出方式都完整回答且退出碼為 0
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    @Test(
        .enabled(if: LKAICommandLiveTests.isAPIKeyConfigured(named: "LKAI_OPENAI_API_KEY")),
        .timeLimit(.minutes(2)),
        arguments: LKAICommandLiveTests.outputModes
    )
    func lkai_openai要求只回一個詞_輸出完整回答且退出碼為0(
        mode: LKAIChatRunner.OutputMode
    ) throws {
        // Given
        let environmentName = "LKAI_OPENAI_API_KEY"
        let apiKey = try #require(ProcessInfo.processInfo.environment[environmentName])
        let environment = makeEnvironment(adding: apiKey, named: environmentName)
        let arguments = makeArguments(provider: "openai", model: "gpt-6-luna", mode: mode)

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: arguments,
            environment: environment
        )

        // Then
        let checks = makeChecks(of: output, apiKey: apiKey)
        #expect(checks.exitedWithZero, checks.diagnostics)
        #expect(checks.hasEmptyStandardError, checks.diagnostics)
        #expect(checks.hasAnswer, checks.diagnostics)
        #expect(checks.endsWithLineFeed, checks.diagnostics)
        #expect(!checks.leaksAPIKey, checks.diagnostics)
    }

    /// 驗證 Gemini：以預設設定要求只回一個詞，兩種輸出方式都完整回答且退出碼為 0
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    @Test(
        .enabled(if: LKAICommandLiveTests.isAPIKeyConfigured(named: "LKAI_GEMINI_API_KEY")),
        .timeLimit(.minutes(2)),
        arguments: LKAICommandLiveTests.outputModes
    )
    func lkai_google要求只回一個詞_輸出完整回答且退出碼為0(
        mode: LKAIChatRunner.OutputMode
    ) throws {
        // Given
        let environmentName = "LKAI_GEMINI_API_KEY"
        let apiKey = try #require(ProcessInfo.processInfo.environment[environmentName])
        let environment = makeEnvironment(adding: apiKey, named: environmentName)
        let arguments = makeArguments(
            provider: "google",
            model: "gemini-3.5-flash-lite",
            mode: mode
        )

        // When
        let output = try LKAICommandTestSupport.runLKAI(
            arguments: arguments,
            environment: environment
        )

        // Then
        let checks = makeChecks(of: output, apiKey: apiKey)
        #expect(checks.exitedWithZero, checks.diagnostics)
        #expect(checks.hasEmptyStandardError, checks.diagnostics)
        #expect(checks.hasAnswer, checks.diagnostics)
        #expect(checks.endsWithLineFeed, checks.diagnostics)
        #expect(!checks.leaksAPIKey, checks.diagnostics)
    }
}

// MARK: - Nested Types

extension LKAICommandLiveTests {

    /// 一次 `lkai` 執行的結果檢查：每一項都先算成布林值，斷言失敗時只會印出布林值與已遮蔽金鑰的說明
    struct RunChecks {

        /// 退出碼是不是 0
        let exitedWithZero: Bool

        /// 標準錯誤是不是空的
        let hasEmptyStandardError: Bool

        /// 標準輸出去掉空白與換行後是不是不為空
        let hasAnswer: Bool

        /// 標準輸出是不是以 LF（`\n`）結尾
        let endsWithLineFeed: Bool

        /// 標準輸出或標準錯誤有沒有含 API 金鑰
        let leaksAPIKey: Bool

        /// 失敗時附在斷言上的說明：退出碼，以及把金鑰換成 `[REDACTED]` 的標準錯誤
        let diagnostics: Comment
    }
}

// MARK: - Private Method

private extension LKAICommandLiveTests {

    /// 環境變數是否有設定 API 金鑰，沒有設定時整個測試函式略過
    ///
    /// - Parameter name: 儲存 API 金鑰的環境變數名稱
    /// - Returns: 有設定而且不是空字串時為 true；`lkai` 把空字串當成沒有設定，所以這裡也一樣
    static func isAPIKeyConfigured(named name: String) -> Bool {
        ProcessInfo.processInfo.environment[name]?.isEmpty == false
    }

    /// 組出執行 `lkai` 的環境變數：預設環境已移除所有 `LKAI_*_API_KEY`，只加回這一家的金鑰
    ///
    /// - Parameters:
    ///   - apiKey: 這一家的 API 金鑰
    ///   - name: 儲存這一家金鑰的環境變數名稱
    /// - Returns: 交給行程的環境變數
    func makeEnvironment(adding apiKey: String, named name: String) -> [String: String] {
        var environment = LKAICommandTestSupport.defaultEnvironment
        environment[name] = apiKey
        return environment
    }

    /// 組出傳給 `lkai` 的命令列引數：供應商、模型與要求只回一個詞的提示詞，金鑰不在其中
    ///
    /// - Parameters:
    ///   - provider: `--provider` 的值
    ///   - model: `--model` 的值
    ///   - mode: 輸出方式，加 `--stream` 或不加
    /// - Returns: 命令列引數；不含 `--max-output-tokens` 與 `--timeout`
    func makeArguments(
        provider: String,
        model: String,
        mode: LKAIChatRunner.OutputMode
    ) -> [String] {
        let baseArguments = [
            "--provider", provider, "-m", model, "-p", "Reply with the single word OK.",
        ]
        return mode == .stream ? baseArguments + ["--stream"] : baseArguments
    }

    /// 檢查一次執行的結果，每一項都先算成布林值
    ///
    /// - Parameters:
    ///   - output: 行程結束後留下的標準輸出、標準錯誤與退出碼
    ///   - apiKey: 這次使用的 API 金鑰
    /// - Returns: 各項檢查與失敗時的說明
    /// - Note: 說明只含退出碼與已遮蔽金鑰的標準錯誤，不含標準輸出；金鑰是空字串時不遮蔽
    func makeChecks(of output: LKAICommandTestSupport.CommandOutput, apiKey: String) -> RunChecks {
        let redactedStandardError = apiKey.isEmpty
            ? output.standardError
            : output.standardError.replacing(apiKey, with: "[REDACTED]")
        let leaksAPIKey = !apiKey.isEmpty
            && (output.standardOutput.contains(apiKey) || output.standardError.contains(apiKey))
        let answer = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return RunChecks(
            exitedWithZero: output.terminationStatus == 0,
            hasEmptyStandardError: output.standardError.isEmpty,
            hasAnswer: !answer.isEmpty,
            endsWithLineFeed: output.standardOutput.hasSuffix("\n"),
            leaksAPIKey: leaksAPIKey,
            diagnostics: "退出碼 \(output.terminationStatus)；標準錯誤（金鑰已遮蔽）：\(redactedStandardError)"
        )
    }
}
