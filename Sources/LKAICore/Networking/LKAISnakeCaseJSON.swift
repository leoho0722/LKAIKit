//
//  LKAISnakeCaseJSON.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation

/// 解碼 snake_case JSON 的共用入口，供應商的 JSON 鍵是 snake_case 時一律用它解碼，不自己建立 `JSONDecoder`
///
/// - Note: 以 `.convertFromSnakeCase` 解碼，型別的 camelCase 欄位名稱直接對應 API 的 snake_case 鍵
/// - Note: 解碼設定只寫在這一處，各供應商不會各自設定出不同的行為
package enum LKAISnakeCaseJSON {

}

// MARK: - Internal Method

extension LKAISnakeCaseJSON {

    /// 把 UTF-8 的 JSON 文字解碼成指定的型別
    ///
    /// - Parameters:
    ///   - type: 要解碼成的型別
    ///   - text: 一段 JSON 文字
    /// - Returns: 解碼出的值
    /// - Throws: 不是合法的 JSON，或內容與型別不符時丟出 `DecodingError`
    package static func decode<Value: Decodable>(
        _ type: Value.Type,
        from text: String
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
