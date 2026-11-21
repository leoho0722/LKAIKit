//
//  LKAIChatClientProtocol.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 與供應商無關的對話介面，App 只透過它呼叫對話，換供應商時不必改呼叫端
///
/// - Note: App 依設定建立具體的 client（例如 Anthropic 的 client），存成 `any LKAIChatClientProtocol` 使用
/// - Note: 可以用 `LKAIChatStream(_:)` 寫只實作 `stream(_:)` 的測試替身，`invoke(_:)` 走預設實作
public protocol LKAIChatClientProtocol: Sendable {

    /// 依序交出文字片段，最後交出一次結束事件後結束
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序交出事件的串流；請求在呼叫這個方法時就送出，不必等到迭代
    /// - Note: 釋放串流（不論是否迭代過）會取消底層請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
    /// - Note: 請求不合法時，迭代串流會以 `invalidRequest` 失敗，而且不送出網路請求；由各供應商實作這項檢查
    func stream(_ request: LKAIChatRequest) -> LKAIChatStream

    /// 等整段回答生成完成後，回傳完整的文字與結束時的資訊
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序串接好的完整文字，加上結束時的資訊
    /// - Throws: 被取消時丟出 `cancelled`；沒有結束事件就結束時丟出 `invalidResponse`；其餘錯誤原樣丟出
    /// - Note: 拒答時丟出 `refused`，不回傳已生成的部分文字
    /// - Note: 收到結束事件時若 task 已被取消，仍丟出 `cancelled`，不回傳已收到的文字
    func invoke(_ request: LKAIChatRequest) async throws(LKAIError) -> LKAIChatResponse
}

// MARK: - Internal Method

public extension LKAIChatClientProtocol {

    /// 迭代 `stream(_:)` 串接所有文字，拿到結束事件時回傳結果
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 依序串接好的完整文字，加上結束事件帶來的資訊
    /// - Throws: 被取消時一律丟出 `cancelled`；沒有結束事件就結束時丟出 `invalidResponse`；其餘錯誤原樣丟出
    /// - Note: 非串流由串流彙整，彙整邏輯只寫在這一處，各供應商只需實作串流
    /// - Note: Claude API 的參考資料建議輸出可能較長時一律用串流，以免 HTTP 請求逾時
    /// - Note: 收到結束事件時若 task 已被取消，仍丟出 `cancelled`，因為緩衝區裡的事件在取消後仍會交出
    func invoke(_ request: LKAIChatRequest) async throws(LKAIError) -> LKAIChatResponse {
        var text = ""
        do throws(LKAIError) {
            for try await event in stream(request) {
                switch event {
                case .textDelta(let delta):
                    text += delta

                case .finished(let completion):
                    // 結束事件可能已在緩衝區，取消後仍會交出，所以拿到結束事件時也要先檢查取消
                    guard !Task.isCancelled else {
                        throw LKAIError.cancelled
                    }
                    return LKAIChatResponse(text: text, completion: completion)
                }
            }
        } catch {
            // 取消後來源可能才丟出錯誤，這些錯誤不交給 App
            guard !Task.isCancelled else {
                throw .cancelled
            }
            throw error
        }
        guard !Task.isCancelled else {
            throw .cancelled
        }
        throw .invalidResponse(reason: "Stream ended before a finish event")
    }
}
