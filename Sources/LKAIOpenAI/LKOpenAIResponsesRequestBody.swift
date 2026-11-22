//
//  LKOpenAIResponsesRequestBody.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 送給 OpenAI Responses API 的請求內容，編碼成 JSON 後放進 HTTP 請求
///
/// - Note: 不放 `temperature`、`top_p`、`reasoning`，推理與取樣設定一律採用 API 預設值
/// - Note: `gpt-6-luna` 這類推理模型的 effort 不是 `none` 時，文件要求不要送 `temperature` 與 `top_p`
struct LKOpenAIResponsesRequestBody: Encodable {

    // MARK: - Properties

    /// 要使用的模型識別碼
    let model: String

    /// 系統指示；沒有時為 nil，此時內容裡不出現 `instructions` 這個鍵
    let instructions: String?

    /// 依序排列的對話訊息
    let input: [Message]

    /// 最多輸出的 token 數，編碼成 `max_output_tokens`，照 App 傳入的值送出
    let maxOutputTokens: Int

    /// 是否以串流回應，一律為 `true`，非串流呼叫也一樣，再由呼叫端彙整
    let stream = true

    /// 是否讓 OpenAI 保存這次的回應，由 App 建立 client 時決定
    let store: Bool

    // MARK: - Init

    /// 依對話請求與保存設定建立請求內容
    ///
    /// - Parameters:
    ///   - request: App 傳入的對話請求
    ///   - shouldStoreResponses: 建立 client 時選擇的回應保存設定
    init(request: LKAIChatRequest, shouldStoreResponses: Bool) {
        model = request.model
        instructions = request.systemPrompt
        input = request.messages.map { Message($0) }
        maxOutputTokens = request.maxOutputTokens
        store = shouldStoreResponses
    }
}

// MARK: - Nested Types

extension LKOpenAIResponsesRequestBody {

    /// JSON 的鍵名；只有 `maxOutputTokens` 與 API 的 `max_output_tokens` 不同
    enum CodingKeys: String, CodingKey {

        /// 模型識別碼
        case model

        /// 系統指示
        case instructions

        /// 對話訊息
        case input

        /// 最多輸出的 token 數
        case maxOutputTokens = "max_output_tokens"

        /// 是否以串流回應
        case stream

        /// 是否保存回應
        case store
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
}
