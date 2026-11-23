//
//  LKAILocalization.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation

/// 以指定的語言查 String Catalog 的字串，不受行程目前的語言設定影響
///
/// - Note: 只給同一個 package 內的 target 使用，所以是 `package` 層級，不是公開 API
package enum LKAILocalization {

}

// MARK: - Internal Method

extension LKAILocalization {

    /// 以指定的語言查 String Catalog 裡的字串
    ///
    /// - Parameters:
    ///   - key: String Catalog 的 key
    ///   - bundle: 放著 String Catalog 的 bundle，例如 `LKAICore` 的 `Bundle.module`
    ///   - localization: 語言資料夾的名稱，不含 `.lproj`，例如 `en`、`zh-Hant`
    /// - Returns: 指定語言的字串；沒有該語言的資料夾時，改用 bundle 預設的查詢結果；
    ///   查不到 key 時和 Foundation 一樣回傳 key
    /// - Note: bundle 預設的查詢跟隨行程的語言設定，`locale:` 也決定不了語言，
    ///   只有取 `<語言>.lproj` 子 bundle 查詢，才能由呼叫端指定語言
    /// - Note: 查詢時 `value`、`table` 都傳 nil，所以查不到 key 時回傳的是 key 本身，不是空字串
    package static func string(
        forKey key: String,
        in bundle: Bundle,
        localization: String
    ) -> String {
        guard let languagePath = bundle.path(forResource: localization, ofType: "lproj"),
              let languageBundle = Bundle(path: languagePath) else {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return languageBundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
