//
//  LKAIChatRunner.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

import LKAIKit

/// 拿 client 執行一次對話，把回答、警告與錯誤寫到 `LKAICommandOutput`，回傳這次執行的結果
///
/// - Note: 只負責執行與輸出；結果對應成哪個退出碼，由 `LKAICommand` 決定
/// - Note: 不依賴 ArgumentParser
/// - Note: `switch` 對 `LKAIFinishReason`、`LKAIChatStreamEvent` 都列出每個 case，不留萬用分支：
///   同一個 package，新增 case 時這裡要編譯失敗，才一定會被處理
struct LKAIChatRunner {

    // MARK: - Properties

    /// 實際送出請求的 client
    let client: any LKAIChatClientProtocol

    /// 回答與警告寫到的地方
    let output: LKAICommandOutput

    /// 警告與錯誤使用的輸出語言
    let language: LKAIOutputLanguage

    /// 這次使用的 API 金鑰，只用來遮蔽輸出中的金鑰，不會被寫出去
    let apiKey: LKAIAPIKey
}

// MARK: - Nested Types

extension LKAIChatRunner {

    /// 回答的輸出方式
    enum OutputMode {

        /// 等整段回答完成，一次寫到標準輸出
        case invoke

        /// 每收到一段文字就寫到標準輸出
        case stream
    }

    /// 這次執行的結果，由 `LKAICommand` 對應成退出碼
    enum Outcome: Equatable {

        /// 回答完整，結束原因是 `completed`
        case completed

        /// 回答沒有正常完成，結束原因是 `maxOutputTokens` 或 `contextWindowExceeded`；回答仍已印出
        case incomplete

        /// 對話失敗，沒有得到完整的結果
        case failed
    }
}

// MARK: - Internal Method

extension LKAIChatRunner {

    /// 送出請求，依輸出方式寫出回答，需要時再寫出警告或錯誤
    ///
    /// - Parameters:
    ///   - request: 要送出的對話請求
    ///   - mode: 回答的輸出方式
    /// - Returns: 這次執行的結果；結束原因是 `completed` 為 `.completed`，其他結束原因為 `.incomplete`，
    ///   對話失敗為 `.failed`
    /// - Note: 寫過文字、而且最後一個 UTF-8 位元組不是 LF（`\n`）時，補一個 LF；以位元組判斷，
    ///   因為 CR（`\r`）加 LF 在 Swift 是一個 `Character`，用 `last == "\n"` 判斷會誤判
    /// - Note: 結束原因不是 `completed` 時，回答照樣寫出，再在標準錯誤寫一行 `Warning: ` 加該語言的訊息
    /// - Note: 對話失敗時，在標準錯誤寫 `Error: ` 加該語言的錯誤說明，有技術細節時再寫一行 `Details: `，
    ///   細節中的 API 金鑰換成 `[REDACTED]`；不印用法，因為問題不在命令列的寫法
    /// - Note: 串流失敗時，標準輸出保留失敗前收到的文字，先依結尾規則補 LF，再寫標準錯誤
    /// - Note: 串流沒有收到結束事件、也沒有錯誤就結束時，當成 `invalidResponse`，走同一條失敗路徑
    func run(_ request: LKAIChatRequest, mode: OutputMode) async -> Outcome {
        switch mode {
        case .invoke:
            return await runInvoke(request)

        case .stream:
            return await runStream(request)
        }
    }
}

// MARK: - Private Method

private extension LKAIChatRunner {

    /// 等整段回答完成，一次寫到標準輸出，再依結束原因寫出警告
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 這次執行的結果；呼叫失敗為 `.failed`，標準輸出沒有寫任何東西
    func runInvoke(_ request: LKAIChatRequest) async -> Outcome {
        let response: LKAIChatResponse
        do throws(LKAIError) {
            response = try await client.invoke(request)
        } catch {
            return reportFailure(error)
        }
        if !response.text.isEmpty {
            output.writeStandardOutput(response.text)
        }
        writeLineFeed(afterLastByte: response.text.utf8.last)
        return reportOutcome(for: response.completion.finishReason)
    }

