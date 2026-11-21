//
//  LKAIMessageRole.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 對話訊息的角色，只有使用者與助理兩種
///
/// - Note: 系統指示不是角色，放在 `LKAIChatRequest` 的 `systemPrompt`
/// - Note: Gemini 的 model 角色由它的 client 轉換，不在這裡出現
/// - Note: 不標 `@nonexhaustive`，新增角色會改變請求的契約，需要另開 change 處理
public enum LKAIMessageRole: CaseIterable, Sendable {

    /// 使用者發出的訊息
    case user

    /// 助理回覆的訊息
    case assistant
}
