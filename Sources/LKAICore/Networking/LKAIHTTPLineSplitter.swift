//
//  LKAIHTTPLineSplitter.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 把收到的位元組切成一行一行的文字，每次收一個位元組，遇到 CR（\r，0x0D）、LF（\n，0x0A）或 CRLF 就結束一行
///
/// - Note: CR 後面緊接 LF 時只算一次換行，空行會保留
/// - Note: U+2028、U+2029、U+0085 不算換行，中文等多位元組字元會完整留在同一行
/// - Note: 不用 `URLSession.AsyncBytes.lines`，因為它會丟掉空行，而事件串流要靠空行判斷事件結束
/// - Note: 它也會在 U+2028 等字元處切開，會把 JSON 字串切壞
package struct LKAIHTTPLineSplitter: Sendable {

    // MARK: - Properties

    /// 目前這一行已經收到、還沒結束的位元組
    private var pendingBytes: [UInt8] = []

    /// 上一個位元組是否為 CR，是的話緊接著的 LF 是 CRLF 的後半，要略過
    private var isAfterCarriageReturn = false

    // MARK: - Init

    /// 建立一個還沒有收到任何位元組的切行器
    package init() {}
}

// MARK: - Internal Method

extension LKAIHTTPLineSplitter {

    /// 輸入一個位元組；這個位元組讓一行結束時回傳那一行，否則回傳 nil
    ///
    /// - Parameter byte: 收到的一個位元組
    /// - Returns: 剛結束的那一行，不含 CR 與 LF；這個位元組沒有讓一行結束時為 nil
    package mutating func append(_ byte: UInt8) -> String? {
        if byte == UInt8(ascii: "\n") {
            // 緊接在 CR 之後的 LF 是 CRLF 的後半，那一行在 CR 時已經結束，這裡只略過它
            if isAfterCarriageReturn {
                isAfterCarriageReturn = false
                return nil
            }
            return takeLine()
        }
        if byte == UInt8(ascii: "\r") {
            // 收到 CR 就立即結束這一行，不等下一個位元組，避免串流延遲
            isAfterCarriageReturn = true
            return takeLine()
        }
        isAfterCarriageReturn = false
        pendingBytes.append(byte)
        return nil
    }

    /// 串流結束時，交出還沒結束的最後一段內容；沒有內容時回傳 nil
    ///
    /// - Returns: 最後一段還沒結束的內容，不含 CR 與 LF；沒有內容時為 nil
    package mutating func finish() -> String? {
        isAfterCarriageReturn = false
        guard !pendingBytes.isEmpty else {
            return nil
        }
        return takeLine()
    }
}

// MARK: - Private Method

private extension LKAIHTTPLineSplitter {

    /// 把目前累積的位元組解碼成一行，並清空累積的位元組
    ///
    /// - Returns: 解碼後的一行，不含 CR 與 LF；不合法的 UTF-8 位元組會以替代字元 U+FFFD 取代
    mutating func takeLine() -> String {
        let line = String(decoding: pendingBytes, as: UTF8.self)
        pendingBytes.removeAll()
        return line
    }
}
