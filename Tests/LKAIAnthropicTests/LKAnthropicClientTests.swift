//
//  LKAnthropicClientTests.swift
//  LKAIAnthropicTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIAnthropic

/// `LKAnthropicClient` 的單元測試，以 `LKAIMockHTTPClient` 記錄送出的請求，不連網
struct LKAnthropicClientTests {

    // MARK: - Properties

    /// 多個測試共用的合法請求：模型、一則使用者訊息與輸出上限，沒有系統指示
    private let validRequest = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )

    // spectra-scenario: anthropic-provider / Send a request with a system prompt
    /// 驗證送出有系統指示的請求時，記錄到的是對 Messages API 的 POST，帶齊金鑰與版本標頭，內容與規格一致
    ///
    /// - Note: 內容以 JSON 值比對，不在意鍵的順序；另外確認沒有 `anthropic-beta` 標頭
    @Test(.timeLimit(.minutes(1)))
    func stream_有系統指示的請求_送出符合MessagesAPI的POST請求() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            systemPrompt: "Be brief.",
            maxOutputTokens: 1024
        )
        let expectedBody = try jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"system":"Be brief.","messages":[{"role":"user","content":"Hi"}],"stream":true}"#)

        // When
        _ = await callError(on: client, with: request, mode: .stream)

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try jsonObject(from: #require(recorded.httpBody))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(recorded.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(recorded.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(recorded.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(recorded.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(recordedBody == expectedBody)
    }

    /// 驗證非串流呼叫也以 `stream: true` 送出同樣格式的請求，因為非串流由串流彙整
    @Test(.timeLimit(.minutes(1)))
    func invoke_非串流呼叫_同樣以stream為true送出請求() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedBody = try jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"messages":[{"role":"user","content":"Hi"}],"stream":true}"#)

        // When
        _ = await callError(on: client, with: validRequest, mode: .invoke)

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try jsonObject(from: #require(recorded.httpBody))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(recordedBody == expectedBody)
    }

    // spectra-scenario: anthropic-provider / Omit the system field without a system prompt
    /// 驗證請求沒有系統指示時，送出的內容沒有 `system` 這個鍵
    @Test(.timeLimit(.minutes(1)))
    func stream_沒有系統指示的請求_內容沒有system鍵() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        _ = await callError(on: client, with: validRequest, mode: .stream)

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody["system"] == nil)
    }

    /// 驗證有多則訊息時，內容依序送出每一則的角色與文字，使用者與助理的角色都照原樣對應
    @Test(.timeLimit(.minutes(1)))
    func stream_多則訊息_依序送出各則的角色與文字() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let request = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [
                LKAIMessage(role: .user, text: "Hi"),
                LKAIMessage(role: .assistant, text: "Hello"),
                LKAIMessage(role: .user, text: "Bye"),
            ],
            maxOutputTokens: 1024
        )
        let expectedBody = try jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"},{"role":"user","content":"Bye"}],"stream":true}"#)

        // When
        _ = await callError(on: client, with: request, mode: .stream)

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody == expectedBody)
    }

    // spectra-scenario: anthropic-provider / Send the fallback setting / fallback settings
    /// 驗證每一種備援設定送出預期的 `anthropic-beta` 標頭與 `fallbacks` 欄位，沒開啟時兩者都不送
    ///
    /// - Parameter testCase: 一列範例：備援設定（nil 表示建立 client 時沒有指定）與預期的標頭、欄位
    /// - Note: 範例表之外多加「剛好 3 個模型」一列，確認 3 個是合法的上限
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            FallbackCase(setting: nil, expectedBetaHeader: nil, expectedFallbacksJSON: nil),
            FallbackCase(setting: .disabled, expectedBetaHeader: nil, expectedFallbacksJSON: nil),
            FallbackCase(
                setting: .automatic,
                expectedBetaHeader: "server-side-fallback-2026-07-01",
                expectedFallbacksJSON: #""default""#
            ),
            FallbackCase(
                setting: .models(["claude-opus-4-8"]),
                expectedBetaHeader: "server-side-fallback-2026-07-01",
                expectedFallbacksJSON: #"[{"model":"claude-opus-4-8"}]"#
            ),
            FallbackCase(
                setting: .models(["claude-opus-4-8", "claude-opus-5"]),
                expectedBetaHeader: "server-side-fallback-2026-07-01",
                expectedFallbacksJSON: #"[{"model":"claude-opus-4-8"},{"model":"claude-opus-5"}]"#
            ),
            FallbackCase(
                setting: .models(["a", "b", "c"]),
                expectedBetaHeader: "server-side-fallback-2026-07-01",
                expectedFallbacksJSON: #"[{"model":"a"},{"model":"b"},{"model":"c"}]"#
            ),
        ] as [FallbackCase]
    )
    func stream_各種備援設定_送出預期的標頭與fallbacks欄位(testCase: FallbackCase) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = if let setting = testCase.setting {
            LKAnthropicClient(apiKey: "test-key", httpClient: mock, refusalFallback: setting)
        } else {
            LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        }
        let expectedFallbacks = try testCase.expectedFallbacksJSON
            .map { try jsonFragment(from: $0) }

        // When
        _ = await callError(on: client, with: validRequest, mode: .stream)

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try jsonObject(from: #require(recorded.httpBody))
        let recordedBetaHeader = recorded.value(forHTTPHeaderField: "anthropic-beta")
        #expect(recordedBetaHeader == testCase.expectedBetaHeader)
        #expect(recordedBody["fallbacks"] as? NSObject == expectedFallbacks)
    }

    // spectra-scenario: anthropic-provider / Reject an invalid fallback model list / invalid fallback model lists
    /// 驗證指定的備援模型清單違反規則時，串流與非串流呼叫都丟出無效請求錯誤，而且沒有送出任何請求
    ///
    /// - Parameters:
    ///   - setting: 違反規則的備援設定：空清單、超過 3 個、重複、含空字串
    ///   - mode: 呼叫方式，串流或非串流
    /// - Note: 只比對是不是無效請求，不比對訊息文字，規格沒有規定它
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            .models([]),
            .models(["a", "b", "c", "d"]),
            .models(["claude-opus-4-8", "claude-opus-4-8"]),
            .models([""]),
        ] as [LKAnthropicRefusalFallback],
        CallMode.allCases
    )
    func stream與invoke_不合法的備援模型清單_丟出無效請求錯誤且不送出請求(
        setting: LKAnthropicRefusalFallback,
        mode: CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(
            apiKey: "test-key",
            httpClient: mock,
            refusalFallback: setting
        )

        // When
        let actualError = await callError(on: client, with: validRequest, mode: mode)

        // Then
        let error = try #require(actualError)
        let isInvalidRequest = if case .invalidRequest = error {
            true
        } else {
            false
        }
        #expect(isInvalidRequest)
        #expect(mock.requests.isEmpty)
    }

    // spectra-scenario: chat-client / Reject an invalid request before sending / invalid requests
    /// 驗證模型為空、沒有訊息，或輸出上限小於 1 的請求，串流與非串流呼叫都丟出無效請求錯誤，而且沒有送出任何請求
    ///
    /// - Parameters:
    ///   - request: 違反規則的請求，三列分別是模型為空字串、沒有訊息、輸出上限為 0
    ///   - mode: 呼叫方式，串流或非串流
    /// - Note: 只比對是不是無效請求，不比對訊息文字，規格沒有規定它
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            LKAIChatRequest(
                model: "",
                messages: [LKAIMessage(role: .user, text: "Hi")],
                maxOutputTokens: 1024
            ),
            LKAIChatRequest(model: "claude-opus-5-5", messages: [], maxOutputTokens: 1024),
            LKAIChatRequest(
                model: "claude-opus-5-5",
                messages: [LKAIMessage(role: .user, text: "Hi")],
                maxOutputTokens: 0
            ),
        ] as [LKAIChatRequest],
        CallMode.allCases
    )
    func stream與invoke_不合法的請求_丟出無效請求錯誤且不送出請求(
        request: LKAIChatRequest,
        mode: CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await callError(on: client, with: request, mode: mode)

        // Then
        let error = try #require(actualError)
        let isInvalidRequest = if case .invalidRequest = error {
            true
        } else {
            false
        }
        #expect(isInvalidRequest)
        #expect(mock.requests.isEmpty)
    }

    // spectra-scenario: anthropic-provider / Describe a configured client
    /// 驗證已設定金鑰的 client，用 `String(describing:)`、`String(reflecting:)` 與 `dump(_:)` 產生的文字都不含金鑰
    @Test
    func description_已設定金鑰的client_三種描述都不含金鑰() {
        // Given
        let client = LKAnthropicClient(
            apiKey: "sk-ant-secret-123",
            httpClient: LKAIMockHTTPClient()
        )
        var dumpedText = ""

        // When
        let describedText = String(describing: client)
        let reflectedText = String(reflecting: client)
        dump(client, to: &dumpedText)

        // Then
        #expect(!describedText.contains("sk-ant-secret-123"))
        #expect(!reflectedText.contains("sk-ant-secret-123"))
        #expect(!dumpedText.contains("sk-ant-secret-123"))
    }

    // spectra-scenario: anthropic-provider / Describe a configured client
    /// 驗證 HTTP 401 回應造成的錯誤，用 `String(describing:)` 與 `String(reflecting:)` 產生的文字都不含金鑰
    ///
    /// - Parameter mode: 呼叫方式，串流或非串流
    /// - Note: 只檢查描述不含金鑰，不比對是哪一種錯誤，錯誤的分類由供應商的錯誤對應決定
    @Test(.timeLimit(.minutes(1)), arguments: CallMode.allCases)
    func stream與invoke_HTTP401回應_錯誤描述不含金鑰(mode: CallMode) async throws {
        // Given
        let mock = LKAIMockHTTPClient(
            statusCode: 401,
            headers: ["content-type": "application/json"]
        )
        mock.yield(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        mock.finish()
        let client = LKAnthropicClient(apiKey: "sk-ant-secret-123", httpClient: mock)

        // When
        let actualError = await callError(on: client, with: validRequest, mode: mode)

        // Then
        let error = try #require(actualError)
        #expect(!String(describing: error).contains("sk-ant-secret-123"))
        #expect(!String(reflecting: error).contains("sk-ant-secret-123"))
    }
}

