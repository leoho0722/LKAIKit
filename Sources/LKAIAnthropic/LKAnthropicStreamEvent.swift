//
//  LKAnthropicStreamEvent.swift
//  LKAIAnthropic
//
//  Created by Leo Ho on 2026/11/21.
//

import Foundation

/// Anthropic Messages API 串流的一筆事件，只解出事件對應規則用得到的欄位
///
/// - Note: 只在 `LKAIAnthropic` 內使用；事件的 `data` 是 JSON，以 `type` 欄位判斷是哪一種事件
/// - Note: 不認得的 `type`、不需要對應的區塊與增量都解成 `.ignored`，API 之後新增事件時串流不會失敗
/// - Note: 認得的 `type` 欄位格式不符時解碼失敗；JSON 的鍵是 snake_case，請用 `init(data:)` 解碼
enum LKAnthropicStreamEvent {

    /// `message_start`：訊息開始，帶回應的模型與開頭回報的用量
    ///
    /// - Parameters:
    ///   - model: `message.model`；沒有備援切換時就是實際回應的模型
    ///   - usage: `message.usage`；API 沒有回報時為 nil
    case messageStart(model: String, usage: Usage?)

    /// `content_block_start` 的 `fallback` 區塊：伺服器端的拒答備援把回答切換到另一個模型
    ///
    /// - Parameter toModel: 切換後的模型，即 `content_block.to.model`
    case fallback(toModel: String)

    /// `content_block_delta` 的 `text_delta`：一段新產生的文字
    ///
    /// - Parameter string: 這一段文字
    case textDelta(String)

    /// `message_delta`：訊息層級的更新，帶結束原因與累計的用量；一個串流可能有多個
    ///
    /// - Parameters:
    ///   - stopReason: `delta.stop_reason`；為 null 時是 nil
    ///   - refusalCategory: `delta.stop_details.category`；沒有 `stop_details` 或類別為 null 時是 nil
    ///   - usage: 頂層的 `usage`，各欄位是累計值；沒有時為 nil
    case messageDelta(stopReason: String?, refusalCategory: String?, usage: Usage?)

    /// `message_stop`：訊息結束，這時才依結束原因交出結束事件或丟出錯誤
    case messageStop

    /// `error`：串流中途的錯誤，整個事件就是錯誤內容；由 `LKAnthropicClient` 對應成錯誤丟出，不交給串流狀態
    ///
    /// - Parameter body: 錯誤內容，即事件的 JSON
    case error(LKAnthropicErrorBody)

    /// 其他事件：`ping`、`content_block_stop`、其他類型的區塊與增量，以及不認得的類型，一律略過
    case ignored

    // MARK: - Init

    /// 把事件的 `data` 解碼成串流事件
    ///
    /// - Parameter data: SSE 事件的 `data`，一段 JSON 文字
    /// - Throws: 不是合法的 JSON，或認得的事件類型欄位格式不符時丟出 `DecodingError`
    /// - Note: 解碼時套用 `convertFromSnakeCase`，讓巢狀型別的欄位名稱直接對應 API 的 snake_case 鍵
    init(data: String) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self = try decoder.decode(LKAnthropicStreamEvent.self, from: Data(data.utf8))
    }
}

// MARK: - Nested Types

extension LKAnthropicStreamEvent {

    /// 事件最外層用到的鍵
    enum CodingKeys: String, CodingKey {

        /// 事件類型
        case type

        /// `message_start` 的訊息
        case message

        /// `content_block_start` 的區塊，對應 JSON 的 `content_block`
        case contentBlock

        /// `content_block_delta` 與 `message_delta` 的增量
        case delta

        /// `message_delta` 的累計用量
        case usage
    }

    /// 用量的累計值；API 沒有回報或回報 null 的欄位是 nil，代表沒有回報
    struct Usage: Decodable {

        /// 輸入 token 數，不含快取建立與讀取的部分
        let inputTokens: Int?

        /// 寫入快取的輸入 token 數
        let cacheCreationInputTokens: Int?

        /// 從快取讀取的輸入 token 數
        let cacheReadInputTokens: Int?

        /// 輸出 token 數，含思考的部分
        let outputTokens: Int?

        /// 輸出 token 的細項
        let outputTokensDetails: OutputTokensDetails?

        /// 輸出 token 的細項，目前只用到思考的部分
        struct OutputTokensDetails: Decodable {

            /// 用在思考的輸出 token 數
            let thinkingTokens: Int?
        }
    }

    /// `message_start` 的 `message`，只取模型與用量
    struct Message: Decodable {

