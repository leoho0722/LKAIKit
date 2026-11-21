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

    /// 輸出的長度用完了呼叫端設定的上限，回答被截斷；調高輸出上限可以解決
    case maxOutputTokens

    /// 輸入加輸出塞滿了模型一次能處理的上限（context window），回答被截斷
    ///
    /// - Note: 調高輸出上限沒用，要縮短對話內容，或換一個上限更大的模型
    /// - Note: 本 change 只有 Anthropic 會回報這個狀態
    /// - Note: 其他供應商由各自的 change 查證；沒有對應狀態時，可能以 `.maxOutputTokens` 或 `.invalidRequest` 出現
    case contextWindowExceeded
}
