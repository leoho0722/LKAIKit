//
//  LKAnthropicClient.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import LKAICore

/// 以 Anthropic Claude 回答對話的 client，App 以 API 金鑰與 `URLSession` 建立，存成 `any LKAIChatClientProtocol` 使用
///
/// - Note: API 金鑰由 App 保管，不會出現在 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡
/// - Note: 端點固定為 Anthropic 官方的 Messages API，`anthropic-version` 固定為 `2026-10-21`
/// - Note: 非串流呼叫也以 `stream: true` 送出，由 `LKAICore` 的預設實作彙整成完整回答
/// - Note: 拒答備援預設關閉，由 App 建立 client 時用 `refusalFallback` 選擇要不要開啟
public struct LKAnthropicClient: Sendable {

    // MARK: - Properties

    /// App 保管的 Anthropic API 金鑰，原始值只在組請求時讀取、放進請求標頭，不出現在任何描述裡
    private let apiKey: LKAIAPIKey

    /// 實際送出請求的 HTTP client，測試時換成不連網的替身；共同流程從這裡取用
    package let httpClient: any LKAIHTTPClientProtocol

    /// 拒答備援設定，預設為關閉
    private let refusalFallback: LKAnthropicRefusalFallback

    // MARK: - Init

    /// 以 API 金鑰與 `URLSession` 建立 client
    ///
    /// - Parameters:
    ///   - apiKey: App 保管的 Anthropic API 金鑰
    ///   - urlSession: 實際送出請求的 `URLSession`，逾時與連線設定由 App 決定
    ///   - refusalFallback: 拒答備援設定，預設為關閉
    public init(
        apiKey: String,
        urlSession: URLSession,
        refusalFallback: LKAnthropicRefusalFallback = .disabled
    ) {
        self.init(
            apiKey: apiKey,
            httpClient: LKAIHTTPClient(session: urlSession),
            refusalFallback: refusalFallback
        )
    }

    /// 以指定的 HTTP client 建立 client，給測試注入不連網的替身
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API 金鑰
    ///   - httpClient: 實際送出請求的 HTTP client
    ///   - refusalFallback: 拒答備援設定，預設為關閉
    package init(
        apiKey: String,
        httpClient: any LKAIHTTPClientProtocol,
        refusalFallback: LKAnthropicRefusalFallback = .disabled
    ) {
        self.apiKey = LKAIAPIKey(apiKey)
        self.httpClient = httpClient
        self.refusalFallback = refusalFallback
    }
}

// MARK: - CustomDebugStringConvertible

extension LKAnthropicClient: CustomDebugStringConvertible {

    /// 除錯用的描述，內容與 `description` 相同，只有型別名與備援設定，沒有金鑰
    public var debugDescription: String {
        description
    }
}

// MARK: - CustomReflectable

extension LKAnthropicClient: CustomReflectable {

    /// `dump(_:)` 與 Mirror 看到的內容，只放備援設定，讓金鑰與 HTTP client 不會被印出來
    public var customMirror: Mirror {
        Mirror(self, children: ["refusalFallback": refusalFallback], displayStyle: .struct)
    }
}

// MARK: - CustomStringConvertible

extension LKAnthropicClient: CustomStringConvertible {

    /// 描述只有型別名與備援設定，刻意不含金鑰，免得 App 記錄 client 時把金鑰寫進 log
    public var description: String {
        "LKAnthropicClient(refusalFallback: \(refusalFallback))"
    }
}

// MARK: - LKAIChatClientProtocol

extension LKAnthropicClient: LKAIChatClientProtocol {

    /// 交給共同流程檢查請求、送出到 Messages API，並把回應的 SSE 事件對應成串流事件交出
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 請求或備援設定不合法時，迭代串流會以 `invalidRequest` 失敗，而且不送出網路請求
    /// - Note: 釋放串流才會取消請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
    public func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
        makeStream(for: request)
    }
}

// MARK: - LKAIServerSentEventChatStreaming

extension LKAnthropicClient: LKAIServerSentEventChatStreaming {

    /// 檢查備援設定，再組出送往 Messages API 的 POST 請求，帶金鑰、版本與內容類型標頭；開啟備援時另帶 beta 標頭
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: POST 請求，內容是 JSON；標頭帶 `x-api-key` 與 `anthropic-version`
    /// - Throws: 備援設定不合法、端點網址無法建立，或請求內容無法編碼時丟出 `invalidRequest`
    /// - Note: 第一行先檢查備援設定，不合法時不組出請求，也就不會送出網路請求
    package func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest {
        try refusalFallback.validate()
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw .invalidRequest(message: "The Anthropic endpoint URL is invalid")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey.unredactedValue, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let betaHeaderValue = refusalFallback.betaHeaderValue {
            urlRequest.setValue(betaHeaderValue, forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try encodeBody(for: request)
        return urlRequest
    }

    /// 依 Anthropic 的 `error.type` 分類非 2xx 的回應；內容解析不了、沒有類型或類型不認得時回傳 nil，改用預設分類
    ///
    /// - Parameters:
    ///   - statusCode: `api_error`、`overloaded_error`、`timeout_error` 以它當 `serviceUnavailable` 的狀態碼
    ///   - headers: 只讀 `retry-after`，用來算限流與三種服務不可用的錯誤的等待時間
    ///   - body: Anthropic 的錯誤 JSON，格式見 `LKAnthropicErrorBody`
    /// - Returns: 對應的錯誤；內容解析不了、沒有類型或類型不認得時為 nil
    /// - Note: `retry-after` 只有 `rate_limit_error`、`api_error`、`overloaded_error` 與
    ///   `timeout_error` 會用到；花費上限用完時是 `quotaExceeded`，不帶等待時間
    package func httpError(statusCode: Int, headers: [String: String], body: String) -> LKAIError? {
        LKAnthropicErrorBody(text: body)?.error.lkaiError(
            statusCode: statusCode,
            retryAfter: headers["retry-after"]
        )
    }

    /// 建立 `LKAnthropicStreamState`，由它累積這條串流的模型、結束原因與用量，`message_stop` 時組出結束事件
    ///
    /// - Returns: 還沒有收到任何事件的 `LKAnthropicStreamState`
    package func makeEventMapper() -> any LKAIServerSentEventMapping {
        LKAnthropicStreamState()
    }
}

// MARK: - Private Method

private extension LKAnthropicClient {

    /// 把對話請求與備援設定編碼成 Messages API 的 JSON 內容
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: JSON 編碼後的內容
    /// - Throws: 編碼失敗時丟出 `invalidRequest`
    func encodeBody(for request: LKAIChatRequest) throws(LKAIError) -> Data {
        let body = LKAnthropicMessagesRequestBody(
            request: request,
            refusalFallback: refusalFallback
        )
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw .invalidRequest(message: "The request body could not be encoded")
        }
    }
}
