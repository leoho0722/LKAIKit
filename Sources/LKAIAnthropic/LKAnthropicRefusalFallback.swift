//
//  LKAnthropicRefusalFallback.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import LKAICore

/// Anthropic 的伺服器端拒答備援設定，由 App 建立 `LKAnthropicClient` 時選擇要不要開啟
///
/// - Note: 備援只在政策性拒答時觸發；開啟後可能改由另一個模型回答，並以那個模型的費率計費，所以預設關閉
/// - Note: 開啟時請求會帶 `anthropic-beta: server-side-fallback-2026-07-01`，這是 beta 功能，格式可能變動
/// - Note: 開啟時頂層用量只涵蓋最後產生回應的那一次嘗試，被拒答的嘗試另外計費；本套件不加總 `usage.iterations`
/// - Note: Claude Haiku 5.5 沒有伺服器端備援：`.automatic` 時拒答照常回報，`.models` 時 API 回 400
public enum LKAnthropicRefusalFallback: Equatable, Sendable {

    /// 不使用備援，拒答照常回報；建立 client 時沒有指定的預設值
    case disabled

    /// 送出 `"fallbacks": "default"`，由 Anthropic 依拒答類別挑選備援模型
    case automatic

    /// 指定備援模型，依指定的順序嘗試
    ///
    /// - Parameter models: 1 到 3 個不重複、非空的模型識別碼；不符合時不送請求，直接丟出 `invalidRequest`
    /// - Note: 備援模型不可與請求的模型相同，也要在原模型允許的備援名單內
    /// - Note: 請求的模型每次呼叫才指定，這兩點由 API 判斷，不允許時 API 回 400，成為 `invalidRequest`
    case models([String])
}

// MARK: - Computed Properties

extension LKAnthropicRefusalFallback {

    /// 開啟備援時請求要帶的 `anthropic-beta` 標頭值；沒有開啟時為 nil，請求不帶這個標頭
    var betaHeaderValue: String? {
        switch self {
        case .disabled:
            nil

        case .automatic, .models:
            "server-side-fallback-2026-07-01"
        }
    }
}

// MARK: - Internal Method

extension LKAnthropicRefusalFallback {

    /// 檢查設定是否合法，送出網路請求前呼叫
    ///
    /// - Throws: 指定的模型清單為空、超過 3 個、有重複或含空字串時丟出 `invalidRequest`
    /// - Note: 訊息是給開發者看的英文，指出違反的是哪一條
    /// - Note: 依序檢查，只丟出第一個違反的規則
    func validate() throws(LKAIError) {
        switch self {
        case .disabled, .automatic:
            return

        case .models(let models):
            let maximumModelCount = 3
            if models.isEmpty {
                throw .invalidRequest(message: "refusal fallback models must not be empty")
            }
            if models.count > maximumModelCount {
                throw .invalidRequest(message: "refusal fallback models must not exceed 3 models")
            }
            if Set(models).count != models.count {
                throw .invalidRequest(message: "refusal fallback models must not repeat a model")
            }
            if models.contains("") {
                throw .invalidRequest(message: "refusal fallback model names must not be empty")
            }
        }
    }
}
