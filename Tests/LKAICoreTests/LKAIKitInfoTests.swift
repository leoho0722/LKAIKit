//
//  LKAIKitInfoTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIKitInfo` 的單元測試
struct LKAIKitInfoTests {

    /// 驗證套件版本是「主版號.次版號.修訂號」三段數字，各段除了單獨的 0 外不以 0 開頭，也不帶 v 前綴
    @Test
    func version_讀取套件版本_符合三段式版本格式() {
        // Given
        let pattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/

        // When
        let version = LKAIKitInfo.version

        // Then
        #expect(version.wholeMatch(of: pattern) != nil)
    }
}
