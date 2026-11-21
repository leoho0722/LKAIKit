//
//  LKAIChatCompletion.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一次對話結束時的資訊：為什麼結束、用了多少 token、實際回答的是哪個模型
///
/// - Note: 之後新增欄位時，`init` 的新參數一律給預設值，讓既有的呼叫端不必修改
public struct LKAIChatCompletion: Equatable, Sendable {

    // MARK: - Properties

    /// 生成結束的原因
    public let finishReason: LKAIFinishReason

    /// token 用量；供應商沒有回報時為 nil
    public let usage: LKAIUsage?

    /// 供應商回報的、實際產生最後輸出的模型識別碼；開啟拒答備援時可能與請求的模型不同，沒有回報時為 nil
    public let respondingModel: String?

    // MARK: - Init

    /// 建立一筆對話結束時的資訊
    ///
    /// - Parameters:
    ///   - finishReason: 生成結束的原因
    ///   - usage: token 用量；供應商沒有回報時傳 nil
    ///   - respondingModel: 實際產生最後輸出的模型識別碼；供應商沒有回報時傳 nil
    public init(finishReason: LKAIFinishReason, usage: LKAIUsage?, respondingModel: String?) {
        self.finishReason = finishReason
        self.usage = usage
        self.respondingModel = respondingModel
    }
}
