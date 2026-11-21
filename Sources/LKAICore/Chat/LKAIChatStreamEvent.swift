//
//  LKAIChatStreamEvent.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 串流對話過程中依序交出的事件：先是一段一段的文字，最後是結束事件
///
/// - Note: 之後可能新增 case，App 對它做 `switch` 時必須寫 `@unknown default`
@nonexhaustive
public enum LKAIChatStreamEvent: Equatable, Sendable {

    /// 模型新產生的一段文字
    ///
    /// - Parameter string: 這一段新增的文字，要由呼叫端自己串接
    case textDelta(String)

    /// 串流的最後一個事件，在串流最後出現一次，帶著結束時的資訊
    ///
    /// - Parameter completion: 結束原因、token 用量與實際回答的模型
    case finished(LKAIChatCompletion)
}
