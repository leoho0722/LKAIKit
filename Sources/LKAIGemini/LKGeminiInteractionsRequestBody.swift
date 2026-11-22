//
//  LKGeminiInteractionsRequestBody.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 送給 Gemini Interactions API 的請求內容，編碼成 JSON 後放進 HTTP 請求
///
/// - Note: 不放 `temperature`、`top_p`、`top_k` 與思考設定，取樣與思考一律採用 API 預設值
/// - Note: Gemini 4 與 3.6 以上的模型，文件寫明會忽略取樣參數
/// - Note: 以沒有 snake_case 策略的 `JSONEncoder` 編碼，所以多字的鍵都要在 `CodingKeys` 寫出原始值
struct LKGeminiInteractionsRequestBody: Encodable {

    // MARK: - Properties

    /// 要使用的模型識別碼
    let model: String

    /// 系統指示；沒有時為 nil，此時內容裡不出現 `system_instruction` 這個鍵
    let systemInstruction: String?

    /// 依序排列的對話步驟，每則訊息一個步驟
    let input: [Step]

    /// 生成設定，只放最多輸出的 token 數
    let generationConfig: GenerationConfig

    /// 是否以串流回應，一律為 `true`，非串流呼叫也一樣，再由呼叫端彙整
    let stream = true

    /// 是否讓 Gemini 保存這次的回應，由 App 建立 client 時決定
    let store: Bool

    // MARK: - Init

    /// 依對話請求與保存設定建立請求內容
    ///
    /// - Parameters:
    ///   - request: App 傳入的對話請求
    ///   - shouldStoreResponses: 建立 client 時選擇的回應保存設定
    init(request: LKAIChatRequest, shouldStoreResponses: Bool) {
        model = request.model
        systemInstruction = request.systemPrompt
        input = request.messages.map { Step($0) }
        generationConfig = GenerationConfig(maxOutputTokens: request.maxOutputTokens)
        store = shouldStoreResponses
    }
}

// MARK: - Nested Types

extension LKGeminiInteractionsRequestBody {

    /// JSON 的鍵名；`systemInstruction` 與 `generationConfig` 與 API 的 snake_case 鍵不同
    enum CodingKeys: String, CodingKey {

        /// 模型識別碼
        case model

        /// 系統指示
        case systemInstruction = "system_instruction"

        /// 對話步驟
        case input

        /// 生成設定
        case generationConfig = "generation_config"

        /// 是否以串流回應
        case stream

        /// 是否保存回應
        case store
    }

    /// 一個對話步驟，對應一則訊息：步驟類型與內容
    struct Step: Encodable {

        /// API 要求的步驟類型，使用者的訊息是 `user_input`，助理的訊息是 `model_output`
        let type: String

        /// 步驟的內容，只有一段文字
        let content: [Content]

        /// 由函式庫的訊息轉成 API 的格式，角色轉成 API 的步驟類型
        ///
        /// - Parameter message: App 傳入的對話訊息
        init(_ message: LKAIMessage) {
            type = switch message.role {
            case .user:
                "user_input"

            case .assistant:
                "model_output"
            }
            content = [Content(text: message.text)]
        }
    }

    /// 步驟內容的一段文字
    struct Content: Encodable {

        /// 內容類型，一律為 `text`
        let type = "text"

        /// 文字內容
        let text: String
    }

    /// 生成設定，只放最多輸出的 token 數
    struct GenerationConfig: Encodable {

        /// 最多輸出的 token 數，編碼成 `max_output_tokens`，照 App 傳入的值送出
        let maxOutputTokens: Int

        /// JSON 的鍵名；`maxOutputTokens` 與 API 的 `max_output_tokens` 不同
        enum CodingKeys: String, CodingKey {

            /// 最多輸出的 token 數
            case maxOutputTokens = "max_output_tokens"
        }
    }
}
