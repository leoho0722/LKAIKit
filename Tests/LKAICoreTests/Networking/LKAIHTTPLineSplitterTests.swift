//
//  LKAIHTTPLineSplitterTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIHTTPLineSplitter` 的單元測試
struct LKAIHTTPLineSplitterTests {

    /// 驗證 CR（\r，0x0D）、LF（\n，0x0A）與 CRLF 都各算一次換行，連續換行之間留下空行，最後一段沒有換行的內容由 `finish()` 交出
    ///
    /// - Parameters:
    ///   - input: 依序輸入的文字，逐一轉成 UTF-8 位元組後餵給切行器
    ///   - expected: 切出的行，不含 CR 與 LF，依出現順序排列
    @Test(arguments: [
        // CRLF 只算一次換行，空行保留
        ("a\r\n\r\nb\n", ["a", "", "b"]),
        ("a\n\nb", ["a", "", "b"]),
        // 單獨的 CR 也算一次換行
        ("a\rb", ["a", "b"]),
        // 連續兩個 CR 之間產生空行
        ("a\r\rb", ["a", "", "b"]),
        // 只有一個 LF 時切出一個空行，空輸入不切出任何行
        ("\n", [""]),
        ("", [String]()),
    ])
    func append_CR與LF_依規則切出預期的行(input: String, expected: [String]) {
        // Given
        let bytes = Array(input.utf8)

        // When
        let lines = splitLines(from: bytes)

        // Then
        #expect(lines == expected)
    }

    /// 驗證 U+2028、U+2029、U+0085 不是換行，中文也完整留在同一行
    ///
    /// - Parameters:
    ///   - input: 含有分隔符或中文的文字，結尾是 LF
    ///   - expected: 切出的行，分隔符與中文仍在行內
    @Test(arguments: [
        ("x\u{2028}y\n", ["x\u{2028}y"]),
        ("x\u{2029}y\n", ["x\u{2029}y"]),
        ("x\u{0085}y\n", ["x\u{0085}y"]),
        ("中文\n", ["中文"]),
    ])
    func append_Unicode分隔符與中文_保留在同一行(input: String, expected: [String]) {
        // Given
        let bytes = Array(input.utf8)

        // When
        let lines = splitLines(from: bytes)

        // Then
        #expect(lines == expected)
    }

    /// 驗證 CR 與 LF 分在兩次輸入時，後到的 LF 只被略過，不會多出一個空行
    @Test
    func append_CR後接LF_只算一次換行() {
        // Given
        var splitter = LKAIHTTPLineSplitter()
        _ = splitter.append(UInt8(ascii: "a"))
        _ = splitter.append(UInt8(ascii: "\r"))

        // When
        let line = splitter.append(UInt8(ascii: "\n"))

        // Then
        #expect(line == nil)
    }

    /// 驗證遇到 CR 時立即回傳目前的行，不等下一個位元組，避免串流延遲
    @Test
    func append_遇到CR_立即回傳目前的行() {
        // Given
        var splitter = LKAIHTTPLineSplitter()
        _ = splitter.append(UInt8(ascii: "a"))

        // When
        let line = splitter.append(UInt8(ascii: "\r"))

        // Then
        #expect(line == "a")
    }

    /// 驗證一行裡的位元組不是合法的 UTF-8 時，該行以替代字元 U+FFFD 取代，仍照常切出
    @Test
    func append_無效的UTF8位元組_以替代字元取代() {
        // Given
        let bytes: [UInt8] = [0xFF, UInt8(ascii: "\n")]

        // When
        let lines = splitLines(from: bytes)

        // Then
        #expect(lines == ["\u{FFFD}"])
    }

    /// 驗證串流結束時，還沒換行的內容由 `finish()` 交出
    @Test
    func finish_有未換行的內容_回傳該內容() {
        // Given
        var splitter = LKAIHTTPLineSplitter()
        for byte in "a\nb".utf8 {
            _ = splitter.append(byte)
        }

        // When
        let rest = splitter.finish()

        // Then
        #expect(rest == "b")
    }

    /// 驗證最後一行已經結束、之後沒有內容時，`finish()` 回傳 nil
    @Test
    func finish_沒有未換行的內容_回傳nil() {
        // Given
        var splitter = LKAIHTTPLineSplitter()
        for byte in "a\n".utf8 {
            _ = splitter.append(byte)
        }

        // When
        let rest = splitter.finish()

        // Then
        #expect(rest == nil)
    }
}

// MARK: - Private Method

private extension LKAIHTTPLineSplitterTests {

    /// 把位元組一個一個交給切行器，收集切出的每一行，最後加上 `finish()` 交出的未換行內容
    ///
    /// - Parameter bytes: 依序輸入的位元組
    /// - Returns: 依序切出的行，不含 CR 與 LF
    func splitLines(from bytes: [UInt8]) -> [String] {
        var splitter = LKAIHTTPLineSplitter()
        var lines: [String] = []
        for byte in bytes {
            if let line = splitter.append(byte) {
                lines.append(line)
            }
        }
        if let rest = splitter.finish() {
            lines.append(rest)
        }
        return lines
    }
}
