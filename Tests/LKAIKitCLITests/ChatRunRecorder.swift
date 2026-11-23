//
//  ChatRunRecorder.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import LKAIKit
import Synchronization

@testable import LKAIKitCLI

/// 記錄一次對話執行寫出的文字，以及「讀取下一個事件」與「寫入文字」的先後順序
///
/// - Note: 一個記錄器只對應一次執行；事件讀取的序號從 1 開始，依讀取的次數累計
/// - Note: 記錄放在 `Mutex` 裡，可以在並行下安全使用，所以不需要 `@unchecked Sendable`
final class ChatRunRecorder: Sendable {

    // MARK: - Properties

    /// 目前為止的全部記錄
    private let state = Mutex(State())
}

// MARK: - Nested Types

extension ChatRunRecorder {

    /// 時間軸上的一筆記錄，依發生的先後排列
    enum TimelineEntry: Equatable, Sendable {

        /// 讀取了第幾個事件；事件讀完之後再讀一次，也會記一筆，那一次讀到的是串流結束
        ///
        /// - Parameter index: 從 1 開始的序號
        case readEvent(Int)

        /// 寫了文字到標準輸出
        ///
        /// - Parameter text: 寫入的文字
        case writeStandardOutput(String)

        /// 寫了文字到標準錯誤
        ///
        /// - Parameter text: 寫入的文字
        case writeStandardError(String)
    }

    /// 全部記錄
    private struct State: Sendable {

        /// 寫到標準輸出的文字，依寫入的順序排列
        var standardOutput: [String] = []

        /// 寫到標準錯誤的文字，依寫入的順序排列
        var standardError: [String] = []

        /// 到目前為止讀取事件的次數
        var readCount = 0

        /// 讀取與寫入的先後順序
        var timeline: [TimelineEntry] = []
    }
}

// MARK: - Computed Properties

extension ChatRunRecorder {

    /// 寫到標準輸出的全部文字
    var standardOutput: String {
        state.withLock { $0.standardOutput.joined() }
    }

    /// 寫到標準錯誤的全部文字
    var standardError: String {
        state.withLock { $0.standardError.joined() }
    }

    /// 讀取事件與寫入文字的先後順序
    var timeline: [TimelineEntry] {
        state.withLock { $0.timeline }
    }

    /// 把寫入的文字記錄下來的輸出，交給受測的執行器
    var output: LKAICommandOutput {
        LKAICommandOutput(
            writeStandardOutput: { [self] text in
                state.withLock {
                    $0.standardOutput.append(text)
                    $0.timeline.append(.writeStandardOutput(text))
                }
            },
            writeStandardError: { [self] text in
                state.withLock {
                    $0.standardError.append(text)
                    $0.timeline.append(.writeStandardError(text))
                }
            }
        )
    }
}

// MARK: - Internal Method

extension ChatRunRecorder {

    /// 建立依需求才讀取事件的事件來源：每次串流的迭代器要下一個事件，才從 `events` 取一個
    ///
    /// - Parameter events: 串流依序交出的事件，交完就結束
    /// - Returns: 給 `MockChatClient` 的事件來源；每讀一次，就在時間軸記一筆 `readEvent`
    func makeStreamSource(events: [LKAIChatStreamEvent]) -> MockChatClient.StreamSource {
        { [self] in
            AsyncThrowingStream(unfolding: { self.readNextEvent(from: events) })
        }
    }
}

// MARK: - Private Method

private extension ChatRunRecorder {

    /// 記一筆讀取，並交出下一個事件
    ///
    /// - Parameter events: 串流依序交出的事件
    /// - Returns: 下一個事件；事件都交完時為 nil，代表串流結束
    func readNextEvent(from events: [LKAIChatStreamEvent]) -> LKAIChatStreamEvent? {
        state.withLock { recorded in
            recorded.readCount += 1
            recorded.timeline.append(.readEvent(recorded.readCount))
            let eventIndex = recorded.readCount - 1
            return events.indices.contains(eventIndex) ? events[eventIndex] : nil
        }
    }
}
