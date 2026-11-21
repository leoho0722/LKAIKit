//
//  LKAIChatRequest.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一次對話呼叫的請求內容：要用的模型、依序排列的訊息、可選的系統指示，以及最多輸出的 token 數
///
/// - Note: `maxOutputTokens` 必填，Anthropic 要求必填，另外兩家也有對應欄位，函式庫不替呼叫端藏預設值
/// - Note: 不提供 temperature 等取樣參數，Anthropic 新版 API 會拒絕這類參數
/// - Note: 之後新增欄位時，`init` 的新參數一律給預設值，讓既有的呼叫端不必修改
public struct LKAIChatRequest: Equatable, Sendable {

    // MARK: - Properties

    /// 要使用的模型識別碼，格式依供應商而定，例如 `claude-opus-5-5`
    public let model: String

    /// 依序排列的對話訊息，只包含使用者與助理的文字訊息
    public let messages: [LKAIMessage]

    /// 系統指示，沒有時為 nil；它不是對話中的一則訊息，各家供應商放的欄位不同
    public let systemPrompt: String?

    /// 最多輸出的 token 數，呼叫端必須指定
    public let maxOutputTokens: Int

    // MARK: - Init

    /// 建立一次對話請求；建立時不檢查內容，供應商送出前會呼叫 `validate()`
    ///
    /// - Parameters:
    ///   - model: 要使用的模型識別碼
    ///   - messages: 依序排列的對話訊息
    ///   - systemPrompt: 系統指示，沒有時傳入 nil
    ///   - maxOutputTokens: 最多輸出的 token 數
    public init(
        model: String,
        messages: [LKAIMessage],
        systemPrompt: String? = nil,
        maxOutputTokens: Int
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.maxOutputTokens = maxOutputTokens
    }
}

// MARK: - Internal Method

extension LKAIChatRequest {

    /// 檢查請求是否合法，供應商送出網路請求前呼叫
    ///
    /// - Throws: 模型為空字串、沒有任何訊息，或 maxOutputTokens 小於 1 時丟出 `invalidRequest`
    /// - Note: 訊息是給開發者看的英文，指出違反的是哪個欄位
    /// - Note: 依序檢查，只丟出第一個違反的規則
    /// - Note: 模型只檢查是否為空字串，不修剪空白，所以純空白的模型名稱會通過
    package func validate() throws(LKAIError) {
        if model.isEmpty {
            throw .invalidRequest(message: "model must not be empty")
        }
        if messages.isEmpty {
            throw .invalidRequest(message: "messages must not be empty")
        }
        if maxOutputTokens < 1 {
            throw .invalidRequest(message: "maxOutputTokens must be at least 1")
        }
    }
}
