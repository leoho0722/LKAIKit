//
//  LKAIServerSentEvent.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一筆 Server-Sent Event 事件，由 `LKAIServerSentEventParser` 從一行一行的文字組成
package struct LKAIServerSentEvent: Equatable, Sendable {

    // MARK: - Properties

    /// 事件名稱，沒有 event 欄位時為 nil
    package let event: String?

    /// 事件的資料，多個 data 欄位的值以 `\n` 接起來
    package let data: String

    // MARK: - Init

    /// 建立一筆事件，沒有事件名稱時傳入 nil
    ///
    /// - Parameters:
    ///   - event: 事件名稱，沒有 event 欄位時為 nil
    ///   - data: 事件的資料
    package init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}
