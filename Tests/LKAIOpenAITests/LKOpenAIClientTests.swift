//
//  LKOpenAIClientTests.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAICore
import LKAITestSupport
import Testing

@testable import LKAIOpenAI

/// `LKOpenAIClient` 的單元測試，以 `LKAIMockHTTPClient` 記錄送出的請求，不連網
struct LKOpenAIClientTests {

    // spectra-scenario: openai-provider / Send a request with a system prompt
    /// 驗證送出有系統指示的請求時，串流與非串流呼叫記錄到的都是對 Responses API 的 POST，帶齊金鑰與內容類型標頭，內容與規格一致
    ///
    /// - Parameter mode: 呼叫方式，串流或非串流
    /// - Note: 內容以 JSON 值比對，不在意鍵的順序
    /// - Note: `NSDictionary` 比對會把 `1` 當成 `true`，
    ///   所以 `stream` 與 `store` 另外用 `JSONDecoder` 確認是 JSON 布林
    @Test(.timeLimit(.minutes(1)), arguments: LKAIChatClientProtocolTestSupport.CallMode.allCases)
    func stream與invoke_有系統指示的請求_送出符合ResponsesAPI的POST請求(
        mode: LKAIChatClientProtocolTestSupport.CallMode
    ) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKOpenAIClient(apiKey: "test-key", httpClient: mock)
        let request = LKAIChatRequest(
            model: "gpt-6-luna",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            systemPrompt: "Be brief.",
            maxOutputTokens: 1024
        )
        let expectedBody = try LKAITestJSON.jsonObject(from: #"{"model":"gpt-6-luna","instructions":"Be brief.","input":[{"role":"user","content":"Hi"}],"max_output_tokens":1024,"stream":true,"store":false}"#)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: mode
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedData = try #require(recorded.httpBody)
        let recordedBody = try LKAITestJSON.jsonObject(from: recordedData)
        let recordedStreamFlag = try LKAITestJSON.booleanField("stream", in: recordedData)
        let recordedStoreFlag = try LKAITestJSON.booleanField("store", in: recordedData)
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(recorded.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(recorded.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(recordedBody == expectedBody)
        #expect(recordedStreamFlag)
        #expect(!recordedStoreFlag)
    }

    // spectra-scenario: openai-provider / Omit the instructions field without a system prompt
    /// 驗證請求沒有系統指示時，送出的內容沒有 `instructions` 這個鍵
    @Test(.timeLimit(.minutes(1)))
    func stream_沒有系統指示的請求_內容沒有instructions鍵() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKOpenAIClient(apiKey: "test-key", httpClient: mock)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKOpenAIClientTestSupport.validRequest,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try LKAITestJSON.jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody["instructions"] == nil)
    }

