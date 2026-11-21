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

    /// 驗證回應內容以 CRLF 與 LF 換行時，`lines` 依序交出每一行並保留空行，然後正常結束，狀態碼照原樣交出
    @Test
    func fetch_回應內容有CRLF與空行_逐行交出且保留空行() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/stream"))
        let request = LKAIHTTPClientTestSupport.makeRequest(
            url: url,
            statusCode: 200,
            body: "a\r\n\r\nb\n"
        )
        let client = LKAIHTTPClientTestSupport.makeClient()
        let expectedLines = ["a", "", "b"]

        // When
        let response = try await client.fetch(request)
        let outcome = await LKAIHTTPClientTestSupport.collectLines(from: response.lines)

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
        let request = LKAIHTTPClientTestSupport.makeRequest(
            url: url,
            statusCode: 200,
            headers: ["X-Request-ID": "abc"]
        )
        let client = LKAIHTTPClientTestSupport.makeClient()

        // When
        let response = try await client.fetch(request)

        // Then
        #expect(response.headers["x-request-id"] == "abc")
        #expect(response.headers["X-Request-ID"] == nil)
    }

    /// 驗證連線在收到回應前就失敗時，`fetch` 丟出傳輸錯誤，並保留系統回報的原始錯誤代碼
    @Test
    func fetch_連線失敗_丟出傳輸錯誤並保留原始代碼() async throws {
        // Given
        let url = try #require(URL(string: "https://lkai.test/offline"))
        let request = LKAIHTTPClientTestSupport.makeFailingRequest(
            url: url,
            code: .notConnectedToInternet
        )
        let client = LKAIHTTPClientTestSupport.makeClient()
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
        let request = LKAIHTTPClientTestSupport.makeNonHTTPRequest(url: url)
        let client = LKAIHTTPClientTestSupport.makeClient()
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
        let request = LKAIHTTPClientTestSupport.makeSilentRequest(url: url)
        let client = LKAIHTTPClientTestSupport.makeClient()
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
        let request = LKAIHTTPClientTestSupport.makeRequest(
            url: url,
            statusCode: 200,
            body: "line1\n",
            keepsOpen: true
        )
        let client = LKAIHTTPClientTestSupport.makeClient()
        let expectedLines = ["line1"]
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            let response = try await client.fetch(request)
            return await LKAIHTTPClientTestSupport.collectLines(from: response.lines) { _ in
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
        let session = LKAIHTTPClientTestSupport.makeSession()
        let client = LKAIHTTPClient(session: session)
        let (receivedSignals, receivedSignal) = AsyncStream<Void>.makeStream()
        let iterationTask = Task {
            let response = try await client.fetch(request)
            return await LKAIHTTPClientTestSupport.collectLines(from: response.lines) { _ in
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
        let session = LKAIHTTPClientTestSupport.makeSession()
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

// MARK: - Private Method

private extension LKAIHTTPClientTests {

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
        return LKAIHTTPClientTestSupport.makeRequest(
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
