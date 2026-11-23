//
//  LKAIChatInput.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit

/// 檢查過的對話輸入：供應商、API 金鑰、要送出的請求，以及等待資料的時間上限
///
/// - Note: 由命令列選項與環境變數建立，建立成功就代表每一條輸入規則都通過
/// - Note: 請求只有一則使用者訊息，沒有系統指示；`--output-language` 不是輸入的一部分，
///   所以輸出語言不會影響請求
/// - Note: 不依賴 ArgumentParser，命令列選項由 `LKAICommand.swift` 傳進來
struct LKAIChatInput: Sendable {

    // MARK: - Properties

    /// 要使用的供應商
    let provider: LKAIChatProvider

    /// 這次使用的 API 金鑰；印出與記錄時只會顯示遮蔽文字
    let apiKey: LKAIAPIKey

    /// 要送出的對話請求
    let request: LKAIChatRequest

    /// 多久沒有收到 AI 服務的任何資料就放棄，單位為秒
    let timeout: Int

    // MARK: - Init

    /// 把命令列選項與環境變數變成檢查過的輸入；任何一條規則不符就丟出對應的錯誤
    ///
    /// - Parameters:
    ///   - provider: `--provider` 的值；沒給為 nil
    ///   - model: `--model` 的值；沒給為 nil
    ///   - prompt: `--prompt` 的值；沒給為 nil
    ///   - promptFile: `--prompt-file` 的值，也就是檔案路徑；沒給為 nil
    ///   - apiKey: `--apiKey` 的值；沒給為 nil
    ///   - maxOutputTokens: `--max-output-tokens` 的值
    ///   - timeout: `--timeout` 的值，單位為秒
    ///   - environment: 目前行程的環境變數，只讀取所選供應商讀取金鑰的那一個
    /// - Throws: 依下列順序檢查，只丟出第一個不符的規則：供應商、模型、提示詞選項、
    ///   檔案副檔名、讀檔、空白的提示詞、輸出上限、逾時、金鑰
    /// - Note: 模型只檢查是否為 nil 或空字串，不修剪空白，和 `LKAIChatRequest.validate()` 相同
    /// - Note: `--prompt` 與 `--prompt-file` 只能給一個；檔案的副檔名不分大小寫，只接受 `txt` 與 `md`，
    ///   內容以 UTF-8 讀取
    /// - Note: 提示詞去掉空白與換行後為空就算空白；送出時不修剪，原樣送出
    /// - Note: 金鑰先用 `--apiKey`，沒給或是空字串時，改讀所選供應商的環境變數；兩者都沒有值就丟出錯誤
    init(
        provider: LKAIChatProvider?,
        model: String?,
        prompt: String?,
        promptFile: String?,
        apiKey: String?,
        maxOutputTokens: Int,
        timeout: Int,
        environment: [String: String]
    ) throws(LKAIChatInputError) {
        guard let provider else {
            throw .missingProvider
        }
        guard let model, !model.isEmpty else {
            throw .missingModel
        }
        let promptText = try Self.makePromptText(prompt: prompt, promptFile: promptFile)
        guard maxOutputTokens >= 1 else {
            throw .invalidMaxOutputTokens
        }
        guard timeout >= 1 else {
            throw .invalidTimeout
        }
        let resolvedAPIKey = try Self.makeAPIKey(
            apiKey: apiKey,
            provider: provider,
            environment: environment
        )

        self.provider = provider
        self.apiKey = resolvedAPIKey
        self.request = LKAIChatRequest(
            model: model,
            messages: [LKAIMessage(role: .user, text: promptText)],
            systemPrompt: nil,
            maxOutputTokens: maxOutputTokens
        )
        self.timeout = timeout
    }
}

// MARK: - Internal Method

extension LKAIChatInput {

