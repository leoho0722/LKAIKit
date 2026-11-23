//
//  LKAICLIText.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit

/// `lkai` 自己輸出的文字，raw value 是 `LKAIKitCLI` 的 String Catalog 裡的 key
///
/// - Note: 每個 case 在 `en` 與 `zh-Hant` 都要有值，由 `CaseIterable` 讓測試逐一檢查
/// - Note: 說明的 key 是 `cli.help.<項目>`，警告是 `warning.cli.<case>`；`error.cli.<case>` 用於輸入錯誤，
///   也用於寫回答到標準輸出失敗的訊息（`error.cli.answerWriteFailed`）
/// - Note: String Catalog 不寫供應商與環境變數的名稱，需要時以 `%@` 代入
enum LKAICLIText: String, CaseIterable {

    /// 指令的簡介，說明 `lkai` 是做什麼的
    case helpAbstract = "cli.help.abstract"

    /// 指令的補充說明，列出環境變數與四個退出碼
    ///
    /// - Note: 帶一個 `%@`，代入各供應商讀取金鑰的環境變數名稱清單
    case helpDiscussion = "cli.help.discussion"

    /// `--provider` 的說明
    case helpProvider = "cli.help.provider"

    /// `--model` 的說明
    case helpModel = "cli.help.model"

    /// `--prompt` 的說明，寫明以 `-` 開頭的內容要改用 `--prompt=<text>` 或 `--prompt-file`
    case helpPrompt = "cli.help.prompt"

    /// `--prompt-file` 的說明
    case helpPromptFile = "cli.help.promptFile"

    /// `--apiKey` 的說明，寫明沒給時讀供應商的環境變數，在 CI 中優先使用環境變數
    case helpAPIKey = "cli.help.apiKey"

    /// `--max-output-tokens` 的說明
    case helpMaxOutputTokens = "cli.help.maxOutputTokens"

    /// `--timeout` 的說明，寫明是多久沒有收到 AI 服務的任何資料就放棄
    case helpTimeout = "cli.help.timeout"

    /// `--stream` 的說明
    case helpStream = "cli.help.stream"

    /// `--output-language` 的說明，寫明只影響 `lkai` 自己的訊息，不影響 AI 回答的語言
    case helpOutputLanguage = "cli.help.outputLanguage"

    /// `-v`、`--version` 的說明
    case helpVersion = "cli.help.version"

    /// 沒有給 `--provider`
    case errorMissingProvider = "error.cli.missingProvider"

    /// 沒有給 `--model`，或給的是空字串
    case errorMissingModel = "error.cli.missingModel"

    /// `--prompt` 與 `--prompt-file` 同時給了
    case errorConflictingPrompts = "error.cli.conflictingPrompts"

    /// `--prompt` 與 `--prompt-file` 都沒給
    case errorMissingPrompt = "error.cli.missingPrompt"

    /// 提示詞檔案的副檔名不是 `txt` 或 `md`
    ///
    /// - Note: 帶一個 `%@`，代入檔案路徑
    case errorUnsupportedPromptFile = "error.cli.unsupportedPromptFile"

    /// 提示詞檔案讀不了：找不到、是資料夾，或內容不是 UTF-8
    ///
    /// - Note: 帶一個 `%@`，代入檔案路徑
    case errorUnreadablePromptFile = "error.cli.unreadablePromptFile"

    /// `--prompt` 的內容是空字串，或只有空白與換行
    case errorBlankPrompt = "error.cli.blankPrompt"

    /// 提示詞檔案的內容是空字串，或只有空白與換行
    ///
    /// - Note: 帶一個 `%@`，代入檔案路徑
    case errorBlankPromptFile = "error.cli.blankPromptFile"

    /// `--max-output-tokens` 小於 1
    case errorInvalidMaxOutputTokens = "error.cli.invalidMaxOutputTokens"

    /// `--timeout` 小於 1
    case errorInvalidTimeout = "error.cli.invalidTimeout"

    /// 沒有給 `--apiKey`，所選供應商的環境變數也沒有值
    ///
    /// - Note: 帶一個 `%@`，代入所選供應商讀取金鑰的環境變數名稱
    case errorMissingAPIKey = "error.cli.missingAPIKey"

    /// 回答無法寫到標準輸出，例如把輸出導向的檔案已經寫滿
    case errorAnswerWriteFailed = "error.cli.answerWriteFailed"

    /// 回答達到輸出上限而被截斷，提示調高 `--max-output-tokens`
    case warningMaxOutputTokens = "warning.cli.maxOutputTokens"

    /// 提示詞加回答塞滿模型的 context window 而被截斷，說明調高輸出上限沒用
    case warningContextWindowExceeded = "warning.cli.contextWindowExceeded"
}

// MARK: - Internal Method

extension LKAICLIText {

    /// 以指定的輸出語言查這個字串，有參數時依序代入 `%@`
    ///
    /// - Parameters:
    ///   - language: 輸出語言；不跟隨系統的語言設定
    ///   - arguments: 依序代入字串內 `%@` 的參數；字串沒有 `%@` 時不傳
    /// - Returns: 該語言的字串；沒有參數時原樣交出 String Catalog 的內容
    func string(in language: LKAIOutputLanguage, _ arguments: any CVarArg...) -> String {
        let template = LKAILocalization.string(
            forKey: rawValue,
            in: .module,
            localization: language.localization
        )
        guard !arguments.isEmpty else {
            return template
        }
        return String(format: template, arguments: arguments)
    }
}
