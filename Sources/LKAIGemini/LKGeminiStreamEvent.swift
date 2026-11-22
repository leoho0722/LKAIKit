//
//  LKGeminiStreamEvent.swift
//  LKAIGemini
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// Gemini Interactions API 串流的一筆事件，只解出事件對應規則用得到的欄位
///
/// - Note: 只在 `LKAIGemini` 內使用；事件的 `data` 是 JSON，以 `event_type` 欄位判斷是哪一種事件
/// - Note: 不看 SSE 的 `event:` 那一行，事件種類一律以 `data` 的 `event_type` 為準
/// - Note: 不認得的 `event_type`、不需要對應的事件都解成 `.ignored`，API 之後新增事件時串流不會失敗
/// - Note: 欄位只在用得到時才解碼：`step.start` 的 `content` 只在步驟類型是 `model_output` 時解碼，
///   `step.delta` 的 `text` 只在片段類型是 `text` 時解碼，其他類型帶什麼內容都不影響串流
/// - Note: 認得的事件欄位格式不符時解碼失敗；JSON 的鍵是 snake_case，請用 `init(data:)` 解碼
enum LKGeminiStreamEvent {

    /// `step.start`：一個步驟開始，記錄它的類型；回答步驟開始時就帶著文字的話，也一併交出
    ///
    /// - Parameters:
    ///   - index: 步驟的 `index`，之後的 `step.delta` 靠它找到所屬的步驟
    ///   - type: 步驟的 `step.type`，例如 `thought`、`model_output`
    ///   - texts: 步驟開始時就帶著的文字，依序是 `content` 裡類型為 `text` 的項目的 `text`；
    ///     步驟類型不是 `model_output`，或沒有 `content` 時為空陣列
    case stepStart(index: Int, type: String, texts: [String])

    /// `step.delta`：一個步驟的增量
    ///
    /// - Parameters:
    ///   - index: 增量所屬步驟的 `index`
    ///   - text: 增量的文字；增量類型不是 `text` 時為 nil
    case stepDelta(index: Int, text: String?)

    /// `interaction.completed`：互動結束，帶著結束時的互動
    ///
    /// - Parameter interaction: 即 `interaction`，裡面有結束的狀態、實際回應的模型與用量
    case completed(Interaction)

    /// 其他事件：生命週期、`step.stop`、`error` 等，以及不認得的類型，一律略過
    case ignored

    // MARK: - Init

    /// 把事件的 `data` 解碼成串流事件
    ///
    /// - Parameter data: SSE 事件的 `data`，一段 JSON 文字
    /// - Throws: 不是合法的 JSON，或認得的事件類型欄位格式不符時丟出 `DecodingError`
    /// - Note: 由 `LKAISnakeCaseJSON` 解碼，讓巢狀型別的欄位名稱直接對應 API 的 snake_case 鍵
    init(data: String) throws {
        self = try LKAISnakeCaseJSON.decode(LKGeminiStreamEvent.self, from: data)
    }
}

// MARK: - Nested Types

extension LKGeminiStreamEvent {

    /// 事件最外層用到的鍵
    enum CodingKeys: String, CodingKey {

        /// 事件類型，對應 JSON 的 `event_type`
        case eventType

        /// `step.start` 與 `step.delta` 所屬步驟的序號
        case index

        /// `step.start` 的步驟
        case step

        /// `step.delta` 的增量
        case delta

        /// `interaction.completed` 的互動
        case interaction
    }

    /// `step.start` 的 `step`，只取步驟類型與開始時帶著的文字
    struct Step: Decodable {

        /// 步驟類型，例如 `thought`、`model_output`
        let type: String

        /// 步驟開始時就帶著的文字；步驟類型不是 `model_output`，或沒有 `content` 時為空陣列
        let texts: [String]

        /// 依步驟類型解碼：只有 `model_output` 才讀 `content`，其他類型的欄位不看
        ///
        /// - Parameter decoder: 提供 JSON 內容的解碼器
        /// - Throws: 沒有 `type`，或 `model_output` 的 `content` 有值卻不是項目都有字串 `type` 的陣列，
        ///   或類型為 `text` 的項目沒有字串 `text` 時丟出 `DecodingError`
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let stepType = try container.decode(String.self, forKey: .type)
            type = stepType
            if stepType == "model_output" {
                let parts = try container.decodeIfPresent([TextPart].self, forKey: .content) ?? []
                texts = parts.compactMap { $0.text }
            } else {
                texts = []
            }
        }

        /// 步驟的鍵
        enum CodingKeys: String, CodingKey {

            /// 步驟類型
            case type

            /// 步驟開始時帶著的內容
            case content
        }
    }

    /// 一段帶類型的內容：`step.start` 的 `content` 的一個項目，或 `step.delta` 的 `delta`
    struct TextPart: Decodable {

        /// 類型是 `text` 的文字；其他類型為 nil
        let text: String?

        /// 依類型解碼：只有 `text` 類型才讀文字，其他類型的欄位不看
        ///
        /// - Parameter decoder: 提供 JSON 內容的解碼器
        /// - Throws: 沒有字串 `type`，或 `text` 類型沒有字串 `text`（沒有、null 或型別不對）時丟出 `DecodingError`
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let partType = try container.decode(String.self, forKey: .type)
            if partType == "text" {
                text = try container.decode(String.self, forKey: .text)
            } else {
                text = nil
            }
        }

        /// 內容的鍵
        enum CodingKeys: String, CodingKey {

            /// 內容類型
            case type

            /// `text` 類型的文字
            case text
        }
    }

    /// `interaction.completed` 的 `interaction`，只取結束的狀態、實際回應的模型與用量
    ///
    /// - Note: 不讀 `errors`，沒有宣告的欄位自動略過
    struct Interaction: Decodable {

        /// 互動結束的狀態，例如 `completed`、`incomplete`；沒有時為 nil
        let status: String?

        /// 實際回應的模型識別碼；API 沒有回報時為 nil，這不是錯誤
        let model: String?

        /// 這次互動的用量；為 null 或沒有這個欄位時為 nil
        let usage: Usage?
    }

    /// 互動的用量；API 沒有回報或回報 null 的欄位是 nil，代表沒有回報
    struct Usage: Decodable {

        /// 輸入 token 總數，已包含讀自快取的部分
        let totalInputTokens: Int?

        /// 讀自快取的輸入 token 數
        let totalCachedTokens: Int?

        /// 輸出 token 總數，不含思考的部分
        let totalOutputTokens: Int?

        /// 用在思考的輸出 token 數
        let totalThoughtTokens: Int?
    }
}

// MARK: - Decodable

extension LKGeminiStreamEvent: Decodable {

    /// 依 `event_type` 欄位決定是哪一種事件，再解出該事件用得到的欄位；不認得的類型解成 `.ignored`
    ///
    /// - Parameter decoder: 提供 JSON 內容的解碼器
    /// - Throws: 沒有字串 `event_type`，或認得的類型缺少必要欄位、欄位格式不符時丟出 `DecodingError`
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(String.self, forKey: .eventType)
        switch eventType {
        case "step.start":
            let index = try container.decode(Int.self, forKey: .index)
            let step = try container.decode(Step.self, forKey: .step)
            self = .stepStart(index: index, type: step.type, texts: step.texts)

        case "step.delta":
            let index = try container.decode(Int.self, forKey: .index)
            let delta = try container.decode(TextPart.self, forKey: .delta)
            self = .stepDelta(index: index, text: delta.text)

        case "interaction.completed":
            self = try .completed(container.decode(Interaction.self, forKey: .interaction))

        default:
            self = .ignored
        }
    }
}
