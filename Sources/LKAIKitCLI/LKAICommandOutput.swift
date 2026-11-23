//
//  LKAICommandOutput.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation

/// `lkai` 寫出文字的唯一出口：標準輸出與標準錯誤各一個寫入動作
///
/// - Note: 正式執行時寫到 `FileHandle`，測試時換成記錄文字的 closure，所以不連網、不開行程就能檢查輸出
/// - Note: 文字直接寫進 `FileHandle`，不經過 `print` 的緩衝，stream 的文字才會即時出現在 pipe 的另一端
/// - Note: 標準輸出的寫入會丟出錯誤，交給 `LKAIChatRunner` 處理；標準錯誤的寫入不回報錯誤，
///   因為已經沒有地方可以回報
/// - Note: 只有實例成員，也不依賴 ArgumentParser
struct LKAICommandOutput: Sendable {

    // MARK: - Properties

    /// 寫文字到標準輸出；寫入失敗時丟出錯誤，由呼叫端處理
    let writeStandardOutput: @Sendable (String) throws -> Void

    /// 寫文字到標準錯誤；寫入失敗時忽略，不丟出錯誤
    let writeStandardError: @Sendable (String) -> Void

    // MARK: - Init

    /// 以兩個 `FileHandle` 建立，正式執行時使用
    ///
    /// - Parameters:
    ///   - standardOutput: 標準輸出，例如 `FileHandle.standardOutput`
    ///   - standardError: 標準錯誤，例如 `FileHandle.standardError`
    /// - Note: 文字以 UTF-8 用 `write(contentsOf:)` 寫入：標準輸出的寫入錯誤往上丟，
    ///   標準錯誤的寫入錯誤忽略
    /// - Note: 不用 `write(_:)`：它寫入失敗時丟出 Objective-C 的例外，Swift 接不住，行程會崩潰
    init(standardOutput: FileHandle, standardError: FileHandle) {
        writeStandardOutput = { text in
            try standardOutput.write(contentsOf: Data(text.utf8))
        }
        writeStandardError = { text in
            try? standardError.write(contentsOf: Data(text.utf8))
        }
    }

    /// 以兩個寫入動作建立，給測試記錄輸出用
    ///
    /// - Parameters:
    ///   - writeStandardOutput: 收到要寫到標準輸出的文字時呼叫；可以丟出錯誤，模擬寫入失敗
    ///   - writeStandardError: 收到要寫到標準錯誤的文字時呼叫
    init(
        writeStandardOutput: @escaping @Sendable (String) throws -> Void,
        writeStandardError: @escaping @Sendable (String) -> Void
    ) {
        self.writeStandardOutput = writeStandardOutput
        self.writeStandardError = writeStandardError
    }
}
