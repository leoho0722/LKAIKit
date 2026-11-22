//
//  LKAIHTTPLines.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// HTTP 回應內容逐行交出的序列，一行一個字串，不含 CR 與 LF，空行保留
///
/// - Note: 只支援單一消費者，與 `AsyncThrowingStream` 相同
/// - Note: 迭代的 task 被取消時正常結束，取消後才收到的錯誤不會交出
package struct LKAIHTTPLines: Sendable {

    // MARK: - Properties

    /// 逐行內容的來源，錯誤在迭代時統一轉成 `LKAIError`
    private let source: AsyncThrowingStream<String, any Error>

    // MARK: - Init

    /// 以逐行內容的來源序列建立
    ///
    /// - Parameter source: 依序送出每一行的來源序列
    /// - Note: 來源丟出 `CancellationError` 或 `LKAIError.cancelled` 時正常結束
    /// - Note: 來源丟出其他 `LKAIError` 時原樣交出，丟出不是 `LKAIError` 的錯誤時轉成 `LKAIError.invalidResponse`
    /// - Note: 迭代的 task 已被取消時，不論來源丟出什麼錯誤都正常結束
    package init(_ source: AsyncThrowingStream<String, any Error>) {
        self.source = source
    }
}

// MARK: - Nested Types

extension LKAIHTTPLines {

    /// 逐行取得內容的迭代器，在這裡把來源丟出的錯誤轉成 `LKAIError`
    package struct AsyncIterator: AsyncIteratorProtocol {

        /// 來源序列的迭代器
        private var sourceIterator: AsyncThrowingStream<String, any Error>.Iterator

        /// 以來源序列的迭代器建立
        ///
        /// - Parameter sourceIterator: 來源序列的迭代器
        init(sourceIterator: AsyncThrowingStream<String, any Error>.Iterator) {
            self.sourceIterator = sourceIterator
        }

        /// 取得來源的下一行，並依規則轉換來源丟出的錯誤
        ///
        /// - Parameter actor: 呼叫端目前所在的 actor，原樣傳給來源的迭代器
        /// - Returns: 下一行；來源結束、迭代的 task 被取消，或來源丟出取消類的錯誤時為 nil
        /// - Throws: 來源丟出其他 `LKAIError` 時原樣丟出，丟出不是 `LKAIError` 的錯誤時轉成 `.invalidResponse`
        package mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(LKAIError) -> String? {
            do {
                return try await sourceIterator.next(isolation: actor)
            } catch {
                // 取消後來源仍可能在空檔丟出錯誤，所以把 `Task.isCancelled` 一併交給判斷，這些錯誤才不會漏出去
                let mapped = LKAIError.streamFailure(for: error, isCancelled: Task.isCancelled)
                guard let failure = mapped else {
                    return nil
                }
                throw failure
            }
        }

        /// 不指定 actor 取得下一行，轉呼叫 `next(isolation:)`
        ///
        /// - Returns: 下一行；串流結束或被取消時為 nil
        /// - Throws: 同 `next(isolation:)`
        package mutating func next() async throws(LKAIError) -> String? {
            try await next(isolation: nil)
        }
    }
}

// MARK: - AsyncSequence

extension LKAIHTTPLines: AsyncSequence {

    /// 序列交出的元素是一行文字
    package typealias Element = String

    /// 迭代失敗時丟出的錯誤型別，讓呼叫端的 `catch` 直接拿到 `LKAIError`
    package typealias Failure = LKAIError

    /// 從來源序列建立一個新的迭代器
    ///
    /// - Returns: 用來逐行取得內容的迭代器
    package func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(sourceIterator: source.makeAsyncIterator())
    }
}