// MARK: - Nested Types

extension LKAnthropicClientTests {

    /// 呼叫 client 的方式，串流與非串流走同一套請求檢查與送出流程
    enum CallMode: CaseIterable, Sendable {

        /// 呼叫 `stream(_:)`，迭代串流到結束
        case stream

        /// 呼叫 `invoke(_:)`，等整段回答完成
        case invoke
    }

    /// 備援設定範例表的一列：備援設定，以及預期送出的標頭與欄位
    struct FallbackCase {

        /// 建立 client 時傳入的備援設定；nil 表示沒有指定這個參數，用預設值
        let setting: LKAnthropicRefusalFallback?

        /// 預期的 `anthropic-beta` 標頭；nil 表示不該出現
        let expectedBetaHeader: String?

        /// 預期的 `fallbacks` 欄位，寫成 JSON 文字；nil 表示不該出現
        let expectedFallbacksJSON: String?
    }
}

// MARK: - Private Method

private extension LKAnthropicClientTests {

    /// 把 JSON 文字解析成 JSON 物件，比對時不受鍵的順序影響
    ///
    /// - Parameter text: JSON 文字，最外層必須是物件
    /// - Returns: 解析出的 JSON 物件
    /// - Throws: 文字不是合法的 JSON，或最外層不是物件時丟出
    func jsonObject(from text: String) throws -> NSDictionary {
        try jsonObject(from: Data(text.utf8))
    }

