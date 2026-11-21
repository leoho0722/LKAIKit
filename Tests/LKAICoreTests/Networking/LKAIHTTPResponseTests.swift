//
//  LKAIHTTPResponseTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Testing

@testable import LKAICore

/// `LKAIHTTPResponse` 的單元測試：標頭 key 轉成小寫與 `readErrorBody()`
///
/// - Note: 直接以 `LKAIHTTPResponse` 與 `LKAIHTTPLines` 建立回應，不經過網路層，也不需要假的傳輸
struct LKAIHTTPResponseTests {

    /// 驗證直接以標頭建立回應時，`headers` 的 key 也一律轉成小寫，測試替身建立的回應走的就是這條路
    @Test
    func init_直接以標頭建立回應_標頭key一律為小寫() {
        // Given
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
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

    /// 驗證 `readErrorBody()` 原樣交出沒有超過上限的錯誤內容
    @Test
    func readErrorBody_錯誤內容未超過上限_原樣交出() async throws {
        // Given
        let response = makeResponse(lines: [#"{"type":"error"}"#])
        let expectedBody = #"{"type":"error"}"#

        // When
        let body = try await response.readErrorBody()

        // Then
        #expect(body == expectedBody)
    }

    /// 驗證錯誤內容有多行時，`readErrorBody()` 以 LF 串接推送的各行
    ///
    /// - Note: 推送的是切行器切好的三行 `a`、`b`、`c`，原始內容是 `a`、CRLF、`b`、LF、`c`
    @Test
    func readErrorBody_內容有多行_以LF串接各行() async throws {
        // Given
        let response = makeResponse(lines: ["a", "b", "c"])
        let expectedBody = "a\nb\nc"

        // When
        let body = try await response.readErrorBody()

        // Then
        #expect(body == expectedBody)
    }

    /// 驗證錯誤內容在 64 KiB（65_536 個 UTF-8 位元組）上限前後的長度，最多只保留上限的位元組數，不丟錯
    ///
    /// - Parameters:
    ///   - contentLength: 錯誤內容的位元組數，內容是推送成一行、沒有換行的 `x`
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
        let response = makeResponse(lines: [String(repeating: "x", count: contentLength)])

        // When
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
        let response = makeResponse(lines: [String(repeating: "中", count: 21_846)])

        // When
        let body = try await response.readErrorBody()

        // Then
        #expect(body.utf8.count == 65_535)
        #expect(!body.contains("\u{FFFD}"))
    }
}

// MARK: - Private Method

private extension LKAIHTTPResponseTests {

    /// 建立一個狀態碼 400、沒有標頭的回應，逐行內容是指定的幾行，推送完就結束
    ///
    /// - Parameter lines: 依序推送的每一行，不含 CR 與 LF；就是切行器切好之後的樣子
    /// - Returns: 帶著這些行的回應
    func makeResponse(lines: [String]) -> LKAIHTTPResponse {
        let (source, sourceContinuation) = LKAIHTTPLinesTestSupport.LineSource.makeStream()
        for line in lines {
            sourceContinuation.yield(line)
        }
        sourceContinuation.finish()
        return LKAIHTTPResponse(statusCode: 400, headers: [:], lines: LKAIHTTPLines(source))
    }
}
