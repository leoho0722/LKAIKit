//
//  LKAIServerSentEventParser.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 依 WHATWG HTML 規格的 event stream 規則，把一行一行的文字組成 Server-Sent Event 事件
///
/// - Note: 不處理 `id` 與 `retry` 欄位，因為這個 package 不做自動重新連線
/// - Note: 串流結束時呼叫 `finish()`，依規格丟棄尚未以空行收尾的事件
package struct LKAIServerSentEventParser: Sendable {

    // MARK: - Properties

    /// 目前這段事件的名稱，還沒有 event 欄位時為 nil
    private var eventName: String?

    /// 目前這段事件的資料，每個 data 欄位的值後面都接一個 LF，還沒有 data 欄位時為空字串
    private var dataBuffer = ""

    // MARK: - Init

    /// 建立一個還沒有任何事件資料的解析器
    package init() {}
}

// MARK: - Internal Method

extension LKAIServerSentEventParser {

    /// 輸入一行；這一行是空行、而且要送出事件時回傳事件，否則回傳 nil
    ///
    /// - Parameter line: 一行文字，不含 CR 與 LF
    /// - Returns: 要送出的事件；這一行不是空行，或沒有資料可送時為 nil
    package mutating func parse(line: String) -> LKAIServerSentEvent? {
        if line.isEmpty {
            return dispatchEvent()
        }
        // 以冒號開頭的行是註解，直接略過
        if line.utf8.first == UInt8(ascii: ":") {
            return nil
        }
        // 冒號和空白都是 ASCII，不會出現在多位元組字元裡，所以直接比對位元組
        if let colon = line.utf8.firstIndex(of: UInt8(ascii: ":")) {
            let field = String(decoding: line.utf8[..<colon], as: UTF8.self)
            var valueStart = line.utf8.index(after: colon)
            // 值開頭只移除一個空白，其餘的空白保留
            if line.utf8[valueStart...].first == UInt8(ascii: " ") {
                valueStart = line.utf8.index(after: valueStart)
            }
            applyField(field, value: String(decoding: line.utf8[valueStart...], as: UTF8.self))
        } else {
            // 沒有冒號時，整行是欄位名，值為空
            applyField(line, value: "")
        }
        return nil
    }

    /// 串流結束時，丟棄尚未以空行收尾的事件名稱與資料，不送出
    package mutating func finish() {
        eventName = nil
        dataBuffer = ""
    }
}

// MARK: - Private Method

private extension LKAIServerSentEventParser {

    /// 依欄位名套用欄位的值：event 設定事件名稱，data 把值接到資料緩衝，其他欄位略過
    ///
    /// - Parameters:
    ///   - field: 欄位名稱
    ///   - value: 欄位的值，冒號後開頭的一個空白已經移除
    mutating func applyField(_ field: String, value: String) {
        if field == "event" {
            eventName = value
        } else if field == "data" {
            dataBuffer += value
            dataBuffer += "\n"
        }
    }

    /// 遇到空行時，有資料就送出事件並清空；沒有資料就只清除事件名稱
    ///
    /// - Returns: 要送出的事件；沒有資料時為 nil
    mutating func dispatchEvent() -> LKAIServerSentEvent? {
        if dataBuffer.isEmpty {
            eventName = nil
            return nil
        }
        // 每個 data 欄位的值後面都接了一個 LF，送出前去掉最後那一個
        let data = String(decoding: dataBuffer.utf8.dropLast(), as: UTF8.self)
        let event = LKAIServerSentEvent(event: eventName, data: data)
        eventName = nil
        dataBuffer = ""
        return event
    }
}
