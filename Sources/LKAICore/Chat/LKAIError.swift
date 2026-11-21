//
//  LKAIError.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation

/// 所有對話呼叫失敗時統一丟出的錯誤，依失敗的種類分類，並標示原封不動再送一次請求是否可能成功
///
/// - Note: 之後可能新增 case，App 對它做 `switch` 時必須寫 `@unknown default`
@nonexhaustive
public enum LKAIError: Error, Equatable, Sendable {

    /// API 金鑰無效或已失效，供應商拒絕驗證身分
    case invalidAPIKey

    /// API 金鑰有效，但沒有權限使用這項服務
    case permissionDenied

    /// 短時間內送出太多請求，被供應商限流
    ///
    /// - Parameter retryAfter: 供應商要求等待的時間；沒有提供或無法解讀時為 nil
    case rateLimited(retryAfter: Duration?)

    /// 帳號的用量上限或餘額已用完
    case quotaExceeded

    /// 供應商的服務暫時無法使用，例如過載或維護中
    ///
    /// - Parameter statusCode: 供應商回報的 HTTP 狀態碼；串流中途發生的錯誤沒有 HTTP 狀態碼，由供應商依錯誤類型指定
    case serviceUnavailable(statusCode: Int)

    /// 請求內容有問題，供應商無法處理
    ///
    /// - Parameter message: 供應商給開發者看的技術文字，不放進 `errorDescription`；沒有時為 nil
    case invalidRequest(message: String?)

    /// AI 拒絕回應這個請求
    ///
    /// - Parameter detail: 供應商說明拒答的原因，各家格式不同（類別代碼、說明文字或列舉名），只適合記錄 log，不適合依內容判斷
    case refused(detail: String?)

    /// 呼叫在完成前被取消
    case cancelled

    /// 網路連線失敗，例如沒有網路或連線逾時
    ///
    /// - Parameter underlying: 系統回報的原始網路錯誤，供除錯用
    case transport(underlying: URLError)

    /// 供應商回傳的內容不符預期，無法解讀
    ///
    /// - Parameter reason: 無法解讀的原因，給開發者除錯用
    case invalidResponse(reason: String)

    // MARK: - Init

    /// 依 HTTP 狀態碼與 `retry-after` 標頭做預設分類；供應商自己的錯誤格式分類不了時才使用
    ///
    /// - Parameters:
    ///   - httpStatusCode: 回應的 HTTP 狀態碼，只應傳入 200 到 299 以外的狀態碼
    ///   - retryAfter: `retry-after` 標頭的原始值，沒有標頭時為 nil
    /// - Note: 401、402、403 分別是金鑰無效、用量用完、沒有權限，429 是限流，其他 4xx 是請求有問題
    /// - Note: 5xx 是服務不可用，其餘（含 1xx、3xx 與 600 以上）是無法解讀的回應
    /// - Note: 只有 429 會讀 `retryAfter`，且只接受純 ASCII 數字的秒數；帶正負號、空白或 HTTP 日期都視為沒有提供
    package init(httpStatusCode: Int, retryAfter: String?) {
        switch httpStatusCode {
        case 401:
            self = .invalidAPIKey

        case 402:
            self = .quotaExceeded

        case 403:
            self = .permissionDenied

        case 429:
            self = .rateLimited(retryAfter: Self.retryDelay(from: retryAfter))

        case 400...499:
            self = .invalidRequest(message: nil)

        case 500...599:
            self = .serviceUnavailable(statusCode: httpStatusCode)

        default:
            self = .invalidResponse(reason: "Unexpected HTTP status \(httpStatusCode)")
        }
    }
}

// MARK: - Computed Properties

extension LKAIError {

    /// 是否值得原封不動再送一次同樣的請求：限流、服務不可用與網路失敗為 `true`，其餘為 `false`
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serviceUnavailable, .transport:
            true

        case .invalidAPIKey, .permissionDenied, .quotaExceeded, .invalidRequest, .refused,
                .cancelled, .invalidResponse:
            false
        }
    }

    /// 這個錯誤的說明在 String Catalog 裡的 key，格式為 `error.lkai.<case 名稱>`
    ///
    /// - Note: 只在 `LKAICore` 與它的測試使用，讓說明與測試用同一個 key 查詢
    package var localizationKey: String {
        switch self {
        case .invalidAPIKey:
            "error.lkai.invalidAPIKey"

        case .permissionDenied:
            "error.lkai.permissionDenied"

        case .rateLimited:
            "error.lkai.rateLimited"

        case .quotaExceeded:
            "error.lkai.quotaExceeded"

        case .serviceUnavailable:
            "error.lkai.serviceUnavailable"

        case .invalidRequest:
            "error.lkai.invalidRequest"

        case .refused:
            "error.lkai.refused"

        case .cancelled:
            "error.lkai.cancelled"

        case .transport:
            "error.lkai.transport"

        case .invalidResponse:
            "error.lkai.invalidResponse"
        }
    }
}

// MARK: - Internal Method

extension LKAIError {

    /// 把串流來源丟出的錯誤轉成要交給 App 的錯誤，`LKAIChatStream` 與 `LKAIHTTPLines` 共用同一套規則
    ///
    /// - Parameter error: 串流來源丟出的錯誤
    /// - Returns: 要交給 App 的錯誤；來源丟出 `CancellationError` 或 `.cancelled` 時為 nil，表示串流應正常結束
    /// - Note: 其他 `LKAIError` 原樣交出，不是 `LKAIError` 的錯誤轉成 `.invalidResponse`
    /// - Note: 迭代的 task 已被取消時一律正常結束，這個判斷取決於呼叫端所在的 task，所以由呼叫端先做
    package static func streamFailure(for error: any Error) -> LKAIError? {
        if error is CancellationError {
            return nil
        }
        guard let chatError = error as? LKAIError else {
            return .invalidResponse(reason: "Unexpected error: \(error)")
        }
        guard chatError != .cancelled else {
            return nil
        }
        return chatError
    }
}

// MARK: - LocalizedError

extension LKAIError: LocalizedError {

    /// 顯示給使用者的錯誤說明：每種錯誤一則通用訊息，不含供應商訊息、拒答原因、`URLError` 的文字或 API 金鑰
    ///
    /// - Note: 語言跟隨 App 支援的語言；App 的語言不是 `en`、`zh-Hant` 時用英文
    public var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey), bundle: .module)
    }
}

// MARK: - Private Method

private extension LKAIError {

    /// 把 `retry-after` 標頭的原始值轉成等待時間
    ///
    /// - Parameter rawValue: `retry-after` 標頭的原始值，沒有標頭時為 nil
    /// - Returns: 標頭是純 ASCII 數字時為等待的秒數；其餘情況為 nil，包含空字串與超出 `Int` 範圍的數字
    static func retryDelay(from rawValue: String?) -> Duration? {
        guard let rawValue else {
            return nil
        }
        // 不能直接用 `Int(_:)` 判斷，它會接受 "+5" 與 "-1"；也不能用 `Character.isNumber`，它會接受全形數字
        let isASCIIDigits = rawValue.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
        guard isASCIIDigits, let seconds = Int(rawValue) else {
            return nil
        }
        return .seconds(seconds)
    }
}
