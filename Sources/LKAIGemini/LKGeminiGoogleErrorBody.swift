//
//  LKGeminiGoogleErrorBody.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// Google 通用格式的錯誤內容，金鑰無效這類由 Google 的基礎服務擋下的請求，HTTP 錯誤回應用這個格式
///
/// - Note: 外層可以是 `{"error": {…}}` 物件，也可以是只有一個物件的 JSON 陣列，實測是陣列，文件寫的是物件，兩種都接受
/// - Note: 外層是陣列時只取第一個元素，後面的元素不看
/// - Note: `error.code` 是數字，這是它與 Interactions 格式（`code` 是字串）的差別，所以兩種格式不會同時符合
/// - Note: 只用來判斷金鑰是否無效，不解析 `details` 裡的其他內容，例如 `RetryInfo`
struct LKGeminiGoogleErrorBody: Decodable {

    // MARK: - Properties

    /// 錯誤的細節，`error.details` 決定是不是金鑰無效
    let error: Detail

    // MARK: - Init

    /// 解碼 HTTP 錯誤回應的內容；不是合法的 JSON，或不符合這個格式時為 nil，呼叫端改用預設分類
    ///
    /// - Parameter text: 錯誤回應的內容，一段 JSON 文字
    init?(text: String) {
        if let object = try? LKAISnakeCaseJSON.decode(Self.self, from: text) { // 失敗可忽略，因為會改試陣列
            self = object
            return
        }
        let list = try? LKAISnakeCaseJSON.decode(FirstElement.self, from: text) // 失敗可忽略，因為會改用預設分類
        guard let first = list else {
            return nil
        }
        self = first.body
    }
}

// MARK: - Nested Types

extension LKGeminiGoogleErrorBody {

    /// 錯誤的細節：`code` 是數字，`details` 裡的 `reason` 決定是不是金鑰無效
    struct Detail: Decodable {

        /// HTTP 狀態碼的數字，例如 `400`；只用來確認是 Google 通用格式，不影響分類
        let code: Int

        /// 給開發者看的訊息；沒有或為 null 時為 nil
        let message: String?

        /// 狀態名稱，例如 `INVALID_ARGUMENT`；沒有或為 null 時為 nil
        let status: String?

        /// 錯誤的補充項目；沒有或為 null 時為 nil
        let details: [Entry]?

        /// 是否為金鑰無效，也就是 `details` 有一個項目的 `reason` 是 `API_KEY_INVALID`
        var isAPIKeyInvalid: Bool {
            guard let details else {
                return false
            }
            return details.contains { $0.reason == "API_KEY_INVALID" }
        }

        /// `details` 的一個項目，只取原因
        struct Entry: Decodable {

            /// 錯誤的原因，例如 `API_KEY_INVALID`；沒有或為 null 時為 nil
            let reason: String?
        }
    }

    /// 外層是 JSON 陣列時，只解出第一個元素，後面的元素不看
    struct FirstElement: Decodable {

        /// 陣列的第一個元素
        let body: LKGeminiGoogleErrorBody

        /// 只解碼陣列的第一個元素
        ///
        /// - Parameter decoder: 提供 JSON 內容的解碼器
        /// - Throws: 外層不是陣列、陣列是空的，或第一個元素不符合這個格式時丟出 `DecodingError`
        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            body = try container.decode(LKGeminiGoogleErrorBody.self)
        }
    }
}

// MARK: - Internal Method

extension LKGeminiGoogleErrorBody {

    /// 對應成錯誤；只有金鑰無效才有對應，其餘為 nil，由呼叫端改用預設的狀態碼分類
    ///
    /// - Returns: `details` 有 `API_KEY_INVALID` 時為 `invalidAPIKey`，其餘為 nil
    /// - Note: 401 與 403 本來就由預設分類得到 `invalidAPIKey` 與 `permissionDenied`
    func httpError() -> LKAIError? {
        error.isAPIKeyInvalid ? .invalidAPIKey : nil
    }
}
