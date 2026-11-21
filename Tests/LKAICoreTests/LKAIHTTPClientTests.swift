//
//  LKAIHTTPClientTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation
import Testing

@testable import LKAICore

/// `LKAIHTTPClient`、`LKAIHTTPResponse` 與 `LKAIHTTPLines` 的單元測試，以自訂的 `URLProtocol` 攔截請求，不連網
struct LKAIHTTPClientTests {

    /// 驗證回應內容以 CRLF 與 LF 換行時，`lines` 依序交出每一行並保留空行，然後正常結束，狀態碼照原樣交出
    @Test
    func fetch_回應內容有CRLF與空行_逐行交出且保留空行() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/stream"))
        let request = FakeURLProtocol.makeRequest(url: url, statusCode: 200, body: "a\r\n\r\nb\n")
        let client = makeClient()
        let expectedLines = ["a", "", "b"]

        // When
        let response = try await client.fetch(request)
        let outcome = await collectLines(from: response.lines)

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
        let request = FakeURLProtocol.makeRequest(
            url: url,
            statusCode: 200,
            headers: ["X-Request-ID": "abc"]
        )
        let client = makeClient()

        // When
        let response = try await client.fetch(request)

        // Then
        #expect(response.headers["x-request-id"] == "abc")
        #expect(response.headers["X-Request-ID"] == nil)
    }

    /// 驗證直接以標頭建立回應時，`headers` 的 key 也一律轉成小寫，測試替身建立的回應走的就是這條路
    @Test
    func init_直接以標頭建立回應_標頭key一律為小寫() {
        // Given
        let (source, sourceContinuation) = LineSource.makeStream()
        sourceContinuation.finish()
        let lines = LKAIHTTPLines(source)

        // When
        let response = LKAIHTTPResponse(
            statusCode: 200,
            headers: ["Retry-After": "30"],
            lines: lines
        )

        // Then
        #expect(response.headers["retry-after"] == "30")
        #expect(response.headers["Retry-After"] == nil)
    }

    /// 驗證狀態碼 400 的回應不會在 `fetch` 內轉成錯誤，`readErrorBody()` 原樣交出沒有超過上限的內容
    @Test
    func readErrorBody_錯誤內容未超過上限_原樣交出() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/error"))
        let request = FakeURLProtocol.makeRequest(
            url: url,
            statusCode: 400,
            body: #"{"type":"error"}"#
        )
        let client = makeClient()
        let expectedBody = #"{"type":"error"}"#

        // When
        let response = try await client.fetch(request)
        let body = try await response.readErrorBody()

        // Then
        #expect(response.statusCode == 400)
        #expect(body == expectedBody)
    }

    /// 驗證錯誤內容有多行時，`readErrorBody()` 不論原本以 CRLF 或 LF 換行，都以 LF 串接各行
    @Test
    func readErrorBody_內容有多行_以LF串接各行() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/error"))
        let request = FakeURLProtocol.makeRequest(url: url, statusCode: 500, body: "a\r\nb\nc")
        let client = makeClient()
        let expectedBody = "a\nb\nc"

        // When
        let response = try await client.fetch(request)
        let body = try await response.readErrorBody()

        // Then
        #expect(body == expectedBody)
    }

    /// 驗證錯誤內容在 64 KiB（65_536 個 UTF-8 位元組）上限前後的長度，最多只保留上限的位元組數，不丟錯
    ///
    /// - Parameters:
    ///   - contentLength: 假回應內容的位元組數，內容是沒有換行的 `x`
    ///   - expectedLength: `readErrorBody()` 交出的字串應有的 UTF-8 位元組數
    @Test(arguments: [
        (65_535, 65_535),
        (65_536, 65_536),
        (65_537, 65_536),
        (70_000, 65_536),
    ] as [(Int, Int)])
    func readErrorBody_內容長度在上限前後_最多保留64KiB而不失敗(
        contentLength: Int,
        expectedLength: Int
    ) async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/large"))
        let request = FakeURLProtocol.makeRequest(
            url: url,
            statusCode: 400,
            body: String(repeating: "x", count: contentLength)
        )
        let client = makeClient()

        // When
        let response = try await client.fetch(request)
        let body = try await response.readErrorBody()

        // Then
        #expect(body.utf8.count == expectedLength)
    }

    /// 驗證 64 KiB 的上限落在多位元組字元中間時，整個字捨棄而不切開，結果不含替代字元 U+FFFD
    ///
    /// - Note: 內容是 21_846 個 `中`，每個 3 個位元組共 65_538 個位元組，所以只保留 21_845 個字
    @Test
    func readErrorBody_上限落在多位元組字元中間_整個字捨棄而不切開() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/large"))
        let request = FakeURLProtocol.makeRequest(
            url: url,
            statusCode: 400,
            body: String(repeating: "中", count: 21_846)
        )
        let client = makeClient()

        // When
        let response = try await client.fetch(request)
        let body = try await response.readErrorBody()

        // Then
        #expect(body.utf8.count == 65_535)
        #expect(!body.contains("\u{FFFD}"))
    }

    /// 驗證連線在收到回應前就失敗時，`fetch` 丟出傳輸錯誤，並保留系統回報的原始錯誤代碼
    @Test
    func fetch_連線失敗_丟出傳輸錯誤並保留原始代碼() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/offline"))
        let request = FakeURLProtocol.makeFailingRequest(url: url, code: .notConnectedToInternet)
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
        let request = FakeURLProtocol.makeNonHTTPRequest(url: url)
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
        let request = FakeURLProtocol.makeSilentRequest(url: url)
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
        let url = try #require(URL(string: "https://lkai.test/open"))
        let request = FakeURLProtocol.makeRequest(
            url: url,
            statusCode: 200,
            body: "line1\n",
            keepsOpen: true
        )
        let client = makeClient()
        let expectedLines = ["line1"]
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            let response = try await client.fetch(request)
            return await collectLines(from: response.lines) { _ in
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
            return await collectLines(from: response.lines) { _ in
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

    /// 驗證來源丟出 `CancellationError` 或 `cancelled` 時，已送出的行照常交出，`lines` 再正常結束
    ///
    /// - Parameter thrownError: 來源丟出的取消類錯誤
    @Test(arguments: [
        CancellationError(),
        LKAIError.cancelled,
    ] as [any Error & Sendable])
    func init_來源丟出取消類的錯誤_已送出的行照常交出後正常結束(thrownError: any Error & Sendable) async {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: thrownError)
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await collectLines(from: lines)

        // Then
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }

    /// 驗證來源丟出不是 `LKAIError` 的錯誤時，`lines` 先交出已送出的行，再降級成無效回應錯誤
    ///
    /// - Note: 只比對是不是無效回應，不比對原因文字，規格沒有規定它
    @Test
    func init_來源丟出不是對話錯誤的錯誤_降級為無效回應錯誤() async throws {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: UnrelatedError())
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await collectLines(from: lines)

        // Then
        let error = try #require(outcome.error)
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(outcome.lines == expectedLines)
        #expect(isInvalidResponse)
    }

    /// 驗證來源丟出 `LKAIError`（`cancelled` 除外）時，`lines` 先交出已送出的行，再原樣丟出同一個錯誤
    @Test
    func init_來源丟出對話錯誤_原樣丟出() async throws {
        // Given
        let expectedLines = ["a"]
        let expectedError = LKAIError.rateLimited(retryAfter: nil)
        let (source, sourceContinuation) = LineSource.makeStream()
        sourceContinuation.yield("a")
        sourceContinuation.finish(throwing: expectedError)
        let lines = LKAIHTTPLines(source)

        // When
        let outcome = await collectLines(from: lines)

        // Then
        let error = try #require(outcome.error)
        #expect(outcome.lines == expectedLines)
        #expect(error == expectedError)
    }

    /// 驗證迭代的 task 被取消之後來源才丟出錯誤，`lines` 仍正常結束，取消後不論錯誤是什麼都不當成失敗
    ///
    /// - Parameter thrownError: 取消後來源丟出的錯誤，包含對話錯誤與不是對話錯誤的錯誤
    /// - Note: 來源在 `onTermination` 裡才結束，重現「取消的空檔中來源丟出錯誤」；少了取消規則，錯誤會漏到消費端
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [
            LKAIError.rateLimited(retryAfter: nil),
            UnrelatedError(),
        ] as [any Error & Sendable]
    )
    func init_先取消迭代的task再由來源丟出錯誤_正常結束且沒有錯誤(thrownError: any Error & Sendable) async {
        // Given
        let expectedLines = ["a"]
        let (source, sourceContinuation) = LineSource.makeStream()
        sourceContinuation.onTermination = { termination in
            if case .cancelled = termination {
                sourceContinuation.finish(throwing: thrownError)
            }
        }
        sourceContinuation.yield("a")
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let lines = LKAIHTTPLines(source)
        let iterationTask = Task {
            await collectLines(from: lines) { _ in
                receivedSignal.yield()
            }
        }

        // When
        for await _ in receivedSignals {
            break
        }
        iterationTask.cancel()
        let outcome = await iterationTask.value

        // Then
        #expect(outcome.lines == expectedLines)
        #expect(outcome.error == nil)
    }
}