    /// 在標準錯誤寫出失敗的原因：一行 `Error: ` 加錯誤說明，有技術細節時再一行 `Details: `
    ///
    /// - Parameter error: 對話失敗的錯誤
    /// - Returns: 一律是 `.failed`
    /// - Note: `Error: `、`Details: ` 前綴固定是英文，細節不翻譯，兩行都以 LF 結尾
    func reportFailure(_ error: LKAIError) -> Outcome {
        var text = "Error: \(error.errorDescription(localization: language.localization))\n"
        if let details = error.details {
            text += "Details: \(redactAPIKey(in: details))\n"
        }
        output.writeStandardError(text)
        return .failed
    }

    /// 把文字中出現的 API 金鑰換成 `[REDACTED]`
    ///
    /// - Parameter text: 要印出的文字，例如供應商回報的錯誤細節
    /// - Returns: 每一處金鑰都換掉的文字；金鑰是空字串時原樣交出
    /// - Note: 供應商可能在錯誤訊息中回顯金鑰，細節會印到 CI 的 log，所以印出前要遮蔽
    /// - Note: 空字串不能當成要換掉的文字，否則每個位置都會被插入 `[REDACTED]`
    func redactAPIKey(in text: String) -> String {
        let key = apiKey.unredactedValue
        guard !key.isEmpty else {
            return text
        }
        return text.replacing(key, with: "[REDACTED]")
    }

    /// 在回答結尾補一個 LF（`\n`）：寫過文字、而且最後一個位元組不是 LF 時才補
    ///
    /// - Parameter lastByte: 寫到標準輸出的最後一個 UTF-8 位元組；沒有寫過文字時為 nil
    /// - Note: 以位元組判斷，因為 CR（`\r`）加 LF 在 Swift 是一個 `Character`，用 `last == "\n"` 會誤判
    func writeLineFeed(afterLastByte lastByte: UInt8?) {
        let lineFeed = UInt8(ascii: "\n")
        guard let lastByte, lastByte != lineFeed else {
            return
        }
        output.writeStandardOutput("\n")
    }

    /// 依結束原因決定結果，回答沒有正常完成時，在標準錯誤寫一行警告
    ///
    /// - Parameter finishReason: 結束事件帶的結束原因
    /// - Returns: `completed` 為 `.completed`，其他結束原因為 `.incomplete`
    /// - Note: 警告是 `Warning: ` 加該輸出語言的訊息，再加一個 LF；前綴固定是英文，不翻譯
    func reportOutcome(for finishReason: LKAIFinishReason) -> Outcome {
        let warningText: LKAICLIText
        switch finishReason {
        case .completed:
            return .completed

        case .maxOutputTokens:
            warningText = .warningMaxOutputTokens

        case .contextWindowExceeded:
            warningText = .warningContextWindowExceeded
        }
        output.writeStandardError("Warning: \(warningText.string(in: language))\n")
        return .incomplete
    }

    /// 每收到一段文字就寫到標準輸出，寫完才讀下一個事件，串流結束後依結束原因寫出警告
    ///
    /// - Parameter request: 要送出的對話請求
    /// - Returns: 這次執行的結果；串流失敗，或沒有收到結束事件就結束，為 `.failed`
    /// - Note: 失敗時，已經收到的文字保留在標準輸出，先補 LF 再寫標準錯誤
    func runStream(_ request: LKAIChatRequest) async -> Outcome {
        var lastByte: UInt8?
        var completion: LKAIChatCompletion?
        do throws(LKAIError) {
            for try await event in client.stream(request) {
                switch event {
                case .textDelta(let delta):
                    guard let deltaLastByte = delta.utf8.last else {
                        continue
                    }
                    output.writeStandardOutput(delta)
                    lastByte = deltaLastByte

                case .finished(let finishedCompletion):
                    completion = finishedCompletion
                }
            }
        } catch {
            writeLineFeed(afterLastByte: lastByte)
            return reportFailure(error)
        }
        guard let completion else {
            // 比照 `LKAIChatClientProtocol.invoke(_:)` 的預設實作，當成 `invalidResponse`
            writeLineFeed(afterLastByte: lastByte)
            return reportFailure(.invalidResponse(reason: "Stream ended before a finish event"))
        }
        writeLineFeed(afterLastByte: lastByte)
        return reportOutcome(for: completion.finishReason)
    }
}
