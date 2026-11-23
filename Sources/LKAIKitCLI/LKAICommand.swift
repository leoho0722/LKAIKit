//
//  LKAICommand.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/21.
//

import ArgumentParser
import Foundation
import LKAIKit

/// `lkai` 命令列工具的根指令，給 CI/CD 流程呼叫：宣告對話選項，檢查輸入後送出一次對話請求，
/// 並把結果對應成退出碼
///
/// - Note: 說明的簡介、補充說明與每個選項的說明，都以 `LKAIOutputLanguage.current` 的語言查 `LKAICLIText`
/// - Note: 只有這個檔案依賴 ArgumentParser
@main
struct LKAICommand {

    // MARK: - Properties

    /// `--provider`：要使用的 AI 服務
    @Option(help: ArgumentHelp(LKAICLIText.helpProvider.string(in: .current)))
    var provider: LKAIChatProvider?

    /// `-m`、`--model`：要使用的模型
    @Option(
        name: [.short, .long],
        help: ArgumentHelp(LKAICLIText.helpModel.string(in: .current))
    )
    var model: String?

    /// `-p`、`--prompt`：提示詞的文字
    @Option(
        name: [.short, .long],
        help: ArgumentHelp(LKAICLIText.helpPrompt.string(in: .current))
    )
    var prompt: String?

    /// `-f`、`--prompt-file`：存放提示詞的檔案路徑；值的名稱寫成 `path`，說明與用法才一致
    @Option(
        name: [.customShort("f"), .long],
        help: ArgumentHelp(LKAICLIText.helpPromptFile.string(in: .current), valueName: "path")
    )
    var promptFile: String?

    /// `--apiKey`：API 金鑰；拼法照使用者指定，和其他 kebab-case 的選項不同
    @Option(
        name: .customLong("apiKey"),
        help: ArgumentHelp(LKAICLIText.helpAPIKey.string(in: .current))
    )
    var apiKey: String?

    /// `--max-output-tokens`：回答最多可使用的 token 數
    @Option(help: ArgumentHelp(LKAICLIText.helpMaxOutputTokens.string(in: .current)))
    var maxOutputTokens: Int = 4096

    /// `--timeout`：多久沒有收到任何資料就放棄，單位為秒
    @Option(help: ArgumentHelp(LKAICLIText.helpTimeout.string(in: .current)))
    var timeout: Int = 60

    /// `--stream`：邊收邊印出回答
    @Flag(help: ArgumentHelp(LKAICLIText.helpStream.string(in: .current)))
    var stream = false

    /// `--output-language`：`lkai` 自己的訊息使用的語言
    ///
    /// - Note: 說明與解析錯誤的文字要在解析之前產生，由 `LKAIOutputLanguage.scanned(from:)` 先掃描命令列。
    ///   改這個選項的名稱、parsing 策略，或值的轉換時，要同步修改 `scanned(from:)`，
    ///   並在 `LKAICommandTests` 的 `scanned_可解析的引數_與解析出的輸出語言相同` 加一組引數
    @Option(help: ArgumentHelp(LKAICLIText.helpOutputLanguage.string(in: .current)))
    var outputLanguage: LKAIOutputLanguage = .enUS

    /// `-v`、`--version`：印出版本號碼
    @Flag(
        name: [.short, .long],
        help: ArgumentHelp(LKAICLIText.helpVersion.string(in: .current))
    )
    var version = false
}

// MARK: - AsyncParsableCommand

extension LKAICommand: AsyncParsableCommand {

    /// 指令的名稱、簡介、補充說明與用法
    ///
    /// - Note: 簡介與補充說明讀 `LKAIOutputLanguage.current`；補充說明的 `%@` 代入各供應商
    ///   讀取金鑰的環境變數名稱，以逗號連接，所以新增供應商時不必修改字串
    /// - Note: 用法固定兩行、不翻譯：內建的用法把每個選項都包在 `[...]` 裡，看不出哪些是必填
    /// - Note: 不傳版本參數給 `CommandConfiguration`：內建的版本旗標只有 `--version`，沒辦法加上 `-v`，
    ///   版本改由 `version` 旗標與 `validate()` 處理
    static var configuration: CommandConfiguration {
        let environmentNames = LKAIChatProvider.allCases
            .map(\.apiKeyEnvironmentName)
            .joined(separator: ", ")
        let usageLines = [
            "lkai --provider <provider> --model <model> "
                + "(--prompt <prompt> | --prompt-file <path>) [<options>]",
            "lkai --version",
        ]
        return CommandConfiguration(
            commandName: "lkai",
            abstract: LKAICLIText.helpAbstract.string(in: .current),
            usage: usageLines.joined(separator: "\n"),
            discussion: LKAICLIText.helpDiscussion.string(in: .current, environmentNames)
        )
    }

    /// 給了 `-v` 或 `--version` 時，印出 `LKAIKitInfo.version` 並以成功結束
    ///
    /// - Throws: `version` 為 `true` 時丟出 `CleanExit.message`，訊息就是版本號碼，沒有其他文字
    /// - Note: 對話選項的檢查不放在這裡：`validate()` 比「未定義的輸入」的檢查先執行，放在這裡的話，
    ///   `lkai --bogus` 會先回報缺少選項；版本旗標的檢查要比所有對話檢查都先執行，所以留在這裡
    func validate() throws {
        if version {
            throw CleanExit.message(LKAIKitInfo.version)
        }
    }

