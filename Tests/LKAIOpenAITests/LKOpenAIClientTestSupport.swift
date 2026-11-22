//
//  LKOpenAIClientTestSupport.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// `LKOpenAIClient` 的測試共用固定資料與 helper：目前只有合法請求
enum LKOpenAIClientTestSupport {

    // MARK: - Properties

    /// 共用的合法請求：模型、一則使用者訊息與輸出上限，沒有系統指示；內容與各測試要驗證的行為無關
    static let validRequest = LKAIChatRequest(
        model: "gpt-6-luna",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )
}