    /// 把 JSON 資料解析成 JSON 物件，比對時不受鍵的順序影響
    ///
    /// - Parameter data: JSON 資料，最外層必須是物件
    /// - Returns: 解析出的 JSON 物件
    /// - Throws: 資料不是合法的 JSON，或最外層不是物件時丟出
    func jsonObject(from data: Data) throws -> NSDictionary {
        let value = try JSONSerialization.jsonObject(with: data)
        return try #require(value as? NSDictionary)
    }

    /// 以指定的方式呼叫 client，迭代或等待到結束，並記下丟出的錯誤
    ///
    /// - Parameters:
    ///   - client: 要呼叫的 client
    ///   - request: 要送出的對話請求
    ///   - mode: 呼叫方式，串流或非串流
    /// - Returns: 呼叫丟出的錯誤；順利結束時為 nil
    func callError(
        on client: LKAnthropicClient,
        with request: LKAIChatRequest,
        mode: CallMode
    ) async -> LKAIError? {
        var actualError: LKAIError?
        do {
            switch mode {
            case .stream:
                for try await _ in client.stream(request) {
                    // 只需要迭代到結束，事件的內容不在這裡檢查
                }

            case .invoke:
                _ = try await client.invoke(request)
            }
        } catch {
            actualError = error
        }
        return actualError
    }

    /// 把 JSON 文字解析成 JSON 值，最外層可以是字串或陣列
    ///
    /// - Parameter text: JSON 文字
    /// - Returns: 解析出的 JSON 值
    /// - Throws: 文字不是合法的 JSON 時丟出
    func jsonFragment(from text: String) throws -> NSObject {
        let value = try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: .fragmentsAllowed
        )
        return try #require(value as? NSObject)
    }
}
