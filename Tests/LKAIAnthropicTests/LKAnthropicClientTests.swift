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

    // spectra-scenario: anthropic-provider / Send a request with a system prompt
    /// 驗證送出有系統指示的請求時，記錄到的是對 Messages API 的 POST，帶齊金鑰與版本標頭，內容與規格一致
    ///
    /// - Note: 內容以 JSON 值比對，不在意鍵的順序；另外確認沒有 `anthropic-beta` 標頭
    /// - Note: `NSDictionary` 比對會把 `1` 當成 `true`，所以 `stream` 另外用 `JSONDecoder` 確認是 JSON 布林
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
        let expectedBody = try LKAITestJSON.jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"system":"Be brief.","messages":[{"role":"user","content":"Hi"}],"stream":true}"#)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedData = try #require(recorded.httpBody)
        let recordedBody = try LKAITestJSON.jsonObject(from: recordedData)
        let recordedStreamFlag = try LKAITestJSON.booleanField("stream", in: recordedData)
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(recorded.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(recorded.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(recorded.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(recorded.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(recordedBody == expectedBody)
        #expect(recordedStreamFlag)
    }

    /// 驗證非串流呼叫也以 `stream: true` 送出同樣格式的請求，因為非串流由串流彙整
    ///
    /// - Note: `stream` 另外用 `JSONDecoder` 確認是 JSON 布林，不是 `1`
    @Test(.timeLimit(.minutes(1)))
    func invoke_非串流呼叫_同樣以stream為true送出請求() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)
        let expectedBody = try LKAITestJSON.jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"messages":[{"role":"user","content":"Hi"}],"stream":true}"#)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: .invoke
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedData = try #require(recorded.httpBody)
        let recordedBody = try LKAITestJSON.jsonObject(from: recordedData)
        let recordedStreamFlag = try LKAITestJSON.booleanField("stream", in: recordedData)
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(recordedBody == expectedBody)
        #expect(recordedStreamFlag)
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
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try LKAITestJSON.jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody["system"] == nil)
    }

    /// 驗證有多則訊息時，內容依序送出每一則的角色與文字，使用者與助理的角色都照原樣對應
    ///
    /// - Note: `stream` 另外用 `JSONDecoder` 確認是 JSON 布林，不是 `1`
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
        let expectedBody = try LKAITestJSON.jsonObject(from: #"{"model":"claude-opus-5-5","max_tokens":1024,"messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"},{"role":"user","content":"Bye"}],"stream":true}"#)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedData = try #require(recorded.httpBody)
        let recordedBody = try LKAITestJSON.jsonObject(from: recordedData)
        let recordedStreamFlag = try LKAITestJSON.booleanField("stream", in: recordedData)
        #expect(recordedBody == expectedBody)
        #expect(recordedStreamFlag)
    }

    // spectra-scenario: anthropic-provider / Send the fallback setting
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
            .map { try LKAITestJSON.jsonFragment(from: $0) }

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try LKAITestJSON.jsonObject(from: #require(recorded.httpBody))
        let recordedBetaHeader = recorded.value(forHTTPHeaderField: "anthropic-beta")
        #expect(recordedBetaHeader == testCase.expectedBetaHeader)
        #expect(recordedBody["fallbacks"] as? NSObject == expectedFallbacks)
    }

    // spectra-scenario: anthropic-provider / Reject an invalid fallback model list
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
        LKAIChatClientProtocolTestSupport.CallMode.allCases
    )
    func stream與invoke_不合法的備援模型清單_丟出無效請求錯誤且不送出請求(
        setting: LKAnthropicRefusalFallback,
        mode: LKAIChatClientProtocolTestSupport.CallMode
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
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: mode
        )

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

    // spectra-scenario: chat-client / Reject an invalid request before sending
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
        LKAIChatClientProtocolTestSupport.CallMode.allCases
    )
    func stream與invoke_不合法的請求_丟出無效請求錯誤且不送出請求(
        request: LKAIChatRequest,
        mode: LKAIChatClientProtocolTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKAnthropicClient(apiKey: "test-key", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: mode
        )

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
    @Test(.timeLimit(.minutes(1)), arguments: LKAIChatClientProtocolTestSupport.CallMode.allCases)
    func stream與invoke_HTTP401回應_錯誤描述不含金鑰(
        mode: LKAIChatClientProtocolTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient(
            statusCode: 401,
            headers: ["content-type": "application/json"]
        )
        mock.yield(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        mock.finish()
        let client = LKAnthropicClient(apiKey: "sk-ant-secret-123", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKAnthropicClientTestSupport.validRequest,
            mode: mode
        )

        // Then
        let error = try #require(actualError)
        #expect(!String(describing: error).contains("sk-ant-secret-123"))
        #expect(!String(reflecting: error).contains("sk-ant-secret-123"))
    }
}

// MARK: - Nested Types

extension LKAnthropicClientTests {

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
