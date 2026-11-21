//
//  LKAIServerSentEventParserTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIServerSentEventParser` 的單元測試
struct LKAIServerSentEventParserTests {

    /// 驗證以冒號開頭的註解行，以及 id、retry 與未知欄位都被略過，不影響事件的送出
    ///
    /// - Parameters:
    ///   - lines: 依序輸入解析器的行，不含 CR（\r，0x0D）與 LF（\n，0x0A）
    ///   - expected: 解析器送出的事件，依送出順序排列
    @Test(arguments: [
        // 冒號開頭的行是註解，只有一個冒號的行也是
        ([": ping", "data: a", ""], [LKAIServerSentEvent(event: nil, data: "a")]),
        ([":", "data: a", ""], [LKAIServerSentEvent(event: nil, data: "a")]),
        (["event: x", ": ping", "data: a", ""], [LKAIServerSentEvent(event: "x", data: "a")]),
        // id、retry 與未知欄位略過
        (
            ["id: 1", "retry: 10", "foo: bar", "data: x", ""],
            [LKAIServerSentEvent(event: nil, data: "x")]
        ),
    ] as [([String], [LKAIServerSentEvent])])
    func parse_註解行與其他欄位_略過且不影響事件(lines: [String], expected: [LKAIServerSentEvent]) {
        // Given
        var parser = LKAIServerSentEventParser()

        // When
        let events = lines.compactMap { parser.parse(line: $0) }

        // Then
        #expect(events == expected)
    }

    /// 驗證欄位名與值以第一個冒號分開，值開頭只移除一個空白，多個 data 以 `\n` 接起來
    ///
    /// - Parameters:
    ///   - lines: 依序輸入解析器的行，不含 CR 與 LF
    ///   - expected: 解析器送出的事件，依送出順序排列
    @Test(arguments: [
        // event 與 data 組成一個事件
        (
            ["event: message", "data: hi", ""],
            [LKAIServerSentEvent(event: "message", data: "hi")]
        ),
        // 多個 data 以 `\n` 接起來
        (["data: a", "data: b", ""], [LKAIServerSentEvent(event: nil, data: "a\nb")]),
        // 冒號後只移除一個空白
        (["data:  x", ""], [LKAIServerSentEvent(event: nil, data: " x")]),
        (["data:x", ""], [LKAIServerSentEvent(event: nil, data: "x")]),
        // 值裡的冒號保留
        (["data: a:b", ""], [LKAIServerSentEvent(event: nil, data: "a:b")]),
        // 沒有冒號的行，整行是欄位名，值為空
        (["data", ""], [LKAIServerSentEvent(event: nil, data: "")]),
        // 冒號後的值為空
        (["data:", ""], [LKAIServerSentEvent(event: nil, data: "")]),
        // 多位元組字元與 U+2028 都留在值裡
        (
            ["event: 事件", "data: 中文 \u{2028} 資料", ""],
            [LKAIServerSentEvent(event: "事件", data: "中文 \u{2028} 資料")]
        ),
    ] as [([String], [LKAIServerSentEvent])])
    func parse_欄位名與值_依冒號與空白規則解析(lines: [String], expected: [LKAIServerSentEvent]) {
        // Given
        var parser = LKAIServerSentEventParser()

        // When
        let events = lines.compactMap { parser.parse(line: $0) }

        // Then
        #expect(events == expected)
    }

    /// 驗證空行時有資料才送出事件，沒有資料只清除事件名稱，送出後事件名稱與資料都清空
    ///
    /// - Parameters:
    ///   - lines: 依序輸入解析器的行，不含 CR 與 LF
    ///   - expected: 解析器送出的事件，依送出順序排列
    @Test(arguments: [
        // 空行而沒有任何資料，不送出
        (["", "", "data: a", ""], [LKAIServerSentEvent(event: nil, data: "a")]),
        (["", ""], [LKAIServerSentEvent]()),
        // 只有 event 沒有 data，空行不送出，事件名稱不沿用到下一個事件
        (["event: x", "", "data: y", ""], [LKAIServerSentEvent(event: nil, data: "y")]),
        // 送出後事件名稱與資料都清除
        (
            ["event: a", "data: 1", "", "data: 2", ""],
            [
                LKAIServerSentEvent(event: "a", data: "1"),
                LKAIServerSentEvent(event: nil, data: "2"),
            ]
        ),
    ] as [([String], [LKAIServerSentEvent])])
    func parse_空行_依資料與事件名稱決定送出與否(lines: [String], expected: [LKAIServerSentEvent]) {
        // Given
        var parser = LKAIServerSentEventParser()

        // When
        let events = lines.compactMap { parser.parse(line: $0) }

        // Then
        #expect(events == expected)
    }

    /// 驗證串流結束時，尚未以空行收尾的事件被丟棄，之後再來的空行也不會送出它
    @Test
    func finish_有未收尾的事件_丟棄且之後的空行不送出() {
        // Given
        var parser = LKAIServerSentEventParser()
        _ = parser.parse(line: "event: x")
        _ = parser.parse(line: "data: y")

        // When
        parser.finish()
        let event = parser.parse(line: "")

        // Then
        #expect(event == nil)
    }

    /// 驗證 `finish()` 之後新輸入的資料，不會沿用被丟棄事件的事件名稱與資料
    @Test
    func finish_丟棄後再輸入資料_事件名稱不沿用() {
        // Given
        var parser = LKAIServerSentEventParser()
        _ = parser.parse(line: "event: x")
        _ = parser.parse(line: "data: y")
        parser.finish()
        _ = parser.parse(line: "data: z")

        // When
        let event = parser.parse(line: "")

        // Then
        #expect(event == LKAIServerSentEvent(event: nil, data: "z"))
    }
}
