//
//  LKAIHTTPClientTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import Testing

@testable import LKAICore

/// `LKAIHTTPClient` 的單元測試，以自訂的 `URLProtocol` 攔截請求，不連網
struct LKAIHTTPClientTests {

    // MARK: - Properties

    /// 掛在請求上的假回應狀態碼的 key
    private static let statusCodeKey = "lkai.test.statusCode"

    /// 掛在請求上的假回應標頭的 key
    private static let headersKey = "lkai.test.headers"

    /// 掛在請求上的假回應內容的 key
    private static let bodyKey = "lkai.test.body"

    /// 掛在請求上的「送完內容後不結束」設定的 key
    private static let keepsOpenKey = "lkai.test.keepsOpen"

    /// 掛在請求上的假失敗代碼的 key
    private static let failureCodeKey = "lkai.test.failureCode"

    /// 掛在請求上的「回出不是 HTTP 的回應」設定的 key
    private static let nonHTTPResponseKey = "lkai.test.nonHTTPResponse"

    /// 驗證回應內容以 CRLF 與 LF 換行時，`lines` 依序交出每一行並保留空行，然後正常結束，狀態碼照原樣交出
    @Test
    func fetch_回應內容有CRLF與空行_逐行交出且保留空行() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/stream"))
        let request = makeRequest(url: url, statusCode: 200, body: "a\r\n\r\nb\n")
        let client = makeClient()
        let expectedLines = ["a", "", "b"]

        // When
        let response = try await client.fetch(request)
        let outcome = await LKAIHTTPLinesTestSupport.collectLines(from: response.lines)

        // Then
        #expect(response.statusCode == 200)
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }

    /// 驗證回應標頭的 key 大小寫混用時，`headers` 的 key 一律是小寫，用原本的大小寫查不到
    @Test
    func fetch_回應標頭大小寫混用_標頭key一律為小寫() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/headers"))
        let request = makeRequest(url: url, statusCode: 200, headers: ["X-Request-ID": "abc"])
        let client = makeClient()

        // When
        let response = try await client.fetch(request)

        // Then
        #expect(response.headers["x-request-id"] == "abc")
        #expect(response.headers["X-Request-ID"] == nil)
    }

    /// 驗證狀態碼 400 的回應不會在 `fetch` 內轉成錯誤，`fetch` 照常回傳回應並保留狀態碼，由呼叫端自己分類
    ///
    /// - Note: 不看錯誤內容，`readErrorBody()` 的行為由 `LKAIHTTPResponseTests` 驗證
    @Test
    func fetch_狀態碼不是2xx_回傳回應而不轉成錯誤() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/error"))
        let request = makeRequest(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"],
            body: #"{"type":"error"}"#
        )
        let client = makeClient()
        var actualError: LKAIError?
        var actualStatusCode: Int?

        // When
        do {
            let response = try await client.fetch(request)
            actualStatusCode = response.statusCode
        } catch {
            actualError = error
        }

        // Then
        #expect(actualError == nil)
        #expect(actualStatusCode == 400)
    }

    /// 驗證連線在收到回應前就失敗時，`fetch` 丟出傳輸錯誤，並保留系統回報的原始錯誤代碼
    @Test
    func fetch_連線失敗_丟出傳輸錯誤並保留原始代碼() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/offline"))
        let request = makeFailingRequest(url: url, code: .notConnectedToInternet)
        let client = makeClient()
        let expectedCode = URLError.Code.notConnectedToInternet
        var actualError: LKAIError?

        // When
        do {
            _ = try await client.fetch(request)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let underlyingCode: URLError.Code? = if case .transport(let underlying) = error {
            underlying.code
        } else {
            nil
        }
        #expect(underlyingCode == expectedCode)
    }

    /// 驗證回應不是 HTTP 回應時，`fetch` 丟出無效回應錯誤，不會硬湊出狀態碼
    ///
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test
    func fetch_回應不是HTTP回應_丟出無效回應錯誤() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/plain"))
        let request = makeNonHTTPRequest(url: url)
        let client = makeClient()
        var actualError: LKAIError?

        // When
        do {
            _ = try await client.fetch(request)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(isInvalidResponse)
    }

    /// 驗證等不到回應時取消呼叫的 task，`fetch` 丟出 `cancelled`，不是傳輸錯誤
    ///
    /// - Note: 取消前短暫等待，讓請求先送出；就算取消發生在送出前，`URLSession` 丟出的也是取消的錯誤，結果相同
    @Test(.timeLimit(.minutes(1)))
    func fetch_等待回應時取消task_丟出cancelled而非傳輸錯誤() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/silent"))
        let request = makeSilentRequest(url: url)
        let client = makeClient()
        let expectedError = LKAIError.cancelled
        let fetchTask = Task {
            await fetchError(of: request, using: client)
        }

        // When
        try await Task.sleep(for: .milliseconds(100))
        fetchTask.cancel()
        let actualError = await fetchTask.value

        // Then
        #expect(actualError == expectedError)
    }

    /// 驗證逐行讀取到一半、回應還沒結束時取消 task，已收到的行照常交出，`lines` 正常結束，沒有錯誤
    @Test(.timeLimit(.minutes(1)))
    func fetch_逐行讀取中取消task_交出已讀的行後正常結束() async throws {
        // Given
        let request = try makeOpenRequest()
        let client = makeClient()
        let expectedLines = ["line1"]
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            let response = try await client.fetch(request)
            return await LKAIHTTPLinesTestSupport.collectLines(from: response.lines) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        let outcome = try await iterationTask.value

        // Then
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }

    // spectra-scenario: chat-client / Cancel a streaming call
    /// 驗證逐行讀取到一半、回應還沒結束時取消 task，底層的傳輸真的停止，`URLSession` 裡沒有進行中的傳輸
    ///
    /// - Note: 只看 `lines` 沒有錯誤，`LKAIHTTPLines` 自己的規則就能成立；要看到傳輸清空，才證明取消傳到了傳輸層
    @Test(.timeLimit(.minutes(1)))
    func fetch_逐行讀取中取消task_底層傳輸停止() async throws {
        // Given
        let request = try makeOpenRequest()
        let session = makeSession()
        let client = LKAIHTTPClient(session: session)
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            let response = try await client.fetch(request)
            return await LKAIHTTPLinesTestSupport.collectLines(from: response.lines) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        _ = try await iterationTask.value
        let remainingTaskCount = try await remainingActiveTaskCount(in: session)

        // Then
        #expect(remainingTaskCount == 0)
    }

    // spectra-scenario: chat-client / Release a stream after leaving the loop
    /// 驗證迭代到第一行就離開迴圈並釋放回應後，底層的傳輸真的停止，過程中沒有取消任何 task
    @Test(.timeLimit(.minutes(1)))
    func fetch_離開迴圈並釋放回應_底層傳輸停止() async throws {
        // Given
        let request = try makeOpenRequest()
        let session = makeSession()
        let client = LKAIHTTPClient(session: session)
        let expectedLine = "line1"

        // When
        let firstLine = try await receiveFirstLine(of: client, for: request)
        let remainingTaskCount = try await remainingActiveTaskCount(in: session)

        // Then
        #expect(firstLine == expectedLine)
        #expect(remainingTaskCount == 0)
    }
}

