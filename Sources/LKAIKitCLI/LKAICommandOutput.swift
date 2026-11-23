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
/// - Note: 只有實例成員，也不依賴 ArgumentParser
struct LKAICommandOutput: Sendable {

    // MARK: - Properties

    /// 寫文字到標準輸出
    let writeStandardOutput: @Sendable (String) -> Void

    /// 寫文字到標準錯誤
    let writeStandardError: @Sendable (String) -> Void

    // MARK: - Init

    /// 以兩個 `FileHandle` 建立，正式執行時使用
    ///
    /// - Parameters:
    ///   - standardOutput: 標準輸出，例如 `FileHandle.standardOutput`
    ///   - standardError: 標準錯誤，例如 `FileHandle.standardError`
    /// - Note: 文字以 UTF-8 寫入，用 `write(contentsOf:)`，寫入失敗會被忽略
    init(standardOutput: FileHandle, standardError: FileHandle) {
        let write: @Sendable (FileHandle, String) -> Void = { handle, text in
            try? handle.write(contentsOf: Data(text.utf8)) // 失敗時已無處回報；write(_:) 會丟 ObjC 例外使行程崩潰，故不用
        }
        writeStandardOutput = { write(standardOutput, $0) }
        writeStandardError = { write(standardError, $0) }
    }

    /// 以兩個寫入動作建立，給測試記錄輸出用
    ///
    /// - Parameters:
    ///   - writeStandardOutput: 收到要寫到標準輸出的文字時呼叫
    ///   - writeStandardError: 收到要寫到標準錯誤的文字時呼叫
    init(
        writeStandardOutput: @escaping @Sendable (String) -> Void,
        writeStandardError: @escaping @Sendable (String) -> Void
    ) {
        self.writeStandardOutput = writeStandardOutput
        self.writeStandardError = writeStandardError
    }
}
