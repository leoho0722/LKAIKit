//
//  LKAIServerSentEventChatStreaming.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation

/// 以 SSE（Server-Sent Events）串流回答的供應商共用的流程：驗證請求、送出、分類錯誤回應，再把 SSE 事件對應成對話事件交出
///
/// - Note: 供應商只提供下面四個要求，共同流程由 `makeStream(for:)` 提供，不必各自重寫
/// - Note: 供應商的 `public func stream(_:)` 只寫 `makeStream(for: request)` 一行
/// - Note: 原因是 `public` protocol 的要求不能由 `package` extension 滿足
/// - Note: 供應商不自行建立 `Task`，背景 task 與取消接線都由 `LKAIChatStream.init(producing:)` 提供
package protocol LKAIServerSentEventChatStreaming: Sendable {

    /// 送出請求的 HTTP client，測試時換成不連網的替身
    var httpClient: any LKAIHTTPClientProtocol { get }

    /// 檢查供應商自己的設定，再組出帶金鑰的請求
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 可以交給 HTTP client 的請求，帶有 API 金鑰
    /// - Throws: 供應商的設定不合法，或請求內容無法編碼時丟出 `invalidRequest`
    /// - Note: 對話請求本身已由 `makeStream(for:)` 先檢查過，這裡只檢查供應商自己的設定，例如 Anthropic 的拒答備援
    /// - Note: 回傳的請求帶金鑰，只給共同流程使用，不要記錄或轉交到其他地方
    func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest

    /// 依供應商的錯誤格式分類非 2xx 的回應
    ///
    /// - Parameters:
    ///   - statusCode: 回應的 HTTP 狀態碼
    ///   - headers: 回應標頭，key 一律是小寫
    ///   - body: 已讀完的錯誤內容
    /// - Returns: 對應的錯誤；認不得時為 nil，由共同流程改用預設的狀態碼分類
    /// - Note: 純函式，不讀取回應的內容，內容已由共同流程讀好傳進來
    func httpError(statusCode: Int, headers: [String: String], body: String) -> LKAIError?

    /// 建立一份新的事件對應狀態，每條串流各用一份
    ///
    /// - Returns: 還沒有收到任何事件的對應狀態
    func makeEventMapper() -> any LKAIServerSentEventMapping
}

// MARK: - Internal Method

extension LKAIServerSentEventChatStreaming {

    /// 依序驗證請求、送出到供應商、處理錯誤回應，再把回應的 SSE 事件對應成對話事件交出
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 由 `LKAIChatStream.init(producing:)` 的背景 task 依序執行六個步驟，任何一步失敗，串流就以該錯誤結束
    /// - Note: 步驟 1：`request.validate()`，所有供應商相同的規則，不合法時不送出網路請求
    /// - Note: 步驟 2、3：`makeURLRequest(for:)` 組出請求，`httpClient.fetch(_:)` 送出
    /// - Note: 步驟 4：狀態碼不在 200...299 時讀出錯誤內容，丟出 `httpError(statusCode:headers:body:)` 的結果
    /// - Note: 步驟 4 的結果為 nil 時，改丟狀態碼的預設分類，這也是所有供應商共用的規則
    /// - Note: 步驟 5：以 `LKAIServerSentEventParser` 逐行解析回應，每則 SSE 事件交給 mapper
    /// - Note: 步驟 5 依序交出 mapper 回傳的對話事件，交出 `.finished` 後立即返回
    /// - Note: 步驟 6：讀完都沒有 `.finished` 時丟出 `invalidResponse`
    /// - Note: 交出 `.finished` 之後不再讀取，呼叫端離開後回應被釋放，底層傳輸跟著取消
    /// - Note: mapper 或逐行讀取丟出錯誤時，已交出的文字保留，串流以該錯誤結束
    package func makeStream(for request: LKAIChatRequest) -> LKAIChatStream {
        LKAIChatStream { yield throws(LKAIError) in
            try request.validate()
            let urlRequest = try makeURLRequest(for: request)
            let response = try await httpClient.fetch(urlRequest)
            if !(200...299).contains(response.statusCode) {
                let error = try await makeHTTPError(for: response)
                throw error
            }
            try await relayEvents(from: response.lines, yield: yield)
        }
    }
}

// MARK: - Private Method

private extension LKAIServerSentEventChatStreaming {

    /// 讀完非 2xx 回應的錯誤內容，交給供應商分類；供應商認不得時，改用狀態碼的預設分類
    ///
    /// - Parameter response: 狀態碼不是 2xx 的回應
    /// - Returns: 要丟出的錯誤
    /// - Throws: 讀取錯誤內容失敗時丟出，例如連線中斷
    /// - Note: 預設分類由 `retry-after` 標頭與狀態碼決定，是所有供應商共用的規則
    func makeHTTPError(for response: LKAIHTTPResponse) async throws(LKAIError) -> LKAIError {
        let body = try await response.readErrorBody()
        let providerError = httpError(
            statusCode: response.statusCode,
            headers: response.headers,
            body: body
        )
        if let providerError {
            return providerError
        }
        let retryAfter = response.headers["retry-after"]
        return LKAIError(httpStatusCode: response.statusCode, retryAfter: retryAfter)
    }

    /// 逐行讀取回應，組成 SSE 事件交給 mapper，依序交出它回傳的對話事件；交出 `.finished` 就停止讀取
    ///
    /// - Parameters:
    ///   - lines: 回應內容逐行交出的序列
    ///   - yield: 交出事件的 closure，mapper 回傳的對話事件從這裡交出
    /// - Throws: mapper 或逐行讀取丟出的錯誤原樣丟出；讀完沒有 `.finished` 丟 `invalidResponse`
    /// - Note: `.finished` 之後不再讀取，同一個陣列裡在它之後的事件也不交出
    func relayEvents(
        from lines: LKAIHTTPLines,
        yield: (LKAIChatStreamEvent) -> Void
    ) async throws(LKAIError) {
        var parser = LKAIServerSentEventParser()
        var mapper = makeEventMapper()
        for try await line in lines {
            guard let serverSentEvent = parser.parse(line: line) else {
                continue
            }
            let events = try mapper.handle(serverSentEvent)
            for event in events {
                yield(event)
                if case .finished = event {
                    return
                }
            }
        }
        parser.finish()
        throw .invalidResponse(reason: "Stream ended before a finish event")
    }
}
