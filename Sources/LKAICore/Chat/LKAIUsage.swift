//
//  LKAIUsage.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一次對話消耗的 token 用量，各供應商統一成同一種算法，只供觀察與粗估，不保證能精確計費
///
/// - Note: `inputTokens` 一律包含讀自快取的部分，`outputTokens` 一律包含思考或推理的部分
public struct LKAIUsage: Equatable, Sendable {

    // MARK: - Properties

    /// 送進模型的 token 數，包含讀自快取的部分
    public let inputTokens: Int

    /// 模型產生的 token 數，包含思考或推理的部分
    public let outputTokens: Int

    /// 輸入 token 中讀自快取的部分；供應商沒有提供時為 nil，不是 0
    public let cachedInputTokens: Int?

    /// 輸出 token 中用在思考或推理的部分；供應商沒有提供時為 nil，不是 0
    public let reasoningOutputTokens: Int?

    // MARK: - Init

    /// 建立一筆 token 用量
    ///
    /// - Parameters:
    ///   - inputTokens: 送進模型的 token 數，須包含讀自快取的部分
    ///   - outputTokens: 模型產生的 token 數，須包含思考或推理的部分
    ///   - cachedInputTokens: 輸入 token 中讀自快取的部分；供應商沒有提供時傳 nil
    ///   - reasoningOutputTokens: 輸出 token 中用在思考或推理的部分；供應商沒有提供時傳 nil
    public init(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        reasoningOutputTokens: Int?
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}
