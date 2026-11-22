//
//  LKOpenAIStreamState.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 讀取一次串流期間累積的狀態，目前每則 SSE 事件都不交出對話事件
///
/// - Note: 只在 `LKAIOpenAI` 內使用；SSE 事件依序交給 `handle(_:)`
struct LKOpenAIStreamState {

    // MARK: - Init

    /// 建立一個還沒有收到任何事件的狀態
    init() {}
}

// MARK: - LKAIServerSentEventMapping

extension LKOpenAIStreamState: LKAIServerSentEventMapping {

    /// 不處理收到的 SSE 事件，也不交出任何對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件
    /// - Returns: 一律為空陣列
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent] {
        []
    }
}
