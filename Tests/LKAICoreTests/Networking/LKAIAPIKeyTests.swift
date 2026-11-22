//
//  LKAIAPIKeyTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Testing

@testable import LKAICore

/// `LKAIAPIKey` 的單元測試：各種輸出方式都遮蔽金鑰，只有 `unredactedValue` 交出原始值
///
/// - Note: 所有檢查放在同一個參數化測試，每一列是一種輸出方式
struct LKAIAPIKeyTests {

    /// 驗證金鑰直接輸出，或放進不寫任何描述遵循的 struct 再輸出時，文字都不含原始值，
    /// 而且直接以 `String(describing:)`、`String(reflecting:)` 輸出的就是 `LKAIAPIKey(redacted)`；
    /// 只有讀 `unredactedValue` 才拿得到建立時的值
    ///
    /// - Parameter row: 這一列要檢查的輸出方式
    /// - Note: `unredactedValue` 那一列是回歸保護，確認遮蔽沒有影響真正組請求時要用的原始值
    @Test(arguments: Row.allCases)
    func redaction_各種輸出方式_只有unredactedValue交出原始值(row: Row) {
        // Given
        let secret = "sk-test-secret-key-123"
        let key = LKAIAPIKey(secret)
        let expectedText = row.expectedText(secret: secret)

        // When
        let text = row.makeText(for: key)

        // Then
        #expect(text.contains(secret) == row.revealsSecret)
        if let expectedText {
            #expect(text == expectedText)
        }
    }
}

// MARK: - Nested Types

extension LKAIAPIKeyTests {

    /// 參數化測試的一列：一種輸出方式，以及這種輸出方式預期的結果
    enum Row: CaseIterable, Sendable {

        /// 以 `String(describing:)` 輸出金鑰本身
        case describing

        /// 以 `String(reflecting:)` 輸出金鑰本身
        case reflecting

        /// 以 `dump(_:to:)` 寫出金鑰本身
        case dumping

        /// 以 `String(describing:)` 輸出不寫任何描述遵循、只有金鑰欄位的 struct
        case holderDescribing

        /// 以 `String(reflecting:)` 輸出不寫任何描述遵循、只有金鑰欄位的 struct
        case holderReflecting

        /// 以 `dump(_:to:)` 寫出不寫任何描述遵循、只有金鑰欄位的 struct
        case holderDumping

        /// 直接讀 `unredactedValue`，原始值要原樣交出
        case unredactedValue

        /// 這一列產生的文字是否應該含有原始值，只有直接讀 `unredactedValue` 的那一列才是
        var revealsSecret: Bool {
            self == .unredactedValue
        }

        /// 這一列預期的完整文字，期望值寫成字面值，不呼叫受測程式算出來
        ///
        /// - Parameter secret: 測試用的假金鑰原始值
        /// - Returns: 預期的完整文字；只需要確認不含原始值的列回傳 nil
        func expectedText(secret: String) -> String? {
            switch self {
            case .describing, .reflecting:
                "LKAIAPIKey(redacted)"

            case .dumping, .holderDescribing, .holderReflecting, .holderDumping:
                nil

            case .unredactedValue:
                secret
            }
        }

        /// 以這一列的輸出方式，產生要檢查的文字
        ///
        /// - Parameter key: 測試用的金鑰
        /// - Returns: 這種輸出方式對 `key` 產生的文字
        func makeText(for key: LKAIAPIKey) -> String {
            switch self {
            case .describing:
                String(describing: key)

            case .reflecting:
                String(reflecting: key)

            case .dumping:
                dumpedText(of: key)

            case .holderDescribing:
                String(describing: UndescribedHolder(key: key))

            case .holderReflecting:
                String(reflecting: UndescribedHolder(key: key))

            case .holderDumping:
                dumpedText(of: UndescribedHolder(key: key))

            case .unredactedValue:
                key.unredactedValue
            }
        }

        /// 以 `dump(_:to:)` 把值的內容寫成文字
        ///
        /// - Parameter value: 要寫出內容的值
        /// - Returns: `dump(_:to:)` 寫出的文字
        private func dumpedText(of value: some Any) -> String {
            var text = ""
            dump(value, to: &text)
            return text
        }
    }

    /// 不寫任何描述遵循、只有一個金鑰欄位的 struct，用來確認金鑰包在這種型別裡也不會被印出來
    ///
    /// - Note: 固定討論時以 Swift 6.4.2 做的實測：型別本身沒有遮蔽，金鑰仍然只顯示成遮蔽文字
    private struct UndescribedHolder {

        /// 被包著的金鑰
        let key: LKAIAPIKey
    }
}
