//
//  LKAIAPIKey.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/22.
//

/// 保管 API 金鑰的包裝型別，印出、記錄或 `dump(_:)` 時一律只顯示 `LKAIAPIKey(redacted)`
///
/// - Note: 只有三種用途可以讀 `unredactedValue`：組 HTTP 請求、把金鑰交給 client、
///   遮蔽輸出中的金鑰；其他地方不要碰原始值
/// - Note: `description`、`debugDescription` 都是 `LKAIAPIKey(redacted)`，`customMirror` 沒有子項目
/// - Note: 多一層保護：之後有人在 client 的描述加上金鑰欄位，或忘了寫某個遵循，金鑰仍然只會顯示成遮蔽文字
package struct LKAIAPIKey: Sendable {

    // MARK: - Properties

    /// 建立時的原始金鑰，只給三種用途讀取：組 HTTP 請求（例如放進請求標頭）、把金鑰交給 client，
    /// 以及遮蔽輸出中的金鑰（要認得輸出文字裡的原始金鑰，才能把它換成遮蔽文字）
    package let unredactedValue: String

    // MARK: - Init

    /// 以原始金鑰建立
    ///
    /// - Parameter unredactedValue: App 保管的原始金鑰
    package init(_ unredactedValue: String) {
        self.unredactedValue = unredactedValue
    }
}

// MARK: - CustomDebugStringConvertible

extension LKAIAPIKey: CustomDebugStringConvertible {

    /// 除錯用的描述，內容與 `description` 相同，固定是 `LKAIAPIKey(redacted)`
    package var debugDescription: String {
        description
    }
}

// MARK: - CustomReflectable

extension LKAIAPIKey: CustomReflectable {

    /// `dump(_:)` 與 Mirror 看到的內容，沒有任何子項目，原始值不會被印出來
    package var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}

// MARK: - CustomStringConvertible

extension LKAIAPIKey: CustomStringConvertible {

    /// 描述固定是 `LKAIAPIKey(redacted)`，刻意不含原始值，免得金鑰被寫進 log
    package var description: String {
        "LKAIAPIKey(redacted)"
    }
}
