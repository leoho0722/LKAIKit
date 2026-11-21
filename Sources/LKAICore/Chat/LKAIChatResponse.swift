//
//  LKAIChatResponse.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 非串流對話的結果：完整的回答文字，加上結束時的資訊
public struct LKAIChatResponse: Equatable, Sendable {

    // MARK: - Properties

    /// 完整的回答文字，由所有文字片段依序串接而成
    public let text: String

    /// 結束時的資訊；結束原因等都在這裡，例如 `response.completion.finishReason`
    public let completion: LKAIChatCompletion

    // MARK: - Init

    /// 建立一筆非串流對話的結果
    ///
    /// - Parameters:
    ///   - text: 完整的回答文字
    ///   - completion: 結束時的資訊
    public init(text: String, completion: LKAIChatCompletion) {
        self.text = text
        self.completion = completion
    }
}
