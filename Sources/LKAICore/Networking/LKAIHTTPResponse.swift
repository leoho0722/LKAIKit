//
//  LKAIHTTPResponse.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 一次 HTTP 回應：狀態碼、標頭與逐行交出的內容；不是 2xx 的狀態碼也原樣交出，由呼叫端自己判斷
package struct LKAIHTTPResponse: Sendable {

    // MARK: - Properties

    /// HTTP 狀態碼
    package let statusCode: Int

    /// 回應標頭，key 一律是小寫
    package let headers: [String: String]

    /// 回應內容逐行交出的序列
    ///
    /// - Note: 只支援單一消費者，讀過 `readErrorBody()` 之後不能再迭代
    package let lines: LKAIHTTPLines

    // MARK: - Init

    /// 建立一次 HTTP 回應，標頭的 key 在這裡轉成小寫，所以不論來源是真實連線還是測試替身，查詢時都用小寫
    ///
    /// - Parameters:
    ///   - statusCode: HTTP 狀態碼
    ///   - headers: 回應標頭；大小寫不同的重複 key 只保留其中一個
    ///   - lines: 回應內容逐行交出的序列
    package init(statusCode: Int, headers: [String: String], lines: LKAIHTTPLines) {
        var lowercasedHeaders: [String: String] = [:]
        for (key, value) in headers {
            lowercasedHeaders[key.lowercased()] = value
        }
        self.statusCode = statusCode
        self.headers = lowercasedHeaders
        self.lines = lines
    }
}

// MARK: - Internal Method

extension LKAIHTTPResponse {

    /// 讀出錯誤回應的內容，以 LF 串接各行；超過上限就截斷並停止讀取，不當成失敗
    ///
    /// - Returns: 串接後的內容，最多 65_536 個 UTF-8 位元組（64 KiB），不會切在多位元組字元中間
    /// - Throws: 讀取過程中逐行內容丟出的 `LKAIError` 原樣丟出
    /// - Note: 64 KiB 是估計值，足以容納三家已知的錯誤格式，這個上限只限制回傳字串的大小，擋不住異常大型回應佔用的記憶體（見 design Risks）
    /// - Note: 逐行內容只支援單一消費者，讀過之後不能再迭代 `lines`
    /// - Note: 呼叫端讀完後應釋放這個回應，底層傳輸才會被取消
    package func readErrorBody() async throws(LKAIError) -> String {
        let byteLimit = 65_536
        var body = ""
        var byteCount = 0
        var isFirstLine = true
        for try await line in lines {
            let text = isFirstLine ? line : "\n" + line
            isFirstLine = false
            for scalar in text.unicodeScalars {
                byteCount += String(scalar).utf8.count
                guard byteCount <= byteLimit else {
                    return body
                }
                body.unicodeScalars.append(scalar)
            }
        }
        return body
    }
}
