//
//  LKAICommandTestSupport.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import Testing

/// `lkai` 的測試共用 helper：以行程執行建置出的 `lkai`，以及說明文字固定的寬度
///
/// - Note: 給 in-process 的 `LKAICommandTests`、以行程執行的 `LKAICommandProcessTests`
///   與之後的實際 API 測試共用
/// - Note: 和對話替身（`MockChatClient`、`ChatRunRecorder`）是不同的檔案
enum LKAICommandTestSupport {

    // MARK: - Properties

    /// 說明與錯誤訊息固定使用的寬度，寬到每則說明都不會折行
    ///
    /// - Note: 說明依終端機寬度折行，比對整段的簡介或選項說明時，結果會隨執行的終端機與 CI 改變，
    ///   所以固定寬度：行程以環境變數 `COLUMNS` 設定，in-process 的測試把它傳給
    ///   `helpMessage(columns:)`、`fullMessage(for:columns:)`
    /// - Note: 目前最長的一行是 `--apiKey` 的英文說明，約 200 個字元，加上選項欄的縮排仍小於這個寬度；
    ///   新增更長的說明時要一併調大
    static let helpColumns = 300
}

// MARK: - Nested Types

extension LKAICommandTestSupport {

    /// 只用來讓 `Bundle(for:)` 找出測試 bundle 的空型別，因為該 API 只接受 class
    private final class BundleLocator {

    }

    /// 一次 `lkai` 行程結束後留下的標準輸出、標準錯誤與退出碼
    struct CommandOutput {

        /// 行程寫到標準輸出的全部文字
        let standardOutput: String

        /// 行程寫到標準錯誤的全部文字
        let standardError: String

        /// 行程的退出碼
        let terminationStatus: Int32
    }
}

// MARK: - Computed Properties

extension LKAICommandTestSupport {

    /// 執行 `lkai` 行程時預設使用的環境變數：目前行程的環境變數，移除名稱以 `LKAI_` 開頭、
    /// 以 `_API_KEY` 結尾的變數，並把 `COLUMNS` 設為 `helpColumns`
    ///
    /// - Note: 移除金鑰的理由：owner 跑實際 API 測試時會設定這些變數；行程測試若沿用它們，
    ///   原本應該在檢查階段失敗的情境可能會送出真的請求
    /// - Note: 每次取用都重新讀取目前行程的環境變數；需要金鑰的測試在這個結果上加回需要的那一個
    static var defaultEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { name, _ in
            !(name.hasPrefix("LKAI_") && name.hasSuffix("_API_KEY"))
        }
        environment["COLUMNS"] = String(helpColumns)
        return environment
    }
}

// MARK: - Internal Method

extension LKAICommandTestSupport {

    /// 以 `Process` 執行建置出的 `lkai`，標準輸出與標準錯誤各接一條 `Pipe` 分開收集
    ///
    /// - Parameters:
    ///   - arguments: 傳給 `lkai` 的命令列引數
    ///   - environment: 行程的環境變數，整份交給行程；預設是 `defaultEnvironment`
    ///   - currentDirectory: 行程的工作目錄；省略時沿用測試行程的工作目錄
    /// - Returns: 行程結束後讀到的標準輸出、標準錯誤與退出碼
    /// - Throws: 行程無法啟動或輸出讀取失敗時丟出
    /// - Note: 執行檔取自測試 bundle 所在的資料夾；找不到時讓測試失敗，不略過
    static func runLKAI(
        arguments: [String],
        environment: [String: String] = LKAICommandTestSupport.defaultEnvironment,
        currentDirectory: URL? = nil
    ) throws -> CommandOutput {
        let testBundleURL = Bundle(for: BundleLocator.self).bundleURL
        let executableURL = testBundleURL.deletingLastPathComponent().appending(path: "lkai")
        try #require(
            FileManager.default.isExecutableFile(atPath: executableURL.path),
            "找不到 lkai 執行檔：\(executableURL.path)"
        )

        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        try process.run()
        process.waitUntilExit()

        // 輸出只有幾行，行程結束後再讀不會塞滿 Pipe；沒有內容時以空資料處理
        let standardOutputData = try standardOutputPipe.fileHandleForReading.readToEnd() ?? Data()
        let standardErrorData = try standardErrorPipe.fileHandleForReading.readToEnd() ?? Data()
        return CommandOutput(
            standardOutput: String(decoding: standardOutputData, as: UTF8.self),
            standardError: String(decoding: standardErrorData, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }
}
