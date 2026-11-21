//
//  LKAIHTTPClientTestSupport.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation

@testable import LKAICore

/// `LKAIHTTPClient`、`LKAIHTTPResponse` 與 `LKAIHTTPLines` 的測試共用的支援：假 `URLProtocol`、建立請求與 client 的方法
enum LKAIHTTPClientTestSupport {

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
}

// MARK: - Nested Types

extension LKAIHTTPClientTestSupport {

    /// 建構 `LKAIHTTPLines` 時接收的來源序列型別，寫短一點方便閱讀
    typealias LineSource = AsyncThrowingStream<String, any Error>

    /// 迭代完一份逐行內容後的結果：收到的全部行，以及丟出的錯誤
    struct LinesOutcome {

        /// 依收到的順序排列的全部行，不含 CR 與 LF
        let lines: [String]

        /// 逐行內容丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }

    /// 攔截請求並依請求上掛的設定回出假回應的 `URLProtocol`，不連網
    ///
    /// - Note: 設定掛在每個請求自己身上，所以測試之間不共用狀態，也不需要 `static` 可變狀態
    /// - Note: 有失敗代碼時，收到請求就以該代碼失敗；有狀態碼時，回出該狀態碼與設定的標頭、內容
    /// - Note: 設定成回非 HTTP 的回應時，回出一個不是 `HTTPURLResponse` 的回應，之後照常送內容並結束
    /// - Note: 回應的標頭一律加上 `Content-Type: text/event-stream`，否則 `URLSession` 會先緩衝內容
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
            setting(LKAIHTTPClientTestSupport.failureCodeKey, as: Int.self)
        }

        /// 是否要回出不是 `HTTPURLResponse` 的回應
        private var respondsWithNonHTTPResponse: Bool {
            setting(LKAIHTTPClientTestSupport.nonHTTPResponseKey, as: Bool.self) == true
        }

        /// 掛在請求上的假回應狀態碼；沒有設定時為 nil
        private var statusCode: Int? {
            setting(LKAIHTTPClientTestSupport.statusCodeKey, as: Int.self)
        }

        /// 掛在請求上的假回應內容；沒有設定時為空的資料
        private var body: Data {
            setting(LKAIHTTPClientTestSupport.bodyKey, as: Data.self) ?? Data()
        }

        /// 送完內容後是否不結束回應；沒有設定時為 `false`
        private var keepsOpen: Bool {
            setting(LKAIHTTPClientTestSupport.keepsOpenKey, as: Bool.self) == true
        }

        /// 掛在請求上的假回應標頭，不含固定加上的 `Content-Type`；沒有設定時為空
        private var extraHeaders: [String: String] {
            setting(LKAIHTTPClientTestSupport.headersKey, as: [String: String].self) ?? [:]
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

        /// 以請求的網址、狀態碼與設定的標頭建立 HTTP 回應，並加上固定的 `Content-Type`
        ///
        /// - Parameter statusCode: 假回應的 HTTP 狀態碼
        /// - Returns: 建好的 HTTP 回應；請求沒有網址或無法建立時為 nil
        private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse? {
            guard let url = request.url else {
                return nil
            }
            var headers = extraHeaders
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

// MARK: - Internal Method

extension LKAIHTTPClientTestSupport {

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

    /// 建立以假 `URLProtocol` 攔截所有請求的 `LKAIHTTPClient`，每次呼叫都用新的 `URLSession`
    ///
    /// - Returns: 不連網、只回出請求上假回應的 `LKAIHTTPClient`
    static func makeClient() -> LKAIHTTPClient {
        LKAIHTTPClient(session: makeSession())
    }

    /// 建立以假 `URLProtocol` 攔截所有請求的 `URLSession`；測試要自己查它的傳輸時，用它再交給 `LKAIHTTPClient`
    ///
    /// - Returns: 不連網、只回出請求上假回應的 `URLSession`
    static func makeSession() -> URLSession {
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
    static func collectLines(
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
}