    /// 建立送出請求用的 `URLSession` 設定：不留存 cookie 與磁碟快取，並設定等待資料的時間上限
    ///
    /// - Returns: 請求逾時（`timeoutIntervalForRequest`）設為 `timeout` 秒的設定
    /// - Note: 逾時的意思是「多久沒有收到任何資料就放棄」，回應開始前與兩段資料之間都適用，
    ///   每收到資料就重新計時；不是整個請求的總時間
    /// - Note: 整個 `LKAIKitCLI` 只有這裡建立 `URLSession` 的設定
    func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeout)
        return configuration
    }
}

// MARK: - Private Method

private extension LKAIChatInput {

    /// 取得要送出的提示詞：`--prompt` 的文字，或 `--prompt-file` 的檔案內容，並確認不是空白
    ///
    /// - Parameters:
    ///   - prompt: `--prompt` 的值；沒給為 nil
    ///   - promptFile: `--prompt-file` 的值，也就是檔案路徑；沒給為 nil
    /// - Returns: 提示詞，沒有修剪，原樣交出
    /// - Throws: 兩個選項都給或都沒給、檔案副檔名不支援、檔案讀不了，或提示詞是空白時丟出
    /// - Note: 這是 `static`，因為 `init` 呼叫它時，stored property 還沒有全部賦值，沒有實例可用
    static func makePromptText(
        prompt: String?,
        promptFile: String?
    ) throws(LKAIChatInputError) -> String {
        let promptText: String
        let blankPath: String?
        switch (prompt, promptFile) {
        case (.some, .some):
            throw .conflictingPrompts

        case (nil, nil):
            throw .missingPrompt

        case (let prompt?, nil):
            promptText = prompt
            blankPath = nil

        case (nil, let promptFile?):
            promptText = try readPromptFile(at: promptFile)
            blankPath = promptFile
        }
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .blankPrompt(path: blankPath)
        }
        return promptText
    }

    /// 讀取提示詞檔案的內容
    ///
    /// - Parameter path: 檔案路徑
    /// - Returns: 以 UTF-8 讀出的檔案內容
    /// - Throws: 副檔名（不分大小寫）不是 `txt` 或 `md` 時丟出 `unsupportedPromptFile`；
    ///   找不到檔案、是資料夾或不是 UTF-8 時丟出 `unreadablePromptFile`，都帶著傳入的路徑
    /// - Note: 先檢查副檔名再讀檔，所以不支援的副檔名不會去碰檔案
    static func readPromptFile(at path: String) throws(LKAIChatInputError) -> String {
        let fileURL = URL(filePath: path)
        guard ["txt", "md"].contains(fileURL.pathExtension.lowercased()) else {
            throw .unsupportedPromptFile(path: path)
        }
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // 不論是找不到、是資料夾還是不是 UTF-8，使用者要知道的都只是這個檔案讀不了
            throw .unreadablePromptFile(path: path)
        }
    }

    /// 選出這次使用的 API 金鑰：`--apiKey` 優先，其次是所選供應商的環境變數
    ///
    /// - Parameters:
    ///   - apiKey: `--apiKey` 的值；沒給為 nil
    ///   - provider: 所選的供應商，決定讀哪個環境變數
    ///   - environment: 目前行程的環境變數
    /// - Returns: 包成 `LKAIAPIKey` 的金鑰
    /// - Throws: `--apiKey` 與環境變數都沒有值（nil 或空字串）時丟出 `missingAPIKey`
    /// - Note: 這是 `static`，原因同 `makePromptText(prompt:promptFile:)`
    static func makeAPIKey(
        apiKey: String?,
        provider: LKAIChatProvider,
        environment: [String: String]
    ) throws(LKAIChatInputError) -> LKAIAPIKey {
        if let apiKey, !apiKey.isEmpty {
            return LKAIAPIKey(apiKey)
        }
        let environmentName = provider.apiKeyEnvironmentName
        if let value = environment[environmentName], !value.isEmpty {
            return LKAIAPIKey(value)
        }
        throw .missingAPIKey(environmentName: environmentName)
    }
}