    /// 執行對話：用真正的環境變數、`URLSession` 與標準輸出入執行 `execute(environment:makeClient:output:)`
    ///
    /// - Throws: `execute(environment:makeClient:output:)` 丟出的錯誤
    /// - Note: 這是唯一讀目前行程的環境變數、建立 `URLSession` 與建立寫到 `FileHandle` 的輸出的地方，
    ///   其餘的流程都由 `execute` 的參數注入，測試才能換成替身
    func run() async throws {
        try await execute(
            environment: ProcessInfo.processInfo.environment,
            makeClient: { input in
                input.provider.makeClient(
                    apiKey: input.apiKey.unredactedValue,
                    urlSession: URLSession(configuration: input.makeSessionConfiguration())
                )
            },
            output: LKAICommandOutput(
                standardOutput: .standardOutput,
                standardError: .standardError
            )
        )
    }

    /// 先掃描命令列取得輸出語言，在那個語言的範圍內解析、執行與結束
    ///
    /// - Note: 說明與解析錯誤的文字在解析時就要產生，等不到解析出的 `--output-language`，
    ///   所以由 `LKAIOutputLanguage.scanned(from:)` 先掃描，再以 `$current.withValue(_:operation:)` 綁定
    /// - Note: 解析出的指令是 `AsyncParsableCommand` 時要 `await` 它的 `run()`；錯誤交給 `exit(withError:)`，
    ///   由它決定訊息印到哪裡與退出碼
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        await LKAIOutputLanguage.$current.withValue(.scanned(from: arguments)) {
            do {
                var command = try parseAsRoot(arguments)
                if var asyncCommand = command as? AsyncParsableCommand {
                    try await asyncCommand.run()
                } else {
                    try command.run()
                }
            } catch {
                exit(withError: error)
            }
        }
    }
}

// MARK: - Internal Method

extension LKAICommand {

    /// 檢查輸入、送出請求並寫出結果，再把結果對應成退出碼
    ///
    /// - Parameters:
    ///   - environment: 目前行程的環境變數，只讀取所選供應商讀取金鑰的那一個
    ///   - makeClient: 依檢查過的輸入建立 client；正式執行時建立真正的 client，測試時換成替身
    ///   - output: 回答、警告與錯誤寫到的地方
    /// - Throws: 四個對話選項都沒給時丟出 `CleanExit.helpRequest`；輸入不合法時丟出 `ValidationError`
    ///   （退出碼 64，並印出用法）；回答沒有正常完成時丟出 `ExitCode(2)`，對話失敗，
    ///   或寫回答到標準輸出失敗時，丟出 `ExitCode.failure`（1）；回答完整時不丟出，退出碼為 0
    /// - Note: `--provider`、`--model`、`--prompt`、`--prompt-file` 只要給了任何一個，就算要對話；
    ///   其他選項單獨給時仍印出說明
    /// - Note: 輸入不合法與之後的訊息，都用解析出的 `outputLanguage`，不讀 `LKAIOutputLanguage.current`
    /// - Note: 加 `--stream` 時邊收邊寫，沒加時等整段回答完成再一次寫出
    func execute(
        environment: [String: String],
        makeClient: (LKAIChatInput) -> any LKAIChatClientProtocol,
        output: LKAICommandOutput
    ) async throws {
        guard provider != nil || model != nil || prompt != nil || promptFile != nil else {
            throw CleanExit.helpRequest(self)
        }

        let input: LKAIChatInput
        do throws(LKAIChatInputError) {
            input = try LKAIChatInput(
                provider: provider,
                model: model,
                prompt: prompt,
                promptFile: promptFile,
                apiKey: apiKey,
                maxOutputTokens: maxOutputTokens,
                timeout: timeout,
                environment: environment
            )
        } catch {
            throw ValidationError(error.message(in: outputLanguage))
        }

        let runner = LKAIChatRunner(
            client: makeClient(input),
            output: output,
            language: outputLanguage,
            apiKey: input.apiKey
        )
        let outcome = await runner.run(input.request, mode: stream ? .stream : .invoke)
        switch outcome {
        case .completed:
            return

        case .incomplete:
            throw ExitCode(2)

        case .failed:
            throw ExitCode.failure
        }
    }
}

// MARK: - LKAIChatProvider

/// 讓 `--provider` 接受 `LKAIChatProvider`；`String` raw value 加上 `CaseIterable`，
/// 預設實作就提供轉換與說明中的 `(values: …)`
extension LKAIChatProvider: ExpressibleByArgument {

}

// MARK: - LKAIOutputLanguage

/// 讓 `--output-language` 接受 `LKAIOutputLanguage`；`String` raw value 加上 `CaseIterable`，
/// 預設實作就提供轉換、`(values: …)` 與以 raw value 顯示的 `(default: …)`
///
/// - Note: 值的轉換改成自訂時，要同步修改 `LKAIOutputLanguage.scanned(from:)`，
///   做法見 `LKAICommand.outputLanguage` 的說明
extension LKAIOutputLanguage: ExpressibleByArgument {

}
