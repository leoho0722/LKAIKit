//
//  LKAICommandOutputTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import Testing

@testable import LKAIKitCLI

/// `LKAICommandOutput` 的單元測試：收 `FileHandle` 的 `init` 把文字以 UTF-8 寫到對應的那一個，
/// 標準輸出的寫入錯誤往上丟，標準錯誤的寫入錯誤忽略
///
/// - Note: 只用 `Pipe` 與暫存資料夾內的檔案，不碰測試行程自己的標準輸出與標準錯誤
/// - Note: 不使用接收端已關閉的 `Pipe`：寫入時作業系統送出 SIGPIPE，會終止整個測試行程
struct LKAICommandOutputTests {

    /// 驗證兩條 `Pipe` 的寫入端各接標準輸出與標準錯誤時，含非 ASCII 的文字各自進到對應的 `Pipe`，
    /// 內容完整，沒有接反
    ///
    /// - Note: 寫入量只有幾個字，遠小於 `Pipe` 的緩衝，所以先寫完、關閉寫入端，再讀取不會卡住
    @Test
    func init_兩條Pipe各寫一段文字_內容各自進對應的Pipe且沒有接反() throws {
        // Given
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let output = LKAICommandOutput(
            standardOutput: standardOutputPipe.fileHandleForWriting,
            standardError: standardErrorPipe.fileHandleForWriting
        )

        // When
        try output.writeStandardOutput("回答 ✓")
        output.writeStandardError("錯誤 ✗")
        try standardOutputPipe.fileHandleForWriting.close()
        try standardErrorPipe.fileHandleForWriting.close()

        // Then
        #expect(try readAll(from: standardOutputPipe) == "回答 ✓")
        #expect(try readAll(from: standardErrorPipe) == "錯誤 ✗")
    }

    /// 驗證標準輸出接到唯讀開啟的檔案時，`writeStandardOutput` 丟出錯誤，不是吞掉
    ///
    /// - Note: 唯讀開啟的檔案描述符不能寫入，作業系統回報錯誤，這和磁碟已滿一樣是寫入失敗
    /// - Note: 標準錯誤接 `FileHandle.nullDevice`，這個測試不檢查它
    @Test
    func writeStandardOutput_檔案是唯讀_丟出錯誤() throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let fileURL = directory.appending(path: "target.txt")
        let readOnlyHandle = try makeReadOnlyHandle(at: fileURL, content: "原有內容")
        defer { try? readOnlyHandle.close() } // 關閉失敗可忽略，因為測試已經結束
        let output = LKAICommandOutput(
            standardOutput: readOnlyHandle,
            standardError: FileHandle.nullDevice
        )
        var thrownError: (any Error)?

        // When
        do {
            try output.writeStandardOutput("回答")
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError != nil)
    }

    /// 驗證標準錯誤接到唯讀開啟的檔案時，`writeStandardError` 不丟出錯誤、也不中止：
    /// 檔案內容沒有變，之後標準輸出的寫入照常完成
    ///
    /// - Note: `writeStandardError` 的型別沒有 `throws`，所以不丟出錯誤由編譯器保證；
    ///   這裡要確認的是寫入失敗被忽略之後，行程沒有崩潰，後面的寫入也沒有受影響
    @Test
    func writeStandardError_檔案是唯讀_不丟出錯誤也不中止() throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let fileURL = directory.appending(path: "target.txt")
        let originalContent = "原有內容"
        let readOnlyHandle = try makeReadOnlyHandle(at: fileURL, content: originalContent)
        defer { try? readOnlyHandle.close() } // 關閉失敗可忽略，因為測試已經結束
        let standardOutputPipe = Pipe()
        let output = LKAICommandOutput(
            standardOutput: standardOutputPipe.fileHandleForWriting,
            standardError: readOnlyHandle
        )

        // When
        output.writeStandardError("錯誤 ✗")
        try output.writeStandardOutput("回答 ✓")
        try standardOutputPipe.fileHandleForWriting.close()

        // Then
        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(fileContent == originalContent)
        #expect(try readAll(from: standardOutputPipe) == "回答 ✓")
    }
}

// MARK: - Private Method

private extension LKAICommandOutputTests {

    /// 讀出 `Pipe` 裡的全部內容；呼叫前要先關閉它的寫入端，否則讀取會一直等下去
    ///
    /// - Parameter pipe: 寫入端已關閉的 `Pipe`
    /// - Returns: 以 UTF-8 解碼的全部內容；沒有任何內容時為空字串
    /// - Throws: 讀取失敗時丟出
    func readAll(from pipe: Pipe) throws -> String {
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// 建立一個檔案，再以唯讀開啟，寫入這個 `FileHandle` 一定會失敗
    ///
    /// - Parameters:
    ///   - fileURL: 檔案的位置，要在暫存資料夾內
    ///   - content: 檔案原本的內容
    /// - Returns: 唯讀開啟的 `FileHandle`；呼叫端用完要關閉
    /// - Throws: 建立檔案或開啟失敗時丟出
    func makeReadOnlyHandle(at fileURL: URL, content: String) throws -> FileHandle {
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forReadingFrom: fileURL)
    }
}