// MARK: - Nested Types

extension LKAIHTTPClientTests {

    /// 攔截請求並依請求上掛的設定回出假回應的 `URLProtocol`，不連網
    ///
    /// - Note: 設定掛在每個請求自己身上，所以測試之間不共用狀態，也不需要 `static` 可變狀態
    /// - Note: 有失敗代碼時，收到請求就以該代碼失敗；有狀態碼時，回出該狀態碼與設定的標頭、內容
    /// - Note: 設定成回非 HTTP 的回應時，回出一個不是 `HTTPURLResponse` 的回應，之後照常送內容並結束
    /// - Note: 回應的標頭預設加上 `Content-Type: text/event-stream`，否則 `URLSession` 會先緩衝內容
    /// - Note: 請求自己指定了 `Content-Type` 時，以指定的為準
    /// - Note: 什麼都沒設定時既不回應也不結束，模擬等不到回應；要求不結束時，送完內容後不結束
    final class FakeURLProtocol: URLProtocol {

        /// 攔截所有請求，不論網址
        ///
        /// - Parameter request: 即將送出的請求
        /// - Returns: 一律為 `true`
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        /// 不改寫請求，原樣使用
        ///
        /// - Parameter request: 即將送出的請求
        /// - Returns: 傳入的請求本身
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        /// 依請求上的設定回出假回應：依序看有沒有失敗代碼、要不要回非 HTTP 的回應、有沒有狀態碼，都沒有就什麼也不做
        override func startLoading() {
            if let failureCode {
                let error = URLError(URLError.Code(rawValue: failureCode))
                client?.urlProtocol(self, didFailWithError: error)
            } else if respondsWithNonHTTPResponse {
                deliver(makeNonHTTPResponse())
            } else if let statusCode {
                deliver(makeHTTPResponse(statusCode: statusCode))
            }
        }

