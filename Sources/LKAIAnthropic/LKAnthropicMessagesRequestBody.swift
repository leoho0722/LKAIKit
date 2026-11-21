//
//  LKAnthropicMessagesRequestBody.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import LKAICore

/// 送給 Anthropic Messages API 的請求內容，編碼成 JSON 後放進 HTTP 請求
///
/// - Note: 不放 `temperature`、`top_p`、`top_k`，API 版本 `2026-10-21` 會拒絕這類取樣參數
struct LKAnthropicMessagesRequestBody: Encodable {

    // MARK: - Properties

    /// 要使用的模型識別碼
    let model: String

    /// 最多輸出的 token 數，編碼成 `max_tokens`
    let maxTokens: Int

    /// 系統指示；沒有時為 nil，此時內容裡不出現 `system` 這個鍵
    let system: String?

    /// 依序排列的對話訊息
    let messages: [Message]

    /// 是否以串流回應，一律為 `true`，非串流呼叫也一樣，再由呼叫端彙整
    let stream = true

    /// 拒答備援設定；沒有開啟時為 nil，此時內容裡不出現 `fallbacks` 這個鍵
    let fallbacks: Fallbacks?

    // MARK: - Init

    /// 依對話請求與備援設定建立請求內容
    ///
    /// - Parameters:
    ///   - request: App 傳入的對話請求
    ///   - refusalFallback: 建立 client 時選擇的拒答備援設定
    init(request: LKAIChatRequest, refusalFallback: LKAnthropicRefusalFallback) {
        model = request.model
        maxTokens = request.maxOutputTokens
        system = request.systemPrompt
        messages = request.messages.map { Message($0) }
        fallbacks = Fallbacks(refusalFallback)
    }
}

// MARK: - Nested Types

extension LKAnthropicMessagesRequestBody {

    /// JSON 的鍵名；只有 `maxTokens` 與 API 的 `max_tokens` 不同
    enum CodingKeys: String, CodingKey {

        /// 模型識別碼
        case model

        /// 最多輸出的 token 數
        case maxTokens = "max_tokens"

        /// 系統指示
        case system

        /// 對話訊息
        case messages

        /// 是否以串流回應
        case stream

        /// 拒答備援設定
        case fallbacks
    }

    /// 一則對話訊息，角色與文字內容
    struct Message: Encodable {

        /// API 要求的角色名稱，`user` 或 `assistant`
        let role: String

        /// 訊息的文字內容
        let content: String

        /// 由函式庫的訊息轉成 API 的格式，角色轉成 API 的角色名稱
        ///
        /// - Parameter message: App 傳入的對話訊息
        init(_ message: LKAIMessage) {
            role = switch message.role {
            case .user:
                "user"

            case .assistant:
                "assistant"
            }
            content = message.text
        }
    }

    /// 開啟拒答備援時放在內容裡的 `fallbacks` 欄位，兩種寫法編碼成不同的 JSON 形狀
    enum Fallbacks: Encodable {

        /// 編碼成字串 `"default"`，由 Anthropic 依拒答類別挑選備援模型
        case automatic

        /// 編碼成 `[{"model": ...}]`，每個指定的模型一個物件，順序照指定的順序
        ///
        /// - Parameter models: 指定的備援模型識別碼
        case models([String])

        /// 由 App 選擇的備援設定轉成內容裡的欄位；沒有開啟時得到 nil，欄位就不會出現
        ///
        /// - Parameter refusalFallback: 建立 client 時選擇的拒答備援設定
        init?(_ refusalFallback: LKAnthropicRefusalFallback) {
            switch refusalFallback {
            case .disabled:
                return nil

            case .automatic:
                self = .automatic

            case .models(let models):
                self = .models(models)
            }
        }

        /// 依備援的寫法編碼：自動備援是字串，指定模型是物件陣列
        ///
        /// - Parameter encoder: 接收 JSON 內容的編碼器
        /// - Throws: 底層編碼失敗時丟出
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .automatic:
                try container.encode("default")

            case .models(let models):
                try container.encode(models.map { ["model": $0] })
            }
        }
    }
}
