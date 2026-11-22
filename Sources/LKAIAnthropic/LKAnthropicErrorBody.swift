//
//  LKAnthropicErrorBody.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import LKAICore

/// Anthropic 的錯誤內容，HTTP 錯誤回應與串流中的 `error` 事件共用這個格式
///
/// - Note: 外層是 type 為 error 的 JSON 物件，分類用的是裡面的 error 物件；request_id 等其他欄位略過
/// - Note: 官方文件寫明 `error.type` 之後可能新增，不認得的類型由 `Detail` 的對應回傳 nil，由呼叫端決定 fallback
struct LKAnthropicErrorBody: Decodable {

    // MARK: - Properties

    /// 錯誤的細節，`error.type` 決定分類
    let error: Detail

    // MARK: - Init

    /// 解碼錯誤回應的內容；不是合法的 JSON，或缺少 `error` 物件時為 nil，呼叫端改用預設分類
    ///
    /// - Parameter text: 錯誤回應的內容，一段 JSON 文字
    init?(text: String) {
        let decoded = try? LKAISnakeCaseJSON.decode(Self.self, from: text) // 失敗可忽略，因為會改用預設分類
        guard let body = decoded else {
            return nil
        }
        self = body
    }
}

// MARK: - Nested Types

extension LKAnthropicErrorBody {

    /// `error` 物件：`type` 決定分類，`message` 是給開發者看的文字，`details` 只有花費上限等少數情況才有
    struct Detail: Decodable {

        /// 錯誤類型，例如 `rate_limit_error`
        let type: String

        /// 給開發者看的訊息，例如 `max_tokens: too large`；沒有時為 nil
        let message: String?

        /// 補充細節；沒有時為 nil
        let details: Details?

        /// 依 `type` 對應成 LKAIError，類型不認得時為 nil，由呼叫端決定 fallback
        ///
        /// - Parameters:
        ///   - statusCode: HTTP 回應的狀態碼；串流中的 error 事件沒有，傳 nil，改用規格寫定的狀態碼
        ///   - retryAfter: `retry-after` 標頭的原始值；串流中沒有標頭，傳 nil
        /// - Returns: 對應的錯誤；類型不認得時為 nil
        func lkaiError(statusCode: Int?, retryAfter: String?) -> LKAIError? {
            switch type {
            case "authentication_error":
                return .invalidAPIKey

            case "permission_error":
                return .permissionDenied

            case "billing_error":
                return .quotaExceeded

            case "rate_limit_error":
                return rateLimitError(retryAfter: retryAfter)

            case "invalid_request_error":
                return invalidRequestError

            case "not_found_error", "request_too_large":
                return .invalidRequest(message: message)

            case "api_error":
                return .serviceUnavailable(statusCode: statusCode ?? 500)

            case "overloaded_error":
                return .serviceUnavailable(statusCode: statusCode ?? 529)

            case "timeout_error":
                return .serviceUnavailable(statusCode: statusCode ?? 504)

            default:
                // 不認得的類型不猜，交給呼叫端決定
                return nil
            }
        }

        /// 自設的花費上限以錯誤訊息的開頭辨識，其餘的是無效請求，並帶上訊息
        ///
        /// - Note: 訊息文字改變時不再辨識為花費上限，退回成無效請求，不會誤判成其他錯誤
        private var invalidRequestError: LKAIError {
            if message?.hasPrefix("You have reached your specified") == true {
                return .quotaExceeded
            }
            return .invalidRequest(message: message)
        }

        /// `rate_limit_error`：花費上限用完時是配額用完；否則是限流，並帶上 `retry-after` 換算出的等待時間
        ///
        /// - Parameter retryAfter: `retry-after` 標頭的原始值，串流中為 nil
        /// - Returns: 對應的錯誤
        private func rateLimitError(retryAfter: String?) -> LKAIError {
            if details?.errorCode == "enforced_spend_limit_reached" {
                return .quotaExceeded
            }
            return .rateLimited(retryAfter: LKAIError.retryDelay(from: retryAfter))
        }
    }

    /// `error.details` 物件，目前只用到花費上限的錯誤代碼
    struct Details: Decodable {

        /// 錯誤代碼，花費上限用完時為 `enforced_spend_limit_reached`；沒有時為 nil
        let errorCode: String?
    }
}
