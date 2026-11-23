//
//  MockChatClient.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import LKAIKit
import Synchronization

/// 不連網的對話 client 替身：`invoke(_:)` 回傳指定的結果，`stream(_:)` 交出指定的事件，
/// 並記錄兩個方法各收到哪些請求
///
/// - Note: 記錄放在 `Mutex` 裡，可以在並行下安全使用，所以不需要 `@unchecked Sendable`
/// - Note: 沒有指定的那個方法被呼叫時會失敗，錯誤的原因寫明沒有設定，免得被誤認成正常的結果
final class MockChatClient: Sendable {

    // MARK: - Properties

    /// `invoke(_:)` 要回傳的結果
    private let invokeResult: Result<LKAIChatResponse, LKAIError>

    /// 每次呼叫 `stream(_:)` 時建立事件來源的 closure
    private let streamSource: StreamSource

    /// 兩個方法各收到的請求，依呼叫順序排列
    private let receivedRequests = Mutex(ReceivedRequests())

    // MARK: - Init

    /// 以指定的 `invoke(_:)` 結果與事件來源建立
    ///
    /// - Parameters:
    ///   - invokeResult: `invoke(_:)` 要回傳的結果；省略時，呼叫 `invoke(_:)` 會失敗
    ///   - streamSource: 每次呼叫 `stream(_:)` 時建立事件來源的 closure；省略時，迭代串流會失敗
    init(
        invokeResult: Result<LKAIChatResponse, LKAIError>? = nil,
        streamSource: StreamSource? = nil
    ) {
        self.invokeResult = invokeResult ?? .failure(Self.unsetError(of: "invokeResult"))
        self.streamSource = streamSource ?? Self.makeUnsetStreamSource()
    }

    /// 以固定的事件序列建立，串流依序交出這些事件，再正常結束或以指定的錯誤結束
    ///
    /// - Parameters:
    ///   - invokeResult: `invoke(_:)` 要回傳的結果；省略時，呼叫 `invoke(_:)` 會失敗
    ///   - streamEvents: 串流依序交出的事件
    ///   - streamError: 交完事件後讓串流失敗的錯誤；nil 表示正常結束
    convenience init(
        invokeResult: Result<LKAIChatResponse, LKAIError>? = nil,
        streamEvents: [LKAIChatStreamEvent],
        streamError: LKAIError? = nil
    ) {
        self.init(invokeResult: invokeResult, streamSource: {
            AsyncThrowingStream { continuation in
                for event in streamEvents {
                    continuation.yield(event)
                }
                continuation.finish(throwing: streamError)
            }
        })
    }
}

// MARK: - Nested Types

extension MockChatClient {

    /// 每次呼叫 `stream(_:)` 時建立事件來源的 closure
    typealias StreamSource = @Sendable () -> AsyncThrowingStream<LKAIChatStreamEvent, any Error>

    /// 兩個方法各收到的請求
    private struct ReceivedRequests: Sendable {

        /// `invoke(_:)` 收到的請求
        var invoke: [LKAIChatRequest] = []

        /// `stream(_:)` 收到的請求
        var stream: [LKAIChatRequest] = []
    }
}

// MARK: - Computed Properties

extension MockChatClient {

    /// `invoke(_:)` 收到的請求，依呼叫順序排列
    var invokeReceivedRequests: [LKAIChatRequest] {
        receivedRequests.withLock { $0.invoke }
    }

    /// `stream(_:)` 收到的請求，依呼叫順序排列
    var streamReceivedRequests: [LKAIChatRequest] {
        receivedRequests.withLock { $0.stream }
    }
}

// MARK: - LKAIChatClientProtocol

extension MockChatClient: LKAIChatClientProtocol {

    /// 記錄請求，回傳以 `streamSource` 建立的串流
    ///
    /// - Parameter request: 呼叫端傳入的請求，會被記錄
    /// - Returns: 依事件來源交出事件的串流
    func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
        receivedRequests.withLock { $0.stream.append(request) }
        return LKAIChatStream(streamSource())
    }

    /// 記錄請求，回傳或丟出預先指定的結果
    ///
    /// - Parameter request: 呼叫端傳入的請求，會被記錄
    /// - Returns: 預先指定的成功結果
    /// - Throws: 預先指定的結果是失敗時，丟出其中的錯誤
    func invoke(_ request: LKAIChatRequest) async throws(LKAIError) -> LKAIChatResponse {
        receivedRequests.withLock { $0.invoke.append(request) }
        return try invokeResult.get()
    }
}

// MARK: - Private Method

private extension MockChatClient {

    /// 沒有指定的那個方法被呼叫時使用的錯誤
    ///
    /// - Parameter name: 沒有指定的設定名稱
    /// - Returns: 說明沒有設定的 `invalidResponse`
    static func unsetError(of name: String) -> LKAIError {
        .invalidResponse(reason: "MockChatClient: \(name) is not set")
    }

    /// 沒有指定事件來源時使用的來源：迭代時直接以「沒有設定」的錯誤失敗
    ///
    /// - Returns: 建立會失敗的串流的 closure
    static func makeUnsetStreamSource() -> StreamSource {
        {
            AsyncThrowingStream { $0.finish(throwing: unsetError(of: "streamSource")) }
        }
    }
}
