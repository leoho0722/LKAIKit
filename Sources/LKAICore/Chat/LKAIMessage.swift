//
//  LKAIMessage.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一則對話訊息，內容只有文字
///
/// - Note: 之後新增欄位時，`init` 的新參數一律給預設值，讓既有的呼叫端不必修改
public struct LKAIMessage: Equatable, Sendable {

    // MARK: - Properties

    /// 這則訊息的角色，使用者或助理
    public let role: LKAIMessageRole

    /// 訊息的文字內容
    public let text: String

    // MARK: - Init

    /// 建立一則對話訊息
    ///
    /// - Parameters:
    ///   - role: 這則訊息的角色
    ///   - text: 訊息的文字內容
    public init(role: LKAIMessageRole, text: String) {
        self.role = role
        self.text = text
    }
}