        /// 不做任何清理：假回應一次送完，沒有背景工作；取消時 `URLSession` 自行中止傳輸
        override func stopLoading() {
            // 沒有要清理的東西
        }

        /// 掛在請求上的假失敗代碼；沒有設定時為 nil
        private var failureCode: Int? {
            setting(LKAIHTTPClientTests.failureCodeKey, as: Int.self)
        }

        /// 是否要回出不是 `HTTPURLResponse` 的回應
        private var respondsWithNonHTTPResponse: Bool {
            setting(LKAIHTTPClientTests.nonHTTPResponseKey, as: Bool.self) == true
        }

        /// 掛在請求上的假回應狀態碼；沒有設定時為 nil
        private var statusCode: Int? {
            setting(LKAIHTTPClientTests.statusCodeKey, as: Int.self)
        }

        /// 掛在請求上的假回應內容；沒有設定時為空的資料
        private var body: Data {
            setting(LKAIHTTPClientTests.bodyKey, as: Data.self) ?? Data()
        }

        /// 送完內容後是否不結束回應；沒有設定時為 `false`
        private var keepsOpen: Bool {
            setting(LKAIHTTPClientTests.keepsOpenKey, as: Bool.self) == true
        }

        /// 掛在請求上的假回應標頭；沒有設定時為空
        private var extraHeaders: [String: String] {
            setting(LKAIHTTPClientTests.headersKey, as: [String: String].self) ?? [:]
        }

        /// 讀出掛在請求上的設定
        ///
        /// - Parameters:
        ///   - key: 設定的 key
        ///   - type: 設定的值預期的型別
        /// - Returns: 請求上掛的值；沒有掛或型別不符時為 nil
        private func setting<Value>(_ key: String, as type: Value.Type) -> Value? {
            URLProtocol.property(forKey: key, in: request) as? Value
        }

        /// 把回應與設定的內容交給 `URLSession`，除非要求不結束，否則接著結束回應
        ///
        /// - Parameter response: 要交出的回應；建不出回應時為 nil，改以錯誤結束
        private func deliver(_ response: URLResponse?) {
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                if !keepsOpen {
                    client?.urlProtocolDidFinishLoading(self)
                }
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            }
        }

        /// 以請求的網址建立一個不是 `HTTPURLResponse` 的回應
        ///
        /// - Returns: 建好的回應；請求沒有網址時為 nil
        private func makeNonHTTPResponse() -> URLResponse? {
            guard let url = request.url else {
                return nil
            }
            return URLResponse(
                url: url,
                mimeType: "text/event-stream",
                expectedContentLength: -1,
                textEncodingName: nil
            )
        }

        /// 以請求的網址、狀態碼與設定的標頭建立 HTTP 回應；沒有指定 `Content-Type`（不分大小寫）時加上 `text/event-stream`
        ///
        /// - Parameter statusCode: 假回應的 HTTP 狀態碼
        /// - Returns: 建好的 HTTP 回應；請求沒有網址或無法建立時為 nil
        private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse? {
            guard let url = request.url else {
                return nil
            }
            var headers = extraHeaders
            let hasContentType = headers.keys.contains { $0.lowercased() == "content-type" }
            if !hasContentType {
                headers["Content-Type"] = "text/event-stream"
            }
            return HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        }
    }
}

// MARK: - Private Method

private extension LKAIHTTPClientTests {