// MARK: - Nested Types

extension LKAIHTTPClientTests {

    /// 建構 `LKAIHTTPLines` 時接收的來源序列型別，寫短一點方便閱讀
    typealias LineSource = AsyncThrowingStream<String, any Error>

    /// 迭代完一份逐行內容後的結果：收到的全部行，以及丟出的錯誤
    struct LinesOutcome {

        /// 依收到的順序排列的全部行，不含 CR 與 LF
        let lines: [String]

        /// 逐行內容丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }

    /// 不是對話錯誤的錯誤，用來確認未知的錯誤會降級成無效回應
    struct UnrelatedError: Error {

    }

    /// 攔截請求並依請求上掛的設定回出假回應的 `URLProtocol`，不連網
    ///
    /// - Note: 設定掛在每個請求自己身上，所以測試之間不共用狀態，也不需要 `static` 可變狀態
    /// - Note: 有失敗代碼時，收到請求就以該代碼失敗；有狀態碼時，回出該狀態碼與設定的標頭、內容
    /// - Note: 設定成回非 HTTP 的回應時，回出一個不是 `HTTPURLResponse` 的回應，之後照常送內容並結束
    /// - Note: 回應的標頭一律加上 `Content-Type: text/event-stream`，否則 `URLSession` 會先緩衝內容
    /// - Note: 什麼都沒設定時既不回應也不結束，模擬等不到回應；要求不結束時，送完內容後不結束
    final class FakeURLProtocol: URLProtocol {

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

