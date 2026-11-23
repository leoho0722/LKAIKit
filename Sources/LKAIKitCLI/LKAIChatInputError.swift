//
//  LKAIChatInputError.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

/// 命令列輸入檢查失敗的原因，case 依檢查的順序排列
///
/// - Note: 每個 case 對應一則 `error.cli.*` 的訊息，兩種輸出語言都一定含有 spec 指定的詞
/// - Note: 訊息只寫選項名稱、檔案路徑或環境變數名稱，不含 API 金鑰
/// - Note: 不依賴 ArgumentParser，轉成 `ValidationError` 的對接只寫在 `LKAICommand.swift`
enum LKAIChatInputError: Error, Equatable {

    /// 沒有給 `--provider`
    case missingProvider

    /// 沒有給 `--model`，或給的是空字串
    case missingModel

    /// `--prompt` 與 `--prompt-file` 同時給了
    case conflictingPrompts

    /// `--prompt` 與 `--prompt-file` 都沒給
    case missingPrompt

    /// 提示詞檔案的副檔名不是 `txt` 或 `md`
    ///
    /// - Parameter path: 呼叫端傳入的檔案路徑，原樣保留
    case unsupportedPromptFile(path: String)

    /// 提示詞檔案讀不了：找不到、是資料夾，或內容不是 UTF-8
    ///
    /// - Parameter path: 呼叫端傳入的檔案路徑，原樣保留
    case unreadablePromptFile(path: String)

    /// 提示詞是空字串，或只有空白與換行
    ///
    /// - Parameter path: 提示詞來自檔案時是檔案路徑，來自 `--prompt` 時為 nil
    /// - Note: 來自 `--prompt` 的訊息用 `error.cli.blankPrompt`，來自檔案的用 `error.cli.blankPromptFile`
    case blankPrompt(path: String?)

    /// `--max-output-tokens` 小於 1
    case invalidMaxOutputTokens

    /// `--timeout` 小於 1
    case invalidTimeout

    /// 沒有給 `--apiKey`，所選供應商的環境變數也沒有值
    ///
    /// - Parameter environmentName: 所選供應商讀取金鑰的環境變數名稱
    case missingAPIKey(environmentName: String)
}

// MARK: - Internal Method

extension LKAIChatInputError {

    /// 以指定的輸出語言給出這個錯誤的訊息，給使用者看，放在 `Error: ` 之後
    ///
    /// - Parameter language: 輸出語言
    /// - Returns: 該語言的訊息，含 spec 指定的選項名稱、檔案路徑或環境變數名稱
    /// - Note: 有路徑或環境變數名稱的訊息，以 `%@` 代入，路徑與名稱照原樣放進訊息
    func message(in language: LKAIOutputLanguage) -> String {
        switch self {
        case .missingProvider:
            LKAICLIText.errorMissingProvider.string(in: language)

        case .missingModel:
            LKAICLIText.errorMissingModel.string(in: language)

        case .conflictingPrompts:
            LKAICLIText.errorConflictingPrompts.string(in: language)

        case .missingPrompt:
            LKAICLIText.errorMissingPrompt.string(in: language)

        case .unsupportedPromptFile(let path):
            LKAICLIText.errorUnsupportedPromptFile.string(in: language, path)

        case .unreadablePromptFile(let path):
            LKAICLIText.errorUnreadablePromptFile.string(in: language, path)

        case .blankPrompt(path: nil):
            LKAICLIText.errorBlankPrompt.string(in: language)

        case .blankPrompt(let path?):
            LKAICLIText.errorBlankPromptFile.string(in: language, path)

        case .invalidMaxOutputTokens:
            LKAICLIText.errorInvalidMaxOutputTokens.string(in: language)

        case .invalidTimeout:
            LKAICLIText.errorInvalidTimeout.string(in: language)

        case .missingAPIKey(let environmentName):
            LKAICLIText.errorMissingAPIKey.string(in: language, environmentName)
        }
    }
}
