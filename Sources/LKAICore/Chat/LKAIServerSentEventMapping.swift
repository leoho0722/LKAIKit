//
//  LKAIServerSentEventMapping.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/22.
//

/// 把供應商的 SSE 事件對應成對話事件的狀態，每條串流各用一份，由各供應商實作
///
/// - Note: 狀態（例如累計的用量與結束原因）與「何時結束」的判斷都由供應商的實作持有，共同流程只負責依序交出結果
/// - Note: 不要求 `Sendable`：每份狀態在串流的 task 內建立，只在那個 task 內使用
package protocol LKAIServerSentEventMapping {

    /// 處理一則 SSE 事件，更新自己的狀態，並回傳要依序交出的對話事件
    ///
    /// - Parameter event: 剛解析出的 SSE 事件
    /// - Returns: 要依序交出的對話事件；沒有要交出的事件時為空陣列
    /// - Throws: 事件無法解碼、供應商回報錯誤，或結束原因不正常時丟出對應的 `LKAIError`
    /// - Note: 交出結束事件時，`.finished` 放在陣列最後；共同流程交出它之後就返回，同一個陣列裡在它之後的事件不交出
    /// - Note: 回傳陣列，是因為同一則事件可能同時帶最後一段文字與結束原因，要依序交出 `.textDelta` 與 `.finished`
    mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent]
}