        /// 建立一個會得到指定假回應的請求
        ///
        /// - Parameters:
        ///   - url: 請求的網址
        ///   - statusCode: 假回應的 HTTP 狀態碼
        ///   - headers: 假回應的標頭，除了固定加上的 `Content-Type`
        ///   - body: 假回應的內容
        ///   - keepsOpen: 是否在送完內容後不結束回應
        /// - Returns: 帶著假回應設定的請求
        static func makeRequest(
            url: URL,
            statusCode: Int,
            headers: [String: String] = [:],
            body: String = "",
            keepsOpen: Bool = false
        ) -> URLRequest {
            let request = NSMutableURLRequest(url: url)
            URLProtocol.setProperty(statusCode, forKey: statusCodeKey, in: request)
            URLProtocol.setProperty(headers, forKey: headersKey, in: request)
            URLProtocol.setProperty(Data(body.utf8), forKey: bodyKey, in: request)
            URLProtocol.setProperty(keepsOpen, forKey: keepsOpenKey, in: request)
            return request as URLRequest
        }

        /// 建立一個在收到回應前就以指定代碼失敗的請求
        ///
        /// - Parameters:
        ///   - url: 請求的網址
        ///   - code: 失敗的 `URLError` 代碼
        /// - Returns: 帶著失敗設定的請求
        static func makeFailingRequest(url: URL, code: URLError.Code) -> URLRequest {
            let request = NSMutableURLRequest(url: url)
            URLProtocol.setProperty(code.rawValue, forKey: failureCodeKey, in: request)
            return request as URLRequest
        }

        /// 建立一個既不回應也不結束的請求，模擬一直等不到回應
        ///
        /// - Parameter url: 請求的網址
        /// - Returns: 沒有任何假回應設定的請求
        static func makeSilentRequest(url: URL) -> URLRequest {
            NSMutableURLRequest(url: url) as URLRequest
        }

        /// 建立一個會得到不是 `HTTPURLResponse` 的回應的請求
        ///
        /// - Parameter url: 請求的網址
        /// - Returns: 帶著「回出不是 HTTP 回應」設定的請求
        static func makeNonHTTPRequest(url: URL) -> URLRequest {
            let request = NSMutableURLRequest(url: url)
            URLProtocol.setProperty(true, forKey: nonHTTPResponseKey, in: request)
            return request as URLRequest
        }

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
            if let failureCode = setting(Self.failureCodeKey, as: Int.self) {
                let error = URLError(URLError.Code(rawValue: failureCode))
                client?.urlProtocol(self, didFailWithError: error)
            } else if setting(Self.nonHTTPResponseKey, as: Bool.self) == true {
                deliver(makeNonHTTPResponse())
            } else if let statusCode = setting(Self.statusCodeKey, as: Int.self) {
                deliver(makeHTTPResponse(statusCode: statusCode))
            }
        }

        /// 不做任何清理：假回應一次送完，沒有背景工作；取消時 `URLSession` 自行中止傳輸
        override func stopLoading() {
            // 沒有要清理的東西
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
                client?.urlProtocol(self, didLoad: setting(Self.bodyKey, as: Data.self) ?? Data())
                if setting(Self.keepsOpenKey, as: Bool.self) != true {
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

        /// 以請求的網址、狀態碼與設定的標頭建立 HTTP 回應，並加上固定的 `Content-Type`
        ///
        /// - Parameter statusCode: 假回應的 HTTP 狀態碼
        /// - Returns: 建好的 HTTP 回應；請求沒有網址或無法建立時為 nil
        private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse? {
            guard let url = request.url else {
                return nil
            }
            var headers = setting(Self.headersKey, as: [String: String].self) ?? [:]
            headers["Content-Type"] = "text/event-stream"
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

    /// 逐行收下逐行內容交出的每一行，並記下它是正常結束還是丟出了錯誤
    ///
    /// - Parameters:
    ///   - lines: 要迭代的逐行內容
    ///   - onLine: 每收到一行就呼叫一次；不需要時省略
    /// - Returns: 收到的全部行，以及丟出的錯誤；正常結束時錯誤為 nil
    func collectLines(
        from lines: LKAIHTTPLines,
        onLine: (String) -> Void = { _ in }
    ) async -> LinesOutcome {
        var receivedLines: [String] = []
        var actualError: LKAIError?
        do {
            for try await line in lines {
                receivedLines.append(line)
                onLine(line)
            }
        } catch {
            actualError = error
        }
        return LinesOutcome(lines: receivedLines, error: actualError)
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
        return FakeURLProtocol.makeRequest(
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
