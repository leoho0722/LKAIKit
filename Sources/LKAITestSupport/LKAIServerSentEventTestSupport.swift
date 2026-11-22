//
//  LKAIServerSentEventTestSupport.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// SSE 分框的測試 helper，把 `LKAIServerSentEvent` 轉成替身要推送的逐行內容，供各供應商的測試共用
package enum LKAIServerSentEventTestSupport {

}

// MARK: - Internal Method

extension LKAIServerSentEventTestSupport {

    /// 把 SSE 事件轉成逐行內容：依事件順序，每個事件輸出 `event: <event>`、`data: <data>` 與一個空行
    ///
    /// - Parameter events: 依序排列的 SSE 事件
    /// - Returns: 依序排列的逐行內容，每一行都不含 CR 與 LF
    /// - Note: `event` 為 nil 時不輸出 `event:` 那一行，只剩 `data:` 與空行
    /// - Note: `event` 與 `data` 都原樣放在一行，兩者都不能含 CR 或 LF
    package static func lines(of events: [LKAIServerSentEvent]) -> [String] {
        var result: [String] = []
        for event in events {
            if let name = event.event {
                result.append("event: \(name)")
            }
            result.append("data: \(event.data)")
            result.append("")
        }
        return result
    }
}
