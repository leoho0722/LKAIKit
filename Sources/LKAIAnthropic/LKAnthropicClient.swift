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

    /// 交由串流的背景 task 檢查請求、送出到 Messages API，並把回應的 SSE 事件對應成串流事件交出
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 請求或備援設定不合法時，迭代串流會以 `invalidRequest` 失敗，而且不送出網路請求
    /// - Note: 釋放串流才會取消請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
    public func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
        LKAIChatStream { yield throws(LKAIError) in
            try await run(request, yield: yield)
        }
    }
}

// MARK: - Private Method

private extension LKAnthropicClient {

    /// 依序檢查請求與備援設定、送出請求，再把回應的事件交給串流；任何一步失敗就丟出對應的 `LKAIError`
    ///
    /// - Parameters:
    ///   - request: 要送出的對話請求
    ///   - yield: 交出事件的 closure，對應好的事件從這裡交出
    /// - Throws: 請求或備援設定不合法丟 `invalidRequest`；不是 2xx 的狀態碼依錯誤內容分類；事件讀取失敗丟對應的錯誤
    /// - Note: 狀態碼不是 2xx 時先讀完錯誤內容，再依錯誤內容的 `error.type` 分類，解析不了時改用預設分類
    func run(
        _ request: LKAIChatRequest,
        yield: (LKAIChatStreamEvent) -> Void
    ) async throws(LKAIError) {
        try request.validate()
        try refusalFallback.validate()
        let urlRequest = try makeURLRequest(for: request)
        let response = try await httpClient.fetch(urlRequest)
        if !(200...299).contains(response.statusCode) {
            let error = try await httpError(for: response)
            throw error
        }
        try await relayEvents(from: response.lines, yield: yield)
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

    /// 讀完非 2xx 回應的錯誤內容，依 Anthropic 的 `error.type` 分類；內容解析不了或類型不認得時，改用預設分類
    ///
    /// - Parameter response: 狀態碼不是 2xx 的回應
    /// - Returns: 要丟出的錯誤
    /// - Throws: 讀取錯誤內容失敗時丟出，例如連線中斷
    func httpError(for response: LKAIHTTPResponse) async throws(LKAIError) -> LKAIError {
        let text = try await response.readErrorBody()
        let retryAfter = response.headers["retry-after"]
        let mapped = LKAnthropicErrorBody(text: text)?.error.lkaiError(
            statusCode: response.statusCode,
            retryAfter: retryAfter
        )
        return mapped ?? LKAIError(httpStatusCode: response.statusCode, retryAfter: retryAfter)
    }

    /// 逐行讀取回應，組成 SSE 事件、解碼並對應成串流事件，交給串流；收到 `message_stop` 就交出結束事件並停止讀取
    ///
    /// - Parameters:
    ///   - lines: 回應內容逐行交出的序列
    ///   - yield: 交出事件的 closure，文字片段與結束事件從這裡交出
    /// - Throws: 事件解碼失敗、`error` 事件，或結束原因不正常時丟對應的錯誤；讀完沒有 `message_stop` 丟 `invalidResponse`
    /// - Note: 結束事件之後不再讀取，呼叫端離開後回應被釋放，底層傳輸跟著取消
    func relayEvents(
        from lines: LKAIHTTPLines,
        yield: (LKAIChatStreamEvent) -> Void
    ) async throws(LKAIError) {
        var parser = LKAIServerSentEventParser()
        var state = LKAnthropicStreamState()
        for try await line in lines {
            guard let serverSentEvent = parser.parse(line: line) else {
                continue
            }
            let event = try decodeEvent(from: serverSentEvent)
            if case .error(let body) = event {
                // 已交出的文字片段保留，然後丟出對應的錯誤；類型不認得時依規格以 500 處理
                throw body.error.lkaiError(statusCode: nil, retryAfter: nil)
                    ?? .serviceUnavailable(statusCode: 500)
            }
            if case .messageStop = event {
                let completion = try state.makeCompletion()
                yield(.finished(completion))
                return
            }
            if let text = state.apply(event) {
                yield(.textDelta(text))
            }
        }
        parser.finish()
        throw .invalidResponse(reason: "Stream ended before message_stop")
    }

    /// 把 SSE 事件的 `data` 解碼成 Anthropic 的串流事件
    ///
    /// - Parameter serverSentEvent: 解析好的 SSE 事件，事件種類以 `data` 裡的 `type` 為準，不看事件名稱
    /// - Returns: 解碼出的串流事件；不認得的類型是略過
    /// - Throws: `data` 不是合法的 JSON，或認得的類型欄位格式不符時丟出 `invalidResponse`
    func decodeEvent(
        from serverSentEvent: LKAIServerSentEvent
    ) throws(LKAIError) -> LKAnthropicStreamEvent {
        do {
            return try LKAnthropicStreamEvent(data: serverSentEvent.data)
        } catch {
            throw .invalidResponse(reason: "Malformed stream event: \(error)")
        }
    }
}
