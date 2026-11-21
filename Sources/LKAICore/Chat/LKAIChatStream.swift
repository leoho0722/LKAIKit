//
//  LKAIChatStream.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// 串流對話的事件序列：依序交出一段一段的文字，最後交出一次結束事件後結束
///
/// - Note: 只支援單一消費者，第二次迭代的行為與 `AsyncThrowingStream` 相同
/// - Note: App 可以用 `init(_:)` 自己建立串流，為 `LKAIChatClientProtocol` 寫測試替身
/// - Note: 迭代的 task 被取消時正常結束，取消後才收到的錯誤不會交給 App
/// - Note: 釋放串流才會取消底層請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費
public struct LKAIChatStream: Sendable {

    // MARK: - Properties

    /// 事件的來源，錯誤在迭代時統一轉成 `LKAIError`
    private let source: AsyncThrowingStream<LKAIChatStreamEvent, any Error>

    // MARK: - Init

    /// 以自己的事件序列建立串流，讓 App 能為 `LKAIChatClientProtocol` 寫測試替身
    ///
    /// - Parameter source: 依序送出事件的來源序列
    /// - Note: 來源的事件依序原樣交出；來源丟出 `CancellationError` 或 `LKAIError.cancelled` 時正常結束
    /// - Note: 來源丟出其他 `LKAIError` 時原樣交出，丟出不是 `LKAIError` 的錯誤時轉成 `LKAIError.invalidResponse`
    /// - Note: 迭代的 task 已被取消時，不論來源丟出什麼錯誤都正常結束
    public init(_ source: AsyncThrowingStream<LKAIChatStreamEvent, any Error>) {
        self.source = source
    }
}

// MARK: - Nested Types

extension LKAIChatStream {

    /// 逐一取得串流事件的迭代器，在這裡把來源丟出的錯誤轉成 `LKAIError`
    public struct AsyncIterator: AsyncIteratorProtocol {

        /// 來源序列的迭代器
        private var sourceIterator: AsyncThrowingStream<LKAIChatStreamEvent, any Error>.Iterator

        /// 以來源序列的迭代器建立
        ///
        /// - Parameter sourceIterator: 來源序列的迭代器
        init(sourceIterator: AsyncThrowingStream<LKAIChatStreamEvent, any Error>.Iterator) {
            self.sourceIterator = sourceIterator
        }

        /// 取得來源的下一個事件，並依串流的規則轉換來源丟出的錯誤
        ///
        /// - Parameter actor: 呼叫端目前所在的 actor，原樣傳給來源的迭代器
        /// - Returns: 下一個事件；來源結束、迭代的 task 被取消，或來源丟出取消類的錯誤時為 nil
        /// - Throws: 來源丟出其他 `LKAIError` 時原樣丟出，丟出不是 `LKAIError` 的錯誤時轉成 `.invalidResponse`
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(LKAIError) -> LKAIChatStreamEvent? {
            do {
                return try await sourceIterator.next(isolation: actor)
            } catch {
                // 取消後來源仍可能在空檔丟出錯誤，所以最先判斷取消，這些錯誤才不會漏給 App
                guard !Task.isCancelled, let failure = LKAIError.streamFailure(for: error) else {
                    return nil
                }
                throw failure
            }
        }

        /// 不指定 actor 取得下一個事件，轉呼叫 `next(isolation:)`
        ///
        /// - Returns: 下一個事件；串流結束或被取消時為 nil
        /// - Throws: 同 `next(isolation:)`
        public mutating func next() async throws(LKAIError) -> LKAIChatStreamEvent? {
            try await next(isolation: nil)
        }
    }
}

// MARK: - AsyncSequence

extension LKAIChatStream: AsyncSequence {

    /// 串流交出的元素是對話事件
    public typealias Element = LKAIChatStreamEvent

    /// 串流失敗時丟出的錯誤型別，讓 App 的 `catch` 直接拿到 `LKAIError`
    public typealias Failure = LKAIError

    /// 從來源序列建立一個新的迭代器
    ///
    /// - Returns: 用來逐一取得事件的迭代器
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(sourceIterator: source.makeAsyncIterator())
    }
}
