//
//  LKAIFinishReason.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一次對話生成結束的原因
///
/// - Note: 之後可能新增 case，App 對它做 `switch` 時必須寫 `@unknown default`
@nonexhaustive
public enum LKAIFinishReason: CaseIterable, Sendable {

    /// 模型把回答完整寫完
    case completed

    /// 輸出的長度用完了呼叫端設定的上限，回答被截斷
    ///
    /// - Note: 一般調高輸出上限可以解決
    /// - Note: 有些供應商在生成途中塞滿 context window 時也回報這個原因，例如 OpenAI 與 Gemini；
    ///   在這些供應商上調高輸出上限不一定有用
    case maxOutputTokens

    /// 輸入加輸出塞滿了模型一次能處理的上限（context window），回答被截斷
    ///
    /// - Note: 調高輸出上限沒用，要縮短對話內容，或換一個上限更大的模型
    /// - Note: 只有把兩種原因分開回報的供應商才會回報，目前只有 Anthropic；
    ///   其他供應商在生成途中塞滿時以 `.maxOutputTokens` 出現
    /// - Note: 輸入在生成前就超過上限時，供應商以錯誤拒絕請求，通常是 `.invalidRequest`，
    ///   不是這個結束原因
    case contextWindowExceeded
}
