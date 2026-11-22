//
//  LKAITestJSON.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import Testing

/// JSON 的測試 helper，解析請求內容、組出事件資料時用，供各供應商的測試共用
package enum LKAITestJSON {

}

// MARK: - Nested Types

extension LKAITestJSON {

    /// 一個欄位的值：是 JSON 布林就記下來，不是就記成 nil，供 `booleanField(_:in:)` 逐欄位解碼
    private struct OptionalBoolean: Decodable {

        /// 欄位的布林值；欄位的值不是 JSON 布林時為 nil
        let value: Bool?

        /// 從解碼器讀出一個值，是 JSON 布林就記下來，其他型別一律記成 nil
        ///
        /// - Parameter decoder: 解碼器
        init(from decoder: any Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Bool.self) // 失敗可忽略，因為不是布林時記成 nil
        }
    }
}

// MARK: - Internal Method

extension LKAITestJSON {

    /// 把 JSON 文字解析成 JSON 物件，比對時不受鍵的順序影響
    ///
    /// - Parameters:
    ///   - text: JSON 文字，最外層必須是物件
    ///   - sourceLocation: 最外層不是物件時，測試問題記在哪一行；預設是呼叫端那一行，不必傳
    /// - Returns: 解析出的 JSON 物件
    /// - Throws: 文字不是合法的 JSON，或最外層不是物件時丟出
    /// - Note: 最外層不是物件時，問題記在呼叫端的測試檔，不是這個檔案，看得出是哪個測試失敗
    package static func jsonObject(
        from text: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSDictionary {
        try jsonObject(from: Data(text.utf8), sourceLocation: sourceLocation)
    }

    /// 把 JSON 資料解析成 JSON 物件，比對時不受鍵的順序影響
    ///
    /// - Parameters:
    ///   - data: JSON 資料，最外層必須是物件
    ///   - sourceLocation: 最外層不是物件時，測試問題記在哪一行；預設是呼叫端那一行，不必傳
    /// - Returns: 解析出的 JSON 物件
    /// - Throws: 資料不是合法的 JSON，或最外層不是物件時丟出
    /// - Note: 最外層不是物件時，問題記在呼叫端的測試檔，不是這個檔案，看得出是哪個測試失敗
    package static func jsonObject(
        from data: Data,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSDictionary {
        let value = try JSONSerialization.jsonObject(with: data)
        return try #require(value as? NSDictionary, sourceLocation: sourceLocation)
    }

    /// 把 JSON 文字解析成 JSON 值，最外層可以是字串或陣列
    ///
    /// - Parameter text: JSON 文字
    /// - Returns: 解析出的 JSON 值
    /// - Throws: 文字不是合法的 JSON 時丟出
    package static func jsonFragment(from text: String) throws -> NSObject {
        let value = try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: .fragmentsAllowed
        )
        return try #require(value as? NSObject)
    }

    /// 組出 JSON 物件裡可有可無的欄位，前面帶逗號，接在其他欄位之後
    ///
    /// - Parameters:
    ///   - name: 欄位名稱
    ///   - json: 欄位值的 JSON；nil 表示不放這個欄位
    /// - Returns: `,"名稱":值`；沒有值時為空字串
    package static func optionalField(_ name: String, _ json: String?) -> String {
        guard let json else {
            return ""
        }
        return ",\"\(name)\":\(json)"
    }

    /// 以 `JSONDecoder` 取出 JSON 物件裡指定欄位的布林值，只接受 JSON 布林
    ///
    /// - Parameters:
    ///   - name: 欄位名稱，只看最外層物件的欄位
    ///   - data: JSON 資料，最外層必須是物件
    /// - Returns: 欄位的布林值
    /// - Throws: 資料不是合法的 JSON、最外層不是物件、欄位不存在，或欄位不是 JSON 布林時丟出
    /// - Note: 數字 `1` 與字串 `"true"` 都不算 JSON 布林；`NSDictionary` 比對會把 `1` 當成 `true`，
    ///   要確認欄位真的是 JSON 布林時用它
    package static func booleanField(_ name: String, in data: Data) throws -> Bool {
        let fields = try JSONDecoder().decode([String: OptionalBoolean].self, from: data)
        guard let value = fields[name]?.value else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "The field \"\(name)\" is missing or is not a JSON boolean"
                )
            )
        }
        return value
    }
}
