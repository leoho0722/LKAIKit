//
//  LKGeminiStreamState.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 讀取一次串流期間累積的狀態，把 Gemini 的 SSE 事件對應成對話事件
///
/// - Note: 只在 `LKAIGemini` 內使用；SSE 事件依序交給 `handle(_:)`
/// - Note: 事件對應之後再實作，目前不認得任何事件
struct LKGeminiStreamState {

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKGeminiStreamState: LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件；目前不認得任何事件，一律不交出對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件
    /// - Returns: 一律為空陣列
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        []
    }
}
