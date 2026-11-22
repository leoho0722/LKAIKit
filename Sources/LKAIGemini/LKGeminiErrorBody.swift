//
//  LKGeminiErrorBody.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// Gemini Interactions API 的錯誤內容，HTTP 錯誤回應、串流中的 `error` 事件與 `failed` 的 `errors` 共用這個格式
///
/// - Note: HTTP 錯誤回應的外層是 `{"error": {…}}`，以 `init?(text:)` 解碼，分類用的是裡面的 `error` 物件
/// - Note: `error` 事件在 `error` 鍵裡放同樣的物件，`failed` 的 `errors` 每一筆也是，所以三處共用 `Detail`
/// - Note: `code` 與 `message` 都是字串，缺少或為 null 都能解碼；`code` 是數字時解碼失敗
/// - Note: Google 通用格式的 `error.code` 是數字，不在這裡解碼，見 `LKGeminiGoogleErrorBody`
struct LKGeminiErrorBody: Decodable {

    // MARK: - Properties

    /// 錯誤的細節，`error.code` 決定分類
    let error: Detail

    // MARK: - Init

    /// 解碼 HTTP 錯誤回應的內容；不是合法的 JSON，或缺少 `error` 物件時為 nil，呼叫端改試別的格式
    ///
    /// - Parameter text: 錯誤回應的內容，一段 JSON 文字
    init?(text: String) {
        let decoded = try? LKAISnakeCaseJSON.decode(Self.self, from: text) // 失敗可忽略，因為會改試別的格式
        guard let body = decoded else {
            return nil
        }
        self = body
    }
}

// MARK: - Nested Types

extension LKGeminiErrorBody {

    /// 錯誤的細節：`code` 決定分類，`message` 是給開發者看的文字
    struct Detail: Decodable {

        /// 給開發者看的訊息，例如 `Model 'gemini-0' not found.`；沒有或為 null 時為 nil
        let message: String?

        /// 錯誤代碼，例如 `quota_exceeded`；沒有或為 null 時為 nil
        let code: String?

        /// 是否為生成被擋下的代碼，也就是 `code` 是被擋下的 12 個代碼之一
        ///
        /// - Note: 只看 `code`，HTTP 與串流兩條路徑共用
        /// - Note: 被擋下回報的是代碼，不是 `message`：`message` 以 `Input blocked:` 開頭，可能描述使用者的輸入
        var isBlocked: Bool {
            guard let code else {
                return false
            }
            return switch code {
            case "safety", "jailbreak", "prohibited_content", "blocklist", "recitation", "language",
                    "spii", "content_blocked", "image_safety", "image_prohibited_content",
                    "image_recitation", "image_other":
                true

            default:
                false
            }
        }

        /// 是否為額度或帳務用完，也就是 `code` 是 `quota_exceeded` 或 `payment_required`
        ///
        /// - Note: 只看 `code`，HTTP 與串流兩條路徑共用
        var isQuotaExhausted: Bool {
            code == "quota_exceeded" || code == "payment_required"
        }

        /// 串流中的 `error` 事件與 `failed` 的 `errors` 依 `code` 對應成的錯誤
        ///
        /// - Note: 串流中沒有 HTTP 標頭可讀，所以限流與服務不可用都不帶等待時間
        /// - Note: 沒有代碼與不認得的代碼，都依 chat-client「Unrecognized stream errors」的共同規則，
        ///   由 `LKAIError.unrecognizedStreamError(code:message:)` 回報
        var streamError: LKAIError {
            if isBlocked {
                return .refused(detail: code)
            }
            if isQuotaExhausted {
                return .quotaExceeded
            }
            guard let code else {
                return .unrecognizedStreamError(code: nil, message: message)
            }
            switch code {
            case "rate_limit_exceeded", "too_many_requests":
                return .rateLimited(retryAfter: nil)

            case "api_error":
                return .serviceUnavailable(statusCode: 500, retryAfter: nil)

            case "bad_gateway":
                return .serviceUnavailable(statusCode: 502, retryAfter: nil)

            case "service_unavailable":
                return .serviceUnavailable(statusCode: 503, retryAfter: nil)

            case "deadline_exceeded", "gateway_timeout":
                return .serviceUnavailable(statusCode: 504, retryAfter: nil)

            case "authentication":
                return .invalidAPIKey

            case "permission_denied":
                return .permissionDenied

            case "invalid_request":
                return .invalidRequest(message: message)

            default:
                return .unrecognizedStreamError(code: code, message: message)
            }
        }

        /// 依 HTTP 狀態碼與錯誤內容對應成錯誤，依序套用第一條符合的規則；都不符合時為 nil，由呼叫端改用預設的狀態碼分類
        ///
        /// - Parameter statusCode: HTTP 回應的狀態碼
        /// - Returns: 被擋下的代碼為拒答；額度代碼為 `quotaExceeded`；401、402、403、429 以外的 4xx 為帶訊息的無效請求；其餘為 nil
        /// - Note: 被擋下的代碼與額度代碼優先於狀態碼，所以 400 與 429 也可能是拒答或額度用完
        /// - Note: 額度用完不讀 `retry-after`：`quota_exceeded` 要等每日額度重置、`payment_required` 要補餘額，重試沒有用
        func httpError(statusCode: Int) -> LKAIError? {
            if isBlocked {
                return .refused(detail: code)
            }
            if isQuotaExhausted {
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
