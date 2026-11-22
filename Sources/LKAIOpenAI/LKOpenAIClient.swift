//
//  LKOpenAIClient.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAICore

/// 以 OpenAI 模型回答對話的 client，App 以 API 金鑰與 `URLSession` 建立，存成 `any LKAIChatClientProtocol` 使用
///
/// - Note: API 金鑰由 App 保管，不會出現在 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡
/// - Note: 端點固定為 OpenAI 官方的 Responses API
/// - Note: 非串流呼叫也以 `stream: true` 送出，由 `LKAICore` 的預設實作彙整成完整回答
/// - Note: 回應保存預設關閉，由 App 建立 client 時用 `shouldStoreResponses` 開啟
/// - Note: `refused` 的 detail 可能是模型寫的拒答文字，可能引用使用者的內容，記錄 log 時留意
public struct LKOpenAIClient: Sendable {

    // MARK: - Properties

    /// App 保管的 OpenAI API 金鑰，只放進請求標頭，不出現在任何描述裡
    private let apiKey: String

    /// 實際送出請求的 HTTP client，測試時換成不連網的替身；共同流程從這裡取用
    package let httpClient: any LKAIHTTPClientProtocol

    /// 是否讓 OpenAI 保存回應，預設為 false
    private let shouldStoreResponses: Bool

    // MARK: - Init

    /// 以 API 金鑰與 `URLSession` 建立 client
    ///
    /// - Parameters:
    ///   - apiKey: App 保管的 OpenAI API 金鑰
    ///   - urlSession: 實際送出請求的 `URLSession`，逾時與連線設定由 App 決定
    ///   - shouldStoreResponses: 是否讓 OpenAI 保存回應，預設為不保存
    public init(
        apiKey: String,
        urlSession: URLSession,
        shouldStoreResponses: Bool = false
    ) {
        self.init(
            apiKey: apiKey,
            httpClient: LKAIHTTPClient(session: urlSession),
            shouldStoreResponses: shouldStoreResponses
        )
    }

    /// 以指定的 HTTP client 建立 client，給測試注入不連網的替身
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API 金鑰
    ///   - httpClient: 實際送出請求的 HTTP client
    ///   - shouldStoreResponses: 是否讓 OpenAI 保存回應，預設為不保存
    package init(
        apiKey: String,
        httpClient: any LKAIHTTPClientProtocol,
        shouldStoreResponses: Bool = false
    ) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.shouldStoreResponses = shouldStoreResponses
    }
}

// MARK: - CustomDebugStringConvertible

extension LKOpenAIClient: CustomDebugStringConvertible {

    /// 除錯用的描述，內容與 `description` 相同，只有型別名與保存設定，沒有金鑰
    public var debugDescription: String {
        description
    }
}

// MARK: - CustomReflectable

extension LKOpenAIClient: CustomReflectable {

    /// `dump(_:)` 與 Mirror 看到的內容，只放保存設定，讓金鑰與 HTTP client 不會被印出來
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["shouldStoreResponses": shouldStoreResponses],
            displayStyle: .struct
        )
    }
}

// MARK: - CustomStringConvertible

extension LKOpenAIClient: CustomStringConvertible {

    /// 描述只有型別名與保存設定，刻意不含金鑰，免得 App 記錄 client 時把金鑰寫進 log
    public var description: String {
        "LKOpenAIClient(shouldStoreResponses: \(shouldStoreResponses))"
    }
}

// MARK: - LKAIChatClientProtocol

extension LKOpenAIClient: LKAIChatClientProtocol {

    /// 交給共同流程檢查請求、送出到 Responses API，並把回應的 SSE 事件對應成串流事件交出
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 請求不合法時，迭代串流會以 `invalidRequest` 失敗，而且不送出網路請求
    /// - Note: 釋放串流才會取消請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
    public func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
        makeStream(for: request)
    }
}

// MARK: - LKAIServerSentEventChatStreaming

extension LKOpenAIClient: LKAIServerSentEventChatStreaming {

    /// 組出送往 Responses API 的 POST 請求，帶金鑰與內容類型標頭
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: POST 請求，內容是 JSON；標頭帶 `Authorization` 與 `content-type`
    /// - Throws: 端點網址無法建立，或請求內容無法編碼時丟出 `invalidRequest`
    /// - Note: 輸出上限照原樣送出，小於 API 文件的最小值 16 時由 API 拒絕，這裡不檢查也不調整
    package func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw .invalidRequest(message: "The OpenAI endpoint URL is invalid")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try encodeBody(for: request)
        return urlRequest
    }

    /// 不分類非 2xx 的回應，一律回傳 nil，交給共同流程套用預設的狀態碼分類
    ///
    /// - Parameters:
    ///   - statusCode: 回應的 HTTP 狀態碼，這裡不使用
    ///   - headers: 回應標頭，這裡不使用
    ///   - body: 已讀完的錯誤內容，這裡不使用
    /// - Returns: 一律為 nil
    package func httpError(statusCode: Int, headers: [String: String], body: String) -> LKAIError? {
        nil
    }

    /// 建立 `LKOpenAIStreamState`，由它處理這條串流的 SSE 事件
    ///
    /// - Returns: 還沒有收到任何事件的 `LKOpenAIStreamState`
    package func makeEventMapper() -> any LKAIServerSentEventMapping {
        LKOpenAIStreamState()
    }
}

// MARK: - Private Method

private extension LKOpenAIClient {

    /// 把對話請求與保存設定編碼成 Responses API 的 JSON 內容
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: JSON 編碼後的內容
    /// - Throws: 編碼失敗時丟出 `invalidRequest`
    func encodeBody(for request: LKAIChatRequest) throws(LKAIError) -> Data {
        let body = LKOpenAIResponsesRequestBody(
            request: request,
            shouldStoreResponses: shouldStoreResponses
        )
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw .invalidRequest(message: "The request body could not be encoded")
        }
    }
}
