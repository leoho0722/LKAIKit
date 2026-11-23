//
//  LKAIError+Details.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit

// MARK: - Computed Properties

extension LKAIError {

    /// 給 `lkai` 印在 `Details:` 行的技術細節，不翻譯；沒有細節時為 nil
    ///
    /// - Note: 格式照 cli-chat「Service failure reporting」的表：
    ///   `invalidRequest` 與 `refused` 是供應商給的文字，`invalidResponse` 是原因，
    ///   `transport` 是 `URLError <代碼>`，`rateLimited` 是 `retry after <n> seconds`，
    ///   `serviceUnavailable` 是 `status <狀態碼>`，有等待時間時再加 `, retry after <n> seconds`
    /// - Note: `invalidAPIKey`、`permissionDenied`、`quotaExceeded`、`cancelled` 沒有細節
    /// - Note: 等待時間以 `Duration` 的 `components.seconds` 轉成整數秒
    /// - Note: 細節是空字串時視同沒有細節，不會多印一行空的 `Details:`
    /// - Note: `switch` 對 `LKAIError` 列出每個 case，不留萬用分支：同一個 package，
    ///   新增 case 時這裡要編譯失敗，才一定會被處理
    /// - Note: 細節裡可能出現供應商回顯的 API 金鑰，印出前要遮蔽，由 `LKAIChatRunner` 處理
    var details: String? {
        guard let rawDetails, !rawDetails.isEmpty else {
            return nil
        }
        return rawDetails
    }
}

// MARK: - Private Method

private extension LKAIError {

    /// 各種錯誤的細節，還沒有排除空字串
    var rawDetails: String? {
        let retryAfterText: (Duration) -> String = { retryAfter in
            "retry after \(retryAfter.components.seconds) seconds"
        }
        switch self {
        case .invalidAPIKey, .permissionDenied, .quotaExceeded, .cancelled:
            return nil

        case .rateLimited(let retryAfter):
            return retryAfter.map(retryAfterText)

        case .serviceUnavailable(let statusCode, let retryAfter):
            guard let retryAfter else {
                return "status \(statusCode)"
            }
            return "status \(statusCode), \(retryAfterText(retryAfter))"

        case .invalidRequest(let message):
            return message

        case .refused(let detail):
            return detail

        case .transport(let underlying):
            return "URLError \(underlying.code.rawValue)"

        case .invalidResponse(let reason):
            return reason
        }
    }
}
