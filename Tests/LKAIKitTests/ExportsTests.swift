//
//  ExportsTests.swift
//  LKAIKitTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAIKit
import Testing

/// `LKAIKit` 重新匯出 `LKAICore` 與各供應商模組宣告的單元測試，測試檔只 `import LKAIKit` 就能使用這些宣告
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

    // spectra-scenario: anthropic-provider / Create the client through the umbrella module
    /// 驗證只 `import LKAIKit` 就能建立 `LKAnthropicClient`，並存成 `any LKAIChatClientProtocol` 使用
    @Test
    func init_透過LKAIKit建立LKAnthropicClient_可存成共用介面() {
        // Given
        let session = URLSession(configuration: .ephemeral)

        // When
        let client: any LKAIChatClientProtocol = LKAnthropicClient(
            apiKey: "test-key",
            urlSession: session
        )

        // Then
        #expect(client is LKAnthropicClient)
    }
}
