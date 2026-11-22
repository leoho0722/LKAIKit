//
//  LKOpenAIErrorBody.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// OpenAI 的錯誤內容，HTTP 錯誤回應、串流中的 `error` 事件與 `response.failed` 的 `response.error` 共用這個格式
///
/// - Note: HTTP 錯誤回應的外層是 `{"error": {…}}`，以 `init?(text:)` 解碼，分類用的是裡面的 `error` 物件
/// - Note: `error` 事件是平的 JSON，沒有巢狀的 `error` 物件，整個事件直接解成 `Detail`；`type` 固定是 `error`，分類不讀它
/// - Note: `response.failed` 的 `response.error` 只有 `code` 與 `message`，也解成 `Detail`
/// - Note: `message`、`type`、`code` 都是 Optional，缺少或為 null 都能解碼，所以缺 `message` 的額度錯誤仍能判斷成額度用完
struct LKOpenAIErrorBody: Decodable {

    // MARK: - Properties

    /// 錯誤的細節，`error.code` 與 `error.type` 決定分類
    let error: Detail

    // MARK: - Init

    /// 解碼 HTTP 錯誤回應的內容；不是合法的 JSON，或缺少 `error` 物件時為 nil，呼叫端改用預設分類
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

extension LKOpenAIErrorBody {

    /// 錯誤的細節：`code` 與 `type` 決定分類，`message` 是給開發者看的文字
    struct Detail: Decodable {

        /// 給開發者看的訊息，例如 `The model 'gpt-0' does not exist.`；沒有或為 null 時為 nil
        let message: String?

        /// 錯誤類型，例如 `insufficient_quota`；沒有或為 null 時為 nil
        let type: String?

        /// 錯誤代碼，例如 `rate_limit_exceeded`；沒有或為 null 時為 nil
        let code: String?

        /// 是否為政策性阻擋，也就是 `code` 是 `cyber_policy`、`bio_policy` 或 `misalignment_policy_violation`
        ///
        /// - Note: 只看 `code`，HTTP 與串流兩條路徑共用
        var isPolicyViolation: Bool {
            guard let code else {
                return false
            }
            return switch code {
            case "cyber_policy", "bio_policy", "misalignment_policy_violation":
                true

            default:
                false
            }
        }

        /// 是否為額度或帳務用完，也就是 `code` 是額度與帳務的代碼
        ///
        /// - Note: 只看 `code`，HTTP 與串流兩條路徑共用
        /// - Note: `error.type` 為 `insufficient_quota` 只在 HTTP 規則判斷，串流不判斷
        /// - Note: 串流 `error` 事件的 `type` 是事件種類，固定為 `error`，不是錯誤類型
        var isQuotaExhausted: Bool {
            guard let code else {
                return false
            }
            return switch code {
            case "insufficient_quota", "billing_hard_limit_reached", "credit_balance_exhausted",
                    "organization_spend_limit_exceeded", "project_spend_limit_exceeded",
                    "organization_usage_limit_exceeded":
                true

            default:
                false
            }
        }

        /// 串流中的 `error` 事件與 `response.failed` 依 `code` 對應成的錯誤
        ///
        /// - Note: 串流中沒有 HTTP 標頭可讀，所以限流不帶等待時間
        /// - Note: 沒有代碼時沒有任何線索可判斷，當成服務暫時無法使用，狀態碼 500
        /// - Note: 不認得的代碼丟 `invalidResponse`，說明帶代碼與訊息，這和 Anthropic 把不認得的類型當成 500 不同
        /// - Note: 官方文件列的錯誤代碼中，多數不是可重試的伺服器端問題，新代碼多半也不可重試，所以不猜成 500
        var streamError: LKAIError {
            if isPolicyViolation {
                return .refused(detail: code)
            }
            if isQuotaExhausted {
                return .quotaExceeded
            }
            guard let code else {
                return .serviceUnavailable(statusCode: 500)
            }
            switch code {
            case "rate_limit_exceeded", "slow_down":
                return .rateLimited(retryAfter: nil)

            case "server_is_overloaded":
                return .serviceUnavailable(statusCode: 503)

            case "server_error", "vector_store_timeout":
                return .serviceUnavailable(statusCode: 500)

            case "invalid_prompt", "data_residency_mismatch":
                return .invalidRequest(message: message)

            default:
                return .invalidResponse(
                    reason: "Unexpected error code \(code): \(message ?? "no message")"
                )
            }
        }

        /// 依 HTTP 狀態碼與錯誤內容對應成錯誤，依序套用第一條符合的規則；都不符合時為 nil，由呼叫端改用預設的狀態碼分類
        ///
        /// - Parameter statusCode: HTTP 回應的狀態碼
        /// - Returns: 政策性阻擋為拒答；額度用完為 `quotaExceeded`；401、402、403、429 以外的 4xx 為帶訊息的無效請求；其餘為 nil
        /// - Note: 政策性阻擋與額度優先於狀態碼，所以 403 與 429 也可能是拒答或額度用完
        /// - Note: 額度用完不讀 `retry-after`，OpenAI 寫明它不表示額度或帳務問題可以靠重試解決
        func httpError(statusCode: Int) -> LKAIError? {
            if isPolicyViolation {
                return .refused(detail: code)
            }
            if isQuotaExhausted || type == "insufficient_quota" {
                return .quotaExceeded
            }
            switch statusCode {
            case 401, 402, 403, 429:
                return nil

            case 400...499:
                return .invalidRequest(message: message)

            default:
                return nil
            }
        }
    }
}
