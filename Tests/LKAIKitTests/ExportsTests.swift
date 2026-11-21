//
//  ExportsTests.swift
//  LKAIKitTests
//
//  Created by Leo Ho on 2026/11/21.
//

import LKAIKit
import Testing

/// `LKAIKit` 重新匯出 `LKAICore` 宣告的單元測試，測試檔只 `import LKAIKit` 就能使用這些宣告
///
/// - Note: 本檔不得匯入 `LKAICore` 或任何供應商模組，否則測不到漏寫的重新匯出
/// - Note: SwiftPM 不會擋這種匯入，只能靠這個檔案本身維持
struct ExportsTests {

    // spectra-scenario: package-distribution / Use a core declaration through the umbrella module
    // spectra-scenario: package-distribution / Read the package version
    /// 驗證只 `import LKAIKit` 就能讀取 `LKAIKitInfo.version`，且版本號符合三段式格式
    @Test
    func version_透過LKAIKit讀取_符合三段式版本格式() {
        // Given
        let pattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/

        // When
        let version = LKAIKitInfo.version

        // Then
        #expect(version.wholeMatch(of: pattern) != nil)
    }
}