    // spectra-scenario: openai-provider / Send the conversation in order
    /// 驗證有多則訊息時，`input` 依序放入每一則的角色與文字，使用者與助理的角色都照原樣對應
    @Test(.timeLimit(.minutes(1)))
    func stream_多則訊息_input依序放入各則的角色與文字() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKOpenAIClient(apiKey: "test-key", httpClient: mock)
        let request = LKAIChatRequest(
            model: "gpt-6-luna",
            messages: [
                LKAIMessage(role: .user, text: "Hi"),
                LKAIMessage(role: .assistant, text: "Hello!"),
                LKAIMessage(role: .user, text: "How are you?"),
            ],
            maxOutputTokens: 1024
        )
        let expectedInput = try LKAITestJSON.jsonFragment(from: #"[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello!"},{"role":"user","content":"How are you?"}]"#)

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try LKAITestJSON.jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody["input"] as? NSObject == expectedInput)
    }

    // spectra-scenario: openai-provider / Send a maximum below the documented minimum unchanged
    /// 驗證輸出上限小於 API 文件的最小值 16 時，請求照原樣送出 `max_output_tokens`，不調整也不在送出前擋下
    @Test(.timeLimit(.minutes(1)))
    func stream_輸出上限低於文件最小值_max_output_tokens照原樣送出() async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = LKOpenAIClient(apiKey: "test-key", httpClient: mock)
        let request = LKAIChatRequest(
            model: "gpt-6-luna",
            messages: [LKAIMessage(role: .user, text: "Hi")],
            maxOutputTokens: 8
        )

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: request,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedBody = try LKAITestJSON.jsonObject(from: #require(recorded.httpBody))
        #expect(recordedBody["max_output_tokens"] as? Int == 8)
    }

    // spectra-scenario: openai-provider / Send the storage setting
    // spectra-scenario: openai-provider / Send the storage setting / storage settings
    /// 驗證每一種回應保存設定送出預期的 `store` 欄位，沒指定時與關閉相同，都是 `false`
    ///
    /// - Parameter testCase: 一列範例：保存設定（nil 表示建立 client 時沒有指定）與預期的 `store` 欄位
    /// - Note: `store` 另外用 `JSONDecoder` 確認是 JSON 布林，不是 `0` 或 `1`
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            StorageCase(setting: nil, expectedStore: false),
            StorageCase(setting: false, expectedStore: false),
            StorageCase(setting: true, expectedStore: true),
        ] as [StorageCase]
    )
    func stream_各種回應保存設定_送出預期的store欄位(testCase: StorageCase) async throws {
        // Given
        let mock = LKAIMockHTTPClient()
        mock.finish()
        let client = if let setting = testCase.setting {
            LKOpenAIClient(apiKey: "test-key", httpClient: mock, shouldStoreResponses: setting)
        } else {
            LKOpenAIClient(apiKey: "test-key", httpClient: mock)
        }

        // When
        _ = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKOpenAIClientTestSupport.validRequest,
            mode: .stream
        )

        // Then
        let recorded = try #require(mock.requests.first)
        let recordedData = try #require(recorded.httpBody)
        let recordedStoreFlag = try LKAITestJSON.booleanField("store", in: recordedData)
        // 只要求 stream 也是 JSON 布林，它的值由其他測試確認
        _ = try LKAITestJSON.booleanField("stream", in: recordedData)
        #expect(recordedStoreFlag == testCase.expectedStore)
    }

    // spectra-scenario: openai-provider / Create a client from a URL session without a storage setting
    /// 驗證以 API 金鑰與 `URLSession` 建立、沒有指定保存設定的 client，`Mirror` 的 `shouldStoreResponses` 是 `false`
    ///
    /// - Note: 送出請求的測試只能經 `package init` 注入替身，驗不到 `public init` 自己的預設值，所以另外檢查這一條
    @Test
    func init_以URLSession建立且沒有保存設定_Mirror的shouldStoreResponses為false() throws {
        // Given
        let client = LKOpenAIClient(
            apiKey: "test-key",
            urlSession: URLSession(configuration: .ephemeral)
        )

        // When
        let mirror = Mirror(reflecting: client)

        // Then
        let storageChild = mirror.children.first { $0.label == "shouldStoreResponses" }
        let child = try #require(storageChild)
        let storedValue = child.value as? Bool
        #expect(storedValue == false)
    }

    // spectra-scenario: openai-provider / Describe a configured client
    /// 驗證已設定金鑰的 client，用 `String(describing:)`、`String(reflecting:)` 與 `dump(_:)` 產生的文字都不含金鑰
    @Test
    func description_已設定金鑰的client_三種描述都不含金鑰() {
        // Given
        let client = LKOpenAIClient(
            apiKey: "sk-proj-secret-123",
            httpClient: LKAIMockHTTPClient()
        )
        var dumpedText = ""

        // When
        let describedText = String(describing: client)
        let reflectedText = String(reflecting: client)
        dump(client, to: &dumpedText)

        // Then
        #expect(!describedText.contains("sk-proj-secret-123"))
        #expect(!reflectedText.contains("sk-proj-secret-123"))
        #expect(!dumpedText.contains("sk-proj-secret-123"))
    }

    // spectra-scenario: openai-provider / Describe a configured client
    /// 驗證 HTTP 401 回應造成的錯誤，即使 OpenAI 的錯誤訊息帶著金鑰，
    /// 用 `String(describing:)` 與 `String(reflecting:)` 產生的文字都不含金鑰
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
        mock.yield(#"{"error":{"message":"Incorrect API key provided: sk-proj-secret-123.","type":"invalid_request_error","code":"invalid_api_key"}}"#)
        mock.finish()
        let client = LKOpenAIClient(apiKey: "sk-proj-secret-123", httpClient: mock)

        // When
        let actualError = await LKAIChatClientProtocolTestSupport.callError(
            on: client,
            request: LKOpenAIClientTestSupport.validRequest,
            mode: mode
        )

        // Then
        let error = try #require(actualError)
        #expect(!String(describing: error).contains("sk-proj-secret-123"))
        #expect(!String(reflecting: error).contains("sk-proj-secret-123"))
    }
}

// MARK: - Nested Types

extension LKOpenAIClientTests {

    /// 回應保存設定範例表的一列：保存設定，以及預期送出的 `store` 欄位
    struct StorageCase {

        /// 建立 client 時傳入的保存設定；nil 表示沒有指定這個參數，用預設值
        let setting: Bool?

        /// 預期的 `store` 欄位
        let expectedStore: Bool
    }
}
