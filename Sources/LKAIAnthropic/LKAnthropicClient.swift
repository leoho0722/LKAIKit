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

    /// App 保管的 Anthropic API 金鑰，只放進請求標頭，不出現在任何描述裡
    private let apiKey: String

    /// 實際送出請求的 HTTP client，測試時換成不連網的替身
    private let httpClient: any LKAIHTTPClientProtocol

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
        self.apiKey = apiKey
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

    /// 在背景 task 內檢查請求、送出到 Messages API 並讀取回應，結果以串流交出
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 請求或備援設定不合法時，迭代串流會以 `invalidRequest` 失敗，而且不送出網路請求
    /// - Note: 每次呼叫建立一個非結構化的 `Task` 執行請求，偏離 ios-dev-kit「`Task { }` 只在兩個地方建立」
    /// - Note: 理由：函式庫沒有 View 或 ViewModel，要把非同步的生產端接到 `AsyncSequence` 只能這樣做
    /// - Note: 以「每條串流一個 task、只由 `onTermination` 取消、不存進任何屬性」限制它的生命週期
    /// - Note: 釋放串流才會取消請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
    public func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
        let source = AsyncThrowingStream<LKAIChatStreamEvent, any Error> { continuation in
            let streamingTask = Task {
                do {
                    try await run(request)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                streamingTask.cancel()
            }
        }
        return LKAIChatStream(source)
    }
}

// MARK: - Private Method

private extension LKAnthropicClient {

    /// 依序檢查請求與備援設定、送出請求，再讀取回應；任何一步失敗就丟出對應的 `LKAIError`
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Throws: 請求或備援設定不合法丟 `invalidRequest`；不是 2xx 的狀態碼依預設分類；沒有收到結束事件就結束丟 `invalidResponse`
    /// - Note: 狀態碼不是 2xx 時先讀完錯誤內容，再依狀態碼分類
    /// - Note: 回應的逐行內容還沒有對應成事件，目前只讀到結束
    func run(_ request: LKAIChatRequest) async throws(LKAIError) {
        try request.validate()
        try refusalFallback.validate()
        let urlRequest = try makeURLRequest(for: request)
        let response = try await httpClient.fetch(urlRequest)
        if !(200...299).contains(response.statusCode) {
            _ = try await response.readErrorBody()
            throw LKAIError(
                httpStatusCode: response.statusCode,
                retryAfter: response.headers["retry-after"]
            )
        }
        for try await _ in response.lines {
            // 逐行內容還沒有對應成事件，先讀到結束
        }
        throw .invalidResponse(reason: "Stream ended before message_stop")
    }

    /// 組出送往 Messages API 的 POST 請求，帶金鑰、版本與內容類型標頭；開啟備援時另帶 beta 標頭
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 可以交給 HTTP client 的請求
    /// - Throws: 端點網址無法建立，或請求內容無法編碼時丟出 `invalidRequest`
    func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw .invalidRequest(message: "The Anthropic endpoint URL is invalid")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let betaHeaderValue = refusalFallback.betaHeaderValue {
            urlRequest.setValue(betaHeaderValue, forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try encodeBody(for: request)
        return urlRequest
    }

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