    /// 建立一個會得到指定假回應的請求
    ///
    /// - Parameters:
    ///   - url: 請求的網址
    ///   - statusCode: 假回應的 HTTP 狀態碼
    ///   - headers: 假回應的標頭；沒有指定 `Content-Type`（不分大小寫）時，預設加上 `text/event-stream`
    ///   - body: 假回應的內容
    ///   - keepsOpen: 是否在送完內容後不結束回應
    /// - Returns: 帶著假回應設定的請求
    func makeRequest(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String = "",
        keepsOpen: Bool = false
    ) -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(statusCode, forKey: Self.statusCodeKey, in: request)
        URLProtocol.setProperty(headers, forKey: Self.headersKey, in: request)
        URLProtocol.setProperty(Data(body.utf8), forKey: Self.bodyKey, in: request)
        URLProtocol.setProperty(keepsOpen, forKey: Self.keepsOpenKey, in: request)
        return request as URLRequest
    }

    /// 建立以假 `URLProtocol` 攔截所有請求的 `LKAIHTTPClient`，每次呼叫都用新的 `URLSession`
    ///
    /// - Returns: 不連網、只回出請求上假回應的 `LKAIHTTPClient`
    func makeClient() -> LKAIHTTPClient {
        LKAIHTTPClient(session: makeSession())
    }

    /// 建立以假 `URLProtocol` 攔截所有請求的 `URLSession`；測試要自己查它的傳輸時，用它再交給 `LKAIHTTPClient`
    ///
    /// - Returns: 不連網、只回出請求上假回應的 `URLSession`
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 建立一個在收到回應前就以指定代碼失敗的請求
    ///
    /// - Parameters:
    ///   - url: 請求的網址
    ///   - code: 失敗的 `URLError` 代碼
    /// - Returns: 帶著失敗設定的請求
    func makeFailingRequest(url: URL, code: URLError.Code) -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(code.rawValue, forKey: Self.failureCodeKey, in: request)
        return request as URLRequest
    }

    /// 建立一個會得到不是 `HTTPURLResponse` 的回應的請求
    ///
    /// - Parameter url: 請求的網址
    /// - Returns: 帶著「回出不是 HTTP 回應」設定的請求
    func makeNonHTTPRequest(url: URL) -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(true, forKey: Self.nonHTTPResponseKey, in: request)
        return request as URLRequest
    }

    /// 建立一個既不回應也不結束的請求，模擬一直等不到回應
    ///
    /// - Parameter url: 請求的網址
    /// - Returns: 沒有任何假回應設定的請求
    func makeSilentRequest(url: URL) -> URLRequest {
        NSMutableURLRequest(url: url) as URLRequest
    }

    /// 送出請求並記下 `fetch` 丟出的錯誤
    ///
    /// - Parameters:
    ///   - request: 要送出的請求
    ///   - client: 送出請求的 HTTP client
    /// - Returns: `fetch` 丟出的錯誤；請求順利得到回應時為 nil
    func fetchError(of request: URLRequest, using client: LKAIHTTPClient) async -> LKAIError? {
        var actualError: LKAIError?
        do {
            _ = try await client.fetch(request)
        } catch {
            actualError = error
        }
        return actualError
    }

    /// 建立送出一行後不結束的請求：狀態碼 200、內容 `line1` 加 LF，回應一直開著
    ///
    /// - Returns: 帶著這份假回應設定的請求
    /// - Throws: 測試用的網址無法建立時丟出
    func makeOpenRequest() throws -> URLRequest {
        let url = try #require(URL(string: "https://lkai.test/open"))
        return makeRequest(
            url: url,
            statusCode: 200,
            body: "line1\n",
            keepsOpen: true
        )
    }

    /// 最多等 2 秒，每 10 毫秒查一次，等 `URLSession` 裡進行中的傳輸清空；取消是非同步的，所以要等
    ///
    /// - Parameter session: 要查的 `URLSession`
    /// - Returns: 等待結束時進行中的傳輸數；清空時為 0，等滿仍沒有清空時為仍在進行的數量
    /// - Throws: 測試的 task 在等待中被取消時丟出
    func remainingActiveTaskCount(in session: URLSession) async throws -> Int {
        for _ in 0..<200 {
            let count = await activeTaskCount(of: session)
            if count == 0 {
                return 0
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await activeTaskCount(of: session)
    }

    /// 數 `URLSession` 裡進行中或暫停中的傳輸，已取消或已完成的不算
    ///
    /// - Parameter session: 要查的 `URLSession`
    /// - Returns: 進行中或暫停中的傳輸數
    func activeTaskCount(of session: URLSession) async -> Int {
        await session.allTasks.filter { $0.state == .running || $0.state == .suspended }.count
    }

    /// 送出請求、取得第一行就離開迴圈，函式返回時回應與逐行內容跟著釋放，不取消任何 task
    ///
    /// - Parameters:
    ///   - client: 送出請求的 HTTP client
    ///   - request: 要送出的請求
    /// - Returns: 逐行內容的第一行；沒有任何一行就結束時為 nil
    /// - Throws: 送出請求或讀取第一行失敗時丟出
    func receiveFirstLine(
        of client: LKAIHTTPClient,
        for request: URLRequest
    ) async throws(LKAIError) -> String? {
        let response = try await client.fetch(request)
        for try await line in response.lines {
            return line
        }
        return nil
    }
}
