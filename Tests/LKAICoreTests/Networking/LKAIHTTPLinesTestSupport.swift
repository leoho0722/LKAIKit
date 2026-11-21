//
//  LKAIHTTPLinesTestSupport.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/22.
//

@testable import LKAICore

/// `LKAIHTTPLines` 的測試共用的支援：建立來源的型別、迭代結果，以及逐行收集內容的方法
enum LKAIHTTPLinesTestSupport {

}

// MARK: - Nested Types

extension LKAIHTTPLinesTestSupport {

    /// 建構 `LKAIHTTPLines` 時接收的來源序列型別，寫短一點方便閱讀
    typealias LineSource = AsyncThrowingStream<String, any Error>

    /// 迭代完一份逐行內容後的結果：收到的全部行，以及丟出的錯誤
    struct LinesOutcome {

        /// 依收到的順序排列的全部行，不含 CR 與 LF
        let lines: [String]

        /// 逐行內容丟出的錯誤；正常結束時為 nil
        let error: LKAIError?
    }
}

// MARK: - Internal Method

extension LKAIHTTPLinesTestSupport {

    /// 逐行收下逐行內容交出的每一行，並記下它是正常結束還是丟出了錯誤
    ///
    /// - Parameters:
    ///   - lines: 要迭代的逐行內容
    ///   - onLine: 每收到一行就呼叫一次；不需要時省略
    /// - Returns: 收到的全部行，以及丟出的錯誤；正常結束時錯誤為 nil
    static func collectLines(
        from lines: LKAIHTTPLines,
        onLine: (String) -> Void = { _ in }
    ) async -> LinesOutcome {
        var receivedLines: [String] = []
        var actualError: LKAIError?
        do {
            for try await line in lines {
                receivedLines.append(line)
                onLine(line)
            }
        } catch {
            actualError = error
        }
        return LinesOutcome(lines: receivedLines, error: actualError)
    }
}
