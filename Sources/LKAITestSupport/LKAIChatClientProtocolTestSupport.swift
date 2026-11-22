//
//  LKAIChatClientProtocolTestSupport.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// `LKAIChatClientProtocol` 的測試共用 helper：以串流或非串流呼叫 client，供各供應商共用
package enum LKAIChatClientProtocolTestSupport {

}

// MARK: - Nested Types

extension LKAIChatClientProtocolTestSupport {

    /// 呼叫 client 的方式，串流與非串流走同一套請求檢查與送出流程
    package enum CallMode: CaseIterable, Sendable {

        /// 呼叫 `stream(_:)`，迭代串流到結束
        case stream

        /// 呼叫 `invoke(_:)`，等整段回答完成
        case invoke
    }

    /// 迭代完一條串流後的結果：收到的全部事件，以及串流丟出的錯誤
    package struct StreamOutcome: Sendable {

        /// 依收到的順序排列的全部事件
        package let events: [LKAIChatStreamEvent]

        /// 串流丟出的錯誤；正常結束時為 nil
        package let error: LKAIError?
    }
}

// MARK: - Internal Method

extension LKAIChatClientProtocolTestSupport {

    /// 迭代 client 的串流到結束，收集事件並記下丟出的錯誤
    ///
    /// - Parameters:
    ///   - client: 要呼叫的 client
    ///   - request: 要送出的對話請求，由呼叫端指定
    ///   - onEvent: 每收到一個事件就呼叫一次；不需要時省略
    /// - Returns: 收到的全部事件，以及串流丟出的錯誤；正常結束時錯誤為 nil
    package static func collectOutcome(
        from client: any LKAIChatClientProtocol,
        request: LKAIChatRequest,
        onEvent: (LKAIChatStreamEvent) -> Void = { _ in }
    ) async -> StreamOutcome {
        var events: [LKAIChatStreamEvent] = []
        var actualError: LKAIError?
        do {
            for try await event in client.stream(request) {
                events.append(event)
                onEvent(event)
            }
        } catch {
            actualError = error
        }
        return StreamOutcome(events: events, error: actualError)
    }

    /// 以指定的方式呼叫 client，迭代或等待到結束，並記下丟出的錯誤
    ///
    /// - Parameters:
    ///   - client: 要呼叫的 client
    ///   - request: 要送出的對話請求，由呼叫端指定
    ///   - mode: 呼叫方式，串流或非串流
    /// - Returns: 呼叫丟出的錯誤；順利結束時為 nil
    package static func callError(
        on client: any LKAIChatClientProtocol,
        request: LKAIChatRequest,
        mode: CallMode
    ) async -> LKAIError? {
        var actualError: LKAIError?
        do {
            switch mode {
            case .stream:
                for try await _ in client.stream(request) {
                    // 只需要迭代到結束，事件的內容不在這裡檢查
                }

            case .invoke:
                _ = try await client.invoke(request)
            }
        } catch {
            actualError = error
        }
        return actualError
    }

    /// 取得串流的第一個事件就離開迴圈，函式返回時串流跟著釋放
    ///
    /// - Parameters:
    ///   - client: 要呼叫的 client
    ///   - request: 要送出的對話請求，由呼叫端指定
    /// - Returns: 串流的第一個事件；串流沒有任何事件就結束時為 nil
    /// - Throws: 串流在第一個事件之前失敗時丟出
    package static func receiveFirstEvent(
        of client: any LKAIChatClientProtocol,
        request: LKAIChatRequest
    ) async throws(LKAIError) -> LKAIChatStreamEvent? {
        let stream = client.stream(request)
        for try await event in stream {
            return event
        }
        return nil
    }
}
