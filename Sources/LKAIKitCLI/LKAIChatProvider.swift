//
//  LKAIChatProvider.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit

/// `--provider` 可以選的 AI 服務，負責「供應商 → 讀取金鑰的環境變數與 client」的對應
///
/// - Note: 新增供應商時，程式只改這個型別：加 case，並補上環境變數名稱與建立 client 的對應
/// - Note: 不依賴 ArgumentParser，與命令列解析的對接只寫在 `LKAICommand.swift`
enum LKAIChatProvider: String, CaseIterable, Sendable {

    /// Anthropic；`--provider` 的值是 `anthropic`
    case anthropic

    /// OpenAI；`--provider` 的值是 `openai`
    case openai

    /// Google Gemini；`--provider` 的值是 `google`
    case google
}

// MARK: - Computed Properties

extension LKAIChatProvider {

    /// 讀取這個供應商 API 金鑰的環境變數名稱，沒有給 `--apiKey` 時使用
    ///
    /// - Note: 名稱和各家實際 API 測試用的相同，owner 不必為 `lkai` 另外設定環境變數
    var apiKeyEnvironmentName: String {
        switch self {
        case .anthropic:
            "LKAI_ANTHROPIC_API_KEY"

        case .openai:
            "LKAI_OPENAI_API_KEY"

        case .google:
            "LKAI_GEMINI_API_KEY"
        }
    }
}

// MARK: - Internal Method

extension LKAIChatProvider {

    /// 以預設設定建立這個供應商的 client
    ///
    /// - Parameters:
    ///   - apiKey: API 金鑰的原始值
    ///   - urlSession: 實際送出請求的 `URLSession`，逾時與連線設定由呼叫端決定
    /// - Returns: 對應供應商的 client；除了金鑰與 `URLSession`，其他設定都用預設值：
    ///   Anthropic 不開拒答備援，OpenAI 與 Gemini 不保存回應
    func makeClient(apiKey: String, urlSession: URLSession) -> any LKAIChatClientProtocol {
        switch self {
        case .anthropic:
            LKAnthropicClient(apiKey: apiKey, urlSession: urlSession)

        case .openai:
            LKOpenAIClient(apiKey: apiKey, urlSession: urlSession)

        case .google:
            LKGeminiClient(apiKey: apiKey, urlSession: urlSession)
        }
    }
}