        /// 訊息的模型識別碼
        let model: String

        /// 開頭回報的用量；沒有時為 nil
        let usage: Usage?

        /// 對應的串流事件
        var event: LKAnthropicStreamEvent {
            .messageStart(model: model, usage: usage)
        }
    }

    /// `content_block_start` 的 `content_block`，只關心 `fallback` 類型
    struct ContentBlock: Decodable {

        /// `fallback` 區塊切換後的模型；其他類型的區塊為 nil
        let fallbackTargetModel: String?

        /// 依區塊類型解碼：只有 `fallback` 類型才讀目標模型，其他類型的欄位不看
        ///
        /// - Parameter decoder: 提供 JSON 內容的解碼器
        /// - Throws: `fallback` 區塊沒有 `to.model` 時丟出 `DecodingError`
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "fallback" {
                fallbackTargetModel = try container.decode(Target.self, forKey: .to).model
            } else {
                fallbackTargetModel = nil
            }
        }

        /// 區塊的鍵
        enum CodingKeys: String, CodingKey {

            /// 區塊類型
            case type

            /// `fallback` 區塊切換後的目標
            case to
        }

        /// `fallback` 區塊切換後的目標模型
        struct Target: Decodable {

            /// 切換後的模型識別碼
            let model: String
        }

        /// 對應的串流事件；`fallback` 區塊是 `.fallback`，其他類型略過
        var event: LKAnthropicStreamEvent {
            guard let fallbackTargetModel else {
                return .ignored
            }
            return .fallback(toModel: fallbackTargetModel)
        }
    }

    /// `content_block_delta` 的 `delta`，只關心 `text_delta` 類型
    struct Delta: Decodable {

        /// `text_delta` 的文字；其他類型的增量（`thinking_delta`、`signature_delta` 等）為 nil
        let text: String?

        /// 依增量類型解碼：只有 `text_delta` 才讀文字，其他類型的欄位不看
        ///
        /// - Parameter decoder: 提供 JSON 內容的解碼器
        /// - Throws: `text_delta` 沒有 `text` 時丟出 `DecodingError`
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "text_delta" {
                text = try container.decode(String.self, forKey: .text)
            } else {
                text = nil
            }
        }

        /// 增量的鍵
        enum CodingKeys: String, CodingKey {

            /// 增量類型
            case type

            /// `text_delta` 的文字
            case text
        }

        /// 對應的串流事件；`text_delta` 是 `.textDelta`，其他類型略過
        var event: LKAnthropicStreamEvent {
            guard let text else {
                return .ignored
            }
            return .textDelta(text)
        }
    }

    /// `message_delta` 的 `delta`，取結束原因與拒答的類別
    struct MessageDeltaFields: Decodable {

        /// 結束原因；還沒有結束原因時為 nil
        let stopReason: String?

        /// 結束的細節；沒有時為 nil
        let stopDetails: StopDetails?

        /// 結束的細節，目前只用到拒答的類別
        struct StopDetails: Decodable {

            /// 拒答的類別；API 回報 null 時為 nil
            let category: String?
        }

        /// 組出對應的串流事件
        ///
        /// - Parameter usage: 同一個 `message_delta` 事件頂層的用量
        /// - Returns: 帶著結束原因、拒答類別與用量的串流事件
        func event(usage: Usage?) -> LKAnthropicStreamEvent {
            .messageDelta(
                stopReason: stopReason,
                refusalCategory: stopDetails?.category,
                usage: usage
            )
        }
    }
}

// MARK: - Decodable

extension LKAnthropicStreamEvent: Decodable {

    /// 依 `type` 欄位決定是哪一種事件，再解出該事件用得到的欄位；不認得的類型解成 `.ignored`
    ///
    /// - Parameter decoder: 提供 JSON 內容的解碼器
    /// - Throws: 沒有 `type` 欄位，或認得的類型欄位格式不符時丟出 `DecodingError`
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message_start":
            self = try container.decode(Message.self, forKey: .message).event

        case "content_block_start":
            self = try container.decode(ContentBlock.self, forKey: .contentBlock).event

        case "content_block_delta":
            self = try container.decode(Delta.self, forKey: .delta).event

        case "message_delta":
            let usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
            self = try container.decode(MessageDeltaFields.self, forKey: .delta).event(usage: usage)

        case "message_stop":
            self = .messageStop

        case "error":
            self = try .error(LKAnthropicErrorBody(from: decoder))

        default:
            self = .ignored
        }
    }
}
