//
//  LKOpenAIStreamEvent.swift
//  LKAIOpenAI
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// OpenAI Responses API 串流的一筆事件，只解出事件對應規則用得到的欄位
///
/// - Note: 只在 `LKAIOpenAI` 內使用；事件的 `data` 是 JSON，以 `type` 欄位判斷是哪一種事件，不看 `event:` 那一行
/// - Note: 不認得的 `type`、不需要對應的事件都解成 `.ignored`，API 之後新增事件時串流不會失敗
/// - Note: 只宣告用得到的欄位，`obfuscation`、`logprobs` 這類沒有宣告的欄位自動略過
/// - Note: 認得的 `type` 欄位格式不符時解碼失敗；JSON 的鍵是 snake_case，請用 `init(data:)` 解碼
enum LKOpenAIStreamEvent {

    /// `response.output_text.delta`：一段新產生的回答文字
    ///
    /// - Parameter string: 這一段文字，即 `delta`
    case outputTextDelta(String)

    /// `response.completed`：回應完成，帶著完整的回應物件
    ///
    /// - Parameter response: 即 `response`，裡面有實際回應的模型與用量
    case completed(Response)

    /// `response.refusal.delta`：一段新產生的拒答文字
    ///
    /// - Parameter string: 這一段拒答文字，即 `delta`
    case refusalDelta(String)

    /// `response.refusal.done`：拒答文字結束，帶著完整的拒答文字
    ///
    /// - Parameter string: 完整的拒答文字，即 `refusal`
    case refusalDone(String)

    /// `response.incomplete`：回應沒有完成，帶著完整的回應物件
    ///
    /// - Parameter response: 即 `response`，裡面有沒有完成的原因、實際回應的模型與用量
    case incomplete(Response)

    /// `response.failed`：回應失敗，帶著完整的回應物件
    ///
    /// - Parameter response: 即 `response`，失敗的原因在 `response.error`；沒有時為 nil
    case failed(Response)

    /// `error`：串流中途的錯誤，整個事件就是錯誤內容；由 `LKOpenAIStreamState.handle(_:)` 對應成錯誤丟出
    ///
    /// - Parameter detail: 錯誤內容，即事件的 JSON
    case error(LKOpenAIErrorBody.Detail)

    /// 其他事件：生命週期、推理摘要、`response.output_text.done` 等，以及不認得的類型，一律略過
    case ignored

    // MARK: - Init

    /// 把事件的 `data` 解碼成串流事件
    ///
    /// - Parameter data: SSE 事件的 `data`，一段 JSON 文字
    /// - Throws: 不是合法的 JSON，或認得的事件類型欄位格式不符時丟出 `DecodingError`
    /// - Note: 由 `LKAISnakeCaseJSON` 解碼，讓巢狀型別的欄位名稱直接對應 API 的 snake_case 鍵
    init(data: String) throws {
        self = try LKAISnakeCaseJSON.decode(LKOpenAIStreamEvent.self, from: data)
    }
}

// MARK: - Nested Types

extension LKOpenAIStreamEvent {

    /// 事件最外層用到的鍵
    enum CodingKeys: String, CodingKey {

        /// 事件類型
        case type

        /// `response.output_text.delta` 與 `response.refusal.delta` 的文字片段
        case delta

        /// `response.refusal.done` 的完整拒答文字
        case refusal

        /// `response.completed`、`response.incomplete` 與 `response.failed` 的回應物件
        case response
    }

    /// `response.completed`、`response.incomplete` 與 `response.failed` 的 `response`
    ///
    /// - Note: 只取失敗的原因、沒有完成的原因、實際回應的模型與用量
    struct Response: Decodable {

        /// 實際回應的模型識別碼；API 沒有回報時為 nil，這不是錯誤
        let model: String?

        /// 這次回應的用量；為 null 或沒有這個欄位時為 nil
        let usage: Usage?

        /// 回應沒有完成的細節；為 null 或沒有這個欄位時為 nil
        let incompleteDetails: IncompleteDetails?

        /// 回應失敗的錯誤內容，只有 `response.failed` 才有；為 null 或沒有這個欄位時為 nil
        let error: LKOpenAIErrorBody.Detail?

        /// 回應沒有完成的細節，目前只用到原因
        struct IncompleteDetails: Decodable {

            /// 沒有完成的原因，例如 `max_output_tokens`；API 沒有回報時為 nil
            let reason: String?
        }
    }

    /// 回應的用量；API 沒有回報或回報 null 的欄位是 nil，代表沒有回報
    struct Usage: Decodable {

        /// 輸入 token 總數，已包含讀自快取的部分
        let inputTokens: Int?

        /// 輸入 token 的細項
        let inputTokensDetails: InputTokensDetails?

        /// 輸出 token 總數，已包含推理的部分
        let outputTokens: Int?

        /// 輸出 token 的細項
        let outputTokensDetails: OutputTokensDetails?

        /// 輸入 token 的細項，目前只用到快取的部分
        struct InputTokensDetails: Decodable {

            /// 讀自快取的輸入 token 數
            let cachedTokens: Int?
        }

        /// 輸出 token 的細項，目前只用到推理的部分
        struct OutputTokensDetails: Decodable {

            /// 用在推理的輸出 token 數
            let reasoningTokens: Int?
        }
    }
}

// MARK: - Decodable

extension LKOpenAIStreamEvent: Decodable {

    /// 依 `type` 欄位決定是哪一種事件，再解出該事件用得到的欄位；不認得的類型解成 `.ignored`
    ///
    /// - Parameter decoder: 提供 JSON 內容的解碼器
    /// - Throws: 沒有 `type` 欄位，或認得的類型缺少必要欄位、欄位格式不符時丟出 `DecodingError`
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "response.output_text.delta":
            self = try .outputTextDelta(container.decode(String.self, forKey: .delta))

        case "response.refusal.delta":
            self = try .refusalDelta(container.decode(String.self, forKey: .delta))

        case "response.refusal.done":
            self = try .refusalDone(container.decode(String.self, forKey: .refusal))

        case "response.completed":
            self = try .completed(container.decode(Response.self, forKey: .response))

        case "response.incomplete":
            self = try .incomplete(container.decode(Response.self, forKey: .response))

        case "response.failed":
            self = try .failed(container.decode(Response.self, forKey: .response))

        case "error":
            self = try .error(LKOpenAIErrorBody.Detail(from: decoder))

        default:
            self = .ignored
        }
    }
}
