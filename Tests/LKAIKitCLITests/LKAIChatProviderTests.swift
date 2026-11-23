//
//  LKAIChatProviderTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAIChatProvider` 的單元測試：`--provider` 的值、對應的 client，以及讀取金鑰的環境變數名稱
struct LKAIChatProviderTests {

    // spectra-scenario: cli-chat / Map the provider to its client
    // spectra-scenario: cli-chat / Map the provider to its client / provider values
    /// 驗證每個供應商建立出範例表的 client：型別正確，`description` 就是範例表的字串，
    /// 而且不含傳入的金鑰
    ///
    /// - Parameter testCase: 一列範例：供應商、client 型別的判斷，以及 client 的 `description`
    /// - Note: 建立 client 只用 `URLSession(configuration: .ephemeral)`，不會送出請求
    /// - Note: `description` 與範例表逐字相同，所以也確認了 Anthropic 不開拒答備援、
    ///   OpenAI 與 Gemini 不保存回應
    @Test(arguments: [
        ProviderCase(
            provider: .anthropic,
            isExpectedClient: { $0 is LKAnthropicClient },
            expectedDescription: "LKAnthropicClient(refusalFallback: disabled)"
        ),
        ProviderCase(
            provider: .openai,
            isExpectedClient: { $0 is LKOpenAIClient },
            expectedDescription: "LKOpenAIClient(shouldStoreResponses: false)"
        ),
        ProviderCase(
            provider: .google,
            isExpectedClient: { $0 is LKGeminiClient },
            expectedDescription: "LKGeminiClient(shouldStoreResponses: false)"
        ),
    ])
    func makeClient_各供應商_建立範例表的client且描述不含金鑰(testCase: ProviderCase) {
        // Given
        let apiKey = "sk-test-secret-key"
        let urlSession = URLSession(configuration: .ephemeral)

        // When
        let client = testCase.provider.makeClient(apiKey: apiKey, urlSession: urlSession)

        // Then
        let description = String(describing: client)
        #expect(testCase.isExpectedClient(client))
        #expect(description == testCase.expectedDescription)
        #expect(!description.contains(apiKey))
    }

    // spectra-scenario: cli-chat / Read the environment variable of the selected provider
    // spectra-scenario: cli-chat / Read the environment variable of the selected provider / environment variables
    /// 驗證每個供應商讀取金鑰的環境變數名稱，與範例表「environment variables」逐字相同
    ///
    /// - Parameters:
    ///   - provider: 供應商
    ///   - expectedName: 範例表列出的環境變數名稱
    /// - Note: 這裡只測對照表；依供應商讀環境變數的行為由 `LKAIChatInputTests` 測
    @Test(arguments: [
        (.anthropic, "LKAI_ANTHROPIC_API_KEY"),
        (.openai, "LKAI_OPENAI_API_KEY"),
        (.google, "LKAI_GEMINI_API_KEY"),
    ] as [(LKAIChatProvider, String)])
    func apiKeyEnvironmentName_各供應商_是範例表的環境變數名稱(
        provider: LKAIChatProvider,
        expectedName: String
    ) {
        // Given

        // When
        let actualName = provider.apiKeyEnvironmentName

        // Then
        #expect(actualName == expectedName)
    }

    /// 驗證每個供應商讀取金鑰的環境變數名稱，都以 `LKAI_` 開頭、以 `_API_KEY` 結尾
    ///
    /// - Parameter provider: 供應商
    /// - Note: `LKAICommandTestSupport.defaultEnvironment` 以這個樣式移除目前行程環境變數裡的金鑰；
    ///   新供應商的名稱不符時，行程測試會帶著真的金鑰執行，原本應該在檢查階段失敗的情境可能送出真的請求
    @Test(arguments: LKAIChatProvider.allCases)
    func apiKeyEnvironmentName_各供應商_符合行程測試移除金鑰的樣式(provider: LKAIChatProvider) {
        // Given

        // When
        let actualName = provider.apiKeyEnvironmentName

        // Then
        #expect(actualName.hasPrefix("LKAI_"))
        #expect(actualName.hasSuffix("_API_KEY"))
    }

    // spectra-scenario: cli-chat / Map the provider to its client
    // spectra-scenario: cli-chat / Map the provider to its client / provider values
    /// 驗證 `--provider` 的值對應到供應商：`anthropic`、`openai`、`google` 各對應一個，
    /// 其他寫法（含大小寫不同與 `gemini`）都不是供應商
    ///
    /// - Parameter testCase: 一列範例：`--provider` 的值與預期的供應商，不是供應商時為 nil
    /// - Note: 這是回歸防護：`rawValue` 的轉換由編譯器合成，在實作前就會通過
    @Test(arguments: [
        RawValueCase(rawValue: "anthropic", expectedProvider: .anthropic),
        RawValueCase(rawValue: "openai", expectedProvider: .openai),
        RawValueCase(rawValue: "google", expectedProvider: .google),
        RawValueCase(rawValue: "gemini", expectedProvider: nil),
        RawValueCase(rawValue: "OpenAI", expectedProvider: nil),
        RawValueCase(rawValue: "", expectedProvider: nil),
    ])
    func init_rawValue_三個值對應到供應商且其他值為nil(testCase: RawValueCase) {
        // Given

        // When
        let actualProvider = LKAIChatProvider(rawValue: testCase.rawValue)

        // Then
        #expect(actualProvider == testCase.expectedProvider)
    }

    /// 驗證 `allCases` 正好是三個供應商，順序是 `anthropic`、`openai`、`google`
    ///
    /// - Note: 這是回歸防護：`allCases` 由編譯器合成，在實作前就會通過
    /// - Note: 新增供應商時這個測試會失敗，提醒要一併補上環境變數與 client 的對應
    @Test
    func allCases_列出全部供應商_正好是三個且依宣告順序() {
        // Given

        // When
        let actualProviders = LKAIChatProvider.allCases

        // Then
        #expect(actualProviders == [.anthropic, .openai, .google])
    }
}

// MARK: - Nested Types

extension LKAIChatProviderTests {

    /// 建立 client 的一列範例：供應商、client 型別的判斷，以及 client 的 `description`
    struct ProviderCase: Sendable {

        /// 要建立 client 的供應商
        let provider: LKAIChatProvider

        /// 判斷建立出的 client 是不是預期的型別
        let isExpectedClient: @Sendable (any LKAIChatClientProtocol) -> Bool

        /// 預期的 `String(describing:)` 結果
        let expectedDescription: String
    }

    /// `rawValue` 轉換的一列範例：`--provider` 的值，以及預期的供應商
    struct RawValueCase: Sendable {

        /// `--provider` 的值
        let rawValue: String

        /// 預期的供應商；不是供應商時為 nil
        let expectedProvider: LKAIChatProvider?
    }
}
