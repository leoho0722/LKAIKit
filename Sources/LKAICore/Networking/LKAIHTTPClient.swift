//
//  LKAIHTTPClient.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation

// MARK: - Protocol

/// 送出 HTTP 請求的入口，供應商透過它連線；測試時換成不連網的替身
package protocol LKAIHTTPClientProtocol: Sendable {

    /// 送出請求並回傳回應；不是 2xx 的狀態碼不會在這裡轉成錯誤
    ///
    /// - Parameter request: 要送出的請求
    /// - Returns: HTTP 回應，內容還沒讀完，由呼叫端逐行取得
    /// - Throws: 呼叫的 task 被取消丟 `.cancelled`；連線失敗丟 `.transport`；收到的不是 HTTP 回應丟 `.invalidResponse`
    /// - Note: 狀態碼不是 2xx 時，由呼叫端讀 `readErrorBody()` 後，依供應商自己的錯誤格式分類
    func fetch(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse
}

// MARK: - Implementation

/// `LKAIHTTPClientProtocol` 的正式實作，以 App 注入的 `URLSession` 送出請求
///
/// - Note: 逾時與連線設定由 App 透過 `URLSession` 決定
package struct LKAIHTTPClient {

    // MARK: - Properties

    /// 實際送出請求的 `URLSession`，由 App 注入
    private let session: URLSession

    // MARK: - Init

    /// 建立正式實作
    ///
    /// - Parameter session: 實際送出請求的 `URLSession`
    package init(session: URLSession) {
        self.session = session
    }
}

// MARK: - LKAIHTTPClientProtocol

extension LKAIHTTPClient: LKAIHTTPClientProtocol {

    /// 以 `URLSession.bytes(for:)` 送出請求，回應一到就回傳，內容在背景逐位元組讀取、切成行後交出
    ///
    /// - Parameter request: 要送出的請求
    /// - Returns: 狀態碼、key 為小寫的標頭，以及逐行內容；逐行內容被釋放或迭代的 task 被取消時，取消底層的資料傳輸
    /// - Throws: 取消的 `URLError` 在呼叫的 task 已被取消時丟 `.cancelled`，其餘 `URLError` 丟 `.transport`
    /// - Note: 回應不是 HTTP 回應，或丟出不是 `URLError` 與 `CancellationError` 的錯誤時，丟 `.invalidResponse`
    package func fetch(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw makeError(from: error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .invalidResponse(reason: "The response is not an HTTP response")
        }
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            guard let name = key as? String, let content = value as? String else {
                continue
            }
            headers[name] = content
        }
        return LKAIHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            lines: makeLines(from: bytes)
        )
    }
}

// MARK: - Private Method

private extension LKAIHTTPClient {

    /// 把送出請求或讀取內容時丟出的錯誤轉成 `LKAIError`
    ///
    /// - Parameter error: `URLSession` 或讀取位元組時丟出的錯誤
    /// - Returns: 對應的 `LKAIError`
    /// - Note: 取消的 `URLError` 只在目前的 task 確實被取消時才算取消，其餘一律是傳輸錯誤
    func makeError(from error: any Error) -> LKAIError {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled && Task.isCancelled {
                return .cancelled
            }
            return .transport(underlying: urlError)
        }
        if error is CancellationError {
            return .cancelled
        }
        return .invalidResponse(reason: "Unexpected error: \(error)")
    }

    /// 把回應內容切成一行一行的文字，包成逐行內容交給呼叫端
    ///
    /// - Parameter bytes: `URLSession` 回傳的回應內容位元組
    /// - Returns: 逐行內容；它被釋放或迭代的 task 被取消時，取消底層的資料傳輸
    /// - Note: 每次呼叫建立一個非結構化的 `Task` 來讀位元組，偏離 ios-dev-kit「`Task { }` 只在兩個地方建立」
    /// - Note: 理由：函式庫沒有 View 或 ViewModel，要把非同步的生產端接到 `AsyncSequence` 只能這樣做
    /// - Note: 以「每條逐行內容一個 task、只由 `onTermination` 取消、不存進任何屬性」限制它的生命週期
    func makeLines(from bytes: URLSession.AsyncBytes) -> LKAIHTTPLines {
        let source = AsyncThrowingStream<String, any Error> { continuation in
            let readingTask = Task {
                var splitter = LKAIHTTPLineSplitter()
                do {
                    for try await byte in bytes {
                        if let line = splitter.append(byte) {
                            continuation.yield(line)
                        }
                    }
                    if let rest = splitter.finish() {
                        continuation.yield(rest)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: makeError(from: error))
                }
            }
            continuation.onTermination = { _ in
                readingTask.cancel()
            }
        }
        return LKAIHTTPLines(source)
    }
}
