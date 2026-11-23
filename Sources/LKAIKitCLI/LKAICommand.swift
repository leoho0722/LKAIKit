//
//  LKAICommand.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/21.
//

import ArgumentParser
import LKAIKit

/// `lkai` 命令列工具的根指令，給 CI/CD 流程呼叫，宣告所有對話選項；目前不論給什麼輸入，都印出說明
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

// MARK: - LKAIChatProvider

/// 讓 `--provider` 接受 `LKAIChatProvider`；`String` raw value 加上 `CaseIterable`，
/// 預設實作就提供轉換與說明中的 `(values: …)`
extension LKAIChatProvider: ExpressibleByArgument {

}

// MARK: - LKAIOutputLanguage

/// 讓 `--output-language` 接受 `LKAIOutputLanguage`；`String` raw value 加上 `CaseIterable`，
/// 預設實作就提供轉換、`(values: …)` 與以 raw value 顯示的 `(default: …)`
extension LKAIOutputLanguage: ExpressibleByArgument {

}
