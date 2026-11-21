//
//  LKAIChatRequestTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIChatRequest` 的單元測試
struct LKAIChatRequestTests {

    // spectra-scenario: chat-client / Reject an invalid request before sending / invalid requests
    /// 驗證規格範例表的三種不合法請求，`validate()` 都丟出 invalidRequest，且訊息不是 nil、含有違反的欄位名稱
    ///
    /// - Parameters:
    ///   - model: 請求的模型識別碼，範例表第一列是空字串
    ///   - messages: 請求的訊息，依序排列，範例表第二列是空陣列
    ///   - maxOutputTokens: 最多輸出的 token 數，範例表第三列是 0
    ///   - expectedFieldName: 訊息應該含有的違反欄位名稱
    @Test(arguments: [
        ("", [LKAIMessage(role: .user, text: "Hi")], 1024, "model"),
        ("claude-opus-5-5", [LKAIMessage](), 1024, "messages"),
        ("claude-opus-5-5", [LKAIMessage(role: .user, text: "Hi")], 0, "maxOutputTokens"),
    ] as [(String, [LKAIMessage], Int, String)])
    func validate_不合法的請求_丟出invalidRequest(
        model: String,
        messages: [LKAIMessage],
        maxOutputTokens: Int,
        expectedFieldName: String
    ) throws {
        // Given
        let request = LKAIChatRequest(
            model: model,
            messages: messages,
            maxOutputTokens: maxOutputTokens
        )
        var actualError: LKAIError?

        // When
        do {
            try request.validate()
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let message: String? = if case .invalidRequest(let text) = error { text } else { nil }
        let unwrappedMessage = try #require(message)
        #expect(unwrappedMessage.contains(expectedFieldName))
    }

    /// 驗證模型、訊息與輸出上限都合法的請求，`validate()` 不丟錯
    @Test
    func validate_合法的請求_不丟錯() {
        // Given
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 1024
        )
        var actualError: LKAIError?

        // When
        do {
            try request.validate()
        } catch {
            actualError = error
        }

        // Then
        #expect(actualError == nil)
    }

    /// 驗證 maxOutputTokens 為 1（最小的合法值）時，`validate()` 不丟錯
    @Test
    func validate_maxOutputTokens為1_不丟錯() {
        // Given
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 1
        )
        var actualError: LKAIError?

        // When
        do {
            try request.validate()
        } catch {
            actualError = error
        }

        // Then
        #expect(actualError == nil)
    }

    /// 驗證 maxOutputTokens 為負數（小於 1）時，`validate()` 丟出 invalidRequest，且訊息不是 nil、含有 maxOutputTokens
    @Test
    func validate_maxOutputTokens為負數_丟出invalidRequest() throws {
        // Given
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: -1
        )
        var actualError: LKAIError?

        // When
        do {
            try request.validate()
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let message: String? = if case .invalidRequest(let text) = error { text } else { nil }
        let unwrappedMessage = try #require(message)
        #expect(unwrappedMessage.contains("maxOutputTokens"))
    }

    /// 驗證帶系統指示的合法請求，`validate()` 不丟錯
    @Test
    func validate_帶系統指示的合法請求_不丟錯() {
        // Given
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            systemPrompt: "Be brief.",
            maxOutputTokens: 1024
        )
        var actualError: LKAIError?

        // When
        do {
            try request.validate()
        } catch {
            actualError = error
        }

        // Then
        #expect(actualError == nil)
    }

    /// 驗證省略 systemPrompt 建立的請求，systemPrompt 為 nil，呼叫端不必另外指定
    @Test
    func init_省略systemPrompt_為nil() {
        // Given
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 1024
        )

        // When
        let systemPrompt = request.systemPrompt

        // Then
        #expect(systemPrompt == nil)
    }
}
