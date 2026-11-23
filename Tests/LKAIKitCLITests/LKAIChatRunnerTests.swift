//
//  LKAIChatRunnerTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAIChatRunner` 的單元測試：回答完成與被截斷時，標準輸出與標準錯誤寫什麼、寫的時機，
/// 以及回傳的結果
///
/// - Note: 以 `MockChatClient` 替代真實的 client，以 `ChatRunRecorder` 記錄輸出，不連網
/// - Note: 失敗的路徑（`LKAIError`、沒有結束事件就結束）由之後的任務補測試
struct LKAIChatRunnerTests {

    // MARK: - Properties

    /// 兩種不是 `completed` 的結束原因，各自要出現在警告裡的詞與對應的警告字串
    private static let finishReasonCases = [
        FinishReasonCase(
            finishReason: .maxOutputTokens,
            warningText: .warningMaxOutputTokens,
            expectedToken: "--max-output-tokens"
        ),
        FinishReasonCase(
            finishReason: .contextWindowExceeded,
            warningText: .warningContextWindowExceeded,
            expectedToken: "context window"
        ),
    ]

    /// 兩種輸出方式
    private static let outputModes: [LKAIChatRunner.OutputMode] = [.invoke, .stream]

    // spectra-scenario: cli-chat / Print the complete answer
    // spectra-scenario: cli-chat / Print the complete answer / trailing line terminator
    /// 驗證不加 `--stream` 時，回答完成後一次寫到標準輸出：結尾不是 LF（`\n`）才補一個 LF，
    /// 以 CR（`\r`）加 LF 結尾的不補，空回答什麼都不寫；標準錯誤為空，結果是 `.completed`
    ///
    /// - Parameters:
    ///   - answer: client 回傳的回答文字
    ///   - expectedOutput: 預期寫到標準輸出的全部文字，對應範例表的四列
    @Test(arguments: [
        ("Hello", "Hello\n"),
        ("Hello\n", "Hello\n"),
        ("Hello\r\n", "Hello\r\n"),
        ("", ""),
    ])
    func run_invoke完成_依結尾規則補LF且stderr為空(answer: String, expectedOutput: String) async {
        // Given
        let recorder = ChatRunRecorder()
        let client = makeClient(answer: answer, finishReason: .completed)
        let runner = makeRunner(client: client, recorder: recorder)

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        #expect(recorder.standardOutput == expectedOutput)
        #expect(recorder.standardError.isEmpty)
        #expect(outcome == .completed)
    }

    // spectra-scenario: cli-chat / Write deltas as they arrive
    /// 驗證 `--stream` 每收到一段文字就寫到標準輸出，寫完才讀下一個事件：`Hel` 先於第二個事件被讀取，
    /// `lo` 先於第三個事件被讀取；標準輸出正好是 `Hello` 加 LF，結果是 `.completed`
    ///
    /// - Note: 事件來源只在迭代器要下一個事件時才交出，所以時間軸的先後就是「寫入」與「讀取」的先後
    @Test
    func run_stream收到文字_先寫入再讀取下一個事件且stdout為完整回答() async throws {
        // Given
        let recorder = ChatRunRecorder()
        let events: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            .finished(makeCompletion(.completed)),
        ]
        let client = MockChatClient(streamSource: recorder.makeStreamSource(events: events))
        let runner = makeRunner(client: client, recorder: recorder)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        let timeline = recorder.timeline
        let firstWrite = try #require(timeline.firstIndex(of: .writeStandardOutput("Hel")))
        let secondRead = try #require(timeline.firstIndex(of: .readEvent(2)))
        let secondWrite = try #require(timeline.firstIndex(of: .writeStandardOutput("lo")))
        let thirdRead = try #require(timeline.firstIndex(of: .readEvent(3)))
        #expect(firstWrite < secondRead)
        #expect(secondWrite < thirdRead)
        #expect(recorder.standardOutput == "Hello\n")
        #expect(outcome == .completed)
    }

    // spectra-scenario: cli-chat / Apply the trailing line terminator rule to a stream
    // spectra-scenario: cli-chat / Apply the trailing line terminator rule to a stream / streamed line terminators
    /// 驗證 `--stream` 結束後，寫過文字而且最後一個位元組不是 LF（`\n`）才補一個 LF；
    /// 沒有任何文字時什麼都不寫；標準錯誤為空，結果是 `.completed`
    ///
    /// - Parameters:
    ///   - deltas: 依序交出的文字片段，之後是結束原因為 `completed` 的結束事件
    ///   - expectedOutput: 預期寫到標準輸出的全部文字，對應範例表的五列
    @Test(arguments: [
        (["Hel", "lo"], "Hello\n"),
        (["Hel", "lo\n"], "Hello\n"),
        (["Hel", "lo\r\n"], "Hello\r\n"),
        (["Hel", ""], "Hel\n"),
        ([], ""),
    ] as [([String], String)])
    func run_stream完成_依結尾規則補LF且stderr為空(
        deltas: [String],
        expectedOutput: String
    ) async {
        // Given
        let recorder = ChatRunRecorder()
        let finishedEvent = LKAIChatStreamEvent.finished(makeCompletion(.completed))
        let events = deltas.map { LKAIChatStreamEvent.textDelta($0) } + [finishedEvent]
        let client = MockChatClient(streamEvents: events)
        let runner = makeRunner(client: client, recorder: recorder)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        #expect(recorder.standardOutput == expectedOutput)
        #expect(recorder.standardError.isEmpty)
        #expect(outcome == .completed)
    }

    // spectra-scenario: cli-chat / Warn about an answer that stopped early
    // spectra-scenario: cli-chat / Warn about an answer that stopped early / finish reasons
    /// 驗證結束原因不是 `completed` 時，兩種輸出方式都照樣寫出回答與結尾的 LF，
    /// 標準錯誤第一行以 `Warning: ` 開頭並含指定的詞，結果是 `.incomplete`
    ///
    /// - Parameters:
    ///   - testCase: 一列範例：結束原因、對應的警告字串，以及英文警告要含有的詞
    ///   - mode: 輸出方式，不加 `--stream` 或加 `--stream`
    /// - Note: 輸出語言是 `en-US`，回答文字是 `Partial`
    @Test(arguments: LKAIChatRunnerTests.finishReasonCases, LKAIChatRunnerTests.outputModes)
    func run_回答被截斷_stdout為完整回答且stderr第一行是含指定詞的警告(
        testCase: FinishReasonCase,
        mode: LKAIChatRunner.OutputMode
    ) async throws {
        // Given
        let recorder = ChatRunRecorder()
        let client = makeClient(answer: "Partial", finishReason: testCase.finishReason)
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = try #require(lines.first)
        #expect(recorder.standardOutput == "Partial\n")
        #expect(firstLine.hasPrefix("Warning: "))
        #expect(firstLine.contains(testCase.expectedToken))
        #expect(recorder.standardError.hasSuffix("\n"))
        #expect(outcome == .incomplete)
    }

    // spectra-scenario: cli-output-language / Translate an incomplete answer warning
    /// 驗證輸出語言是 `zh-TW` 時，警告是 `Warning: ` 加上 `zh-Hant` 的警告字串，標準錯誤只有這一行
    ///
    /// - Parameters:
    ///   - testCase: 一列範例：結束原因，以及對應的警告字串
    ///   - mode: 輸出方式，不加 `--stream` 或加 `--stream`
    /// - Note: 期望值以 `LKAICLIText` 查出，不在測試裡寫死翻譯
    @Test(arguments: LKAIChatRunnerTests.finishReasonCases, LKAIChatRunnerTests.outputModes)
    func run_輸出語言為zhTW_警告是該語言的翻譯(
        testCase: FinishReasonCase,
        mode: LKAIChatRunner.OutputMode
    ) async {
        // Given
        let recorder = ChatRunRecorder()
        let client = makeClient(answer: "Partial", finishReason: testCase.finishReason)
        let runner = makeRunner(client: client, recorder: recorder, language: .zhTW)
        let expectedWarning = "Warning: " + testCase.warningText.string(in: .zhTW) + "\n"

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        #expect(recorder.standardError == expectedWarning)
        #expect(outcome == .incomplete)
    }

    /// 驗證不加 `--stream` 時只呼叫 `invoke(_:)`，不呼叫 `stream(_:)`，而且請求原樣交給 client
    @Test
    func run_invoke模式_只呼叫invoke並原樣傳入請求() async {
        // Given
        let request = makeRequest()
        let client = makeClient(answer: "Hi", finishReason: .completed)
        let runner = makeRunner(client: client, recorder: ChatRunRecorder())

        // When
        _ = await runner.run(request, mode: .invoke)

        // Then
        #expect(client.invokeReceivedRequests == [request])
        #expect(client.streamReceivedRequests.isEmpty)
    }

    /// 驗證加 `--stream` 時只呼叫 `stream(_:)`，不呼叫 `invoke(_:)`，而且請求原樣交給 client
    @Test
    func run_stream模式_只呼叫stream並原樣傳入請求() async {
        // Given
        let request = makeRequest()
        let client = makeClient(answer: "Hi", finishReason: .completed)
        let runner = makeRunner(client: client, recorder: ChatRunRecorder())

        // When
        _ = await runner.run(request, mode: .stream)

        // Then
        #expect(client.streamReceivedRequests == [request])
        #expect(client.invokeReceivedRequests.isEmpty)
    }
}

// MARK: - Nested Types

extension LKAIChatRunnerTests {

    /// 回答被截斷的一列範例：結束原因、對應的警告字串，以及英文警告要含有的詞
    struct FinishReasonCase: Sendable {

        /// 結束事件帶的結束原因
        let finishReason: LKAIFinishReason

        /// 這個結束原因對應的警告字串
        let warningText: LKAICLIText

        /// 英文警告一定要含有的詞
        let expectedToken: String
    }
}

// MARK: - Private Method

private extension LKAIChatRunnerTests {

    /// 組出兩種輸出方式都回傳同一個回答的 client
    ///
    /// - Parameters:
    ///   - answer: 回答的文字；串流時是唯一的一段文字
    ///   - finishReason: 結束時帶的結束原因
    /// - Returns: `invoke(_:)` 與 `stream(_:)` 都交出這個回答的替身 client
    func makeClient(answer: String, finishReason: LKAIFinishReason) -> MockChatClient {
        let completion = makeCompletion(finishReason)
        return MockChatClient(
            invokeResult: .success(LKAIChatResponse(text: answer, completion: completion)),
            streamEvents: [.textDelta(answer), .finished(completion)]
        )
    }

    /// 組出只有結束原因有意義的結束資訊
    ///
    /// - Parameter finishReason: 結束原因
    /// - Returns: 沒有用量、沒有回答模型的結束資訊
    func makeCompletion(_ finishReason: LKAIFinishReason) -> LKAIChatCompletion {
        LKAIChatCompletion(finishReason: finishReason, usage: nil, respondingModel: nil)
    }

    /// 組出受測的執行器，輸出寫進記錄器
    ///
    /// - Parameters:
    ///   - client: 替身 client
    ///   - recorder: 記錄輸出的記錄器
    ///   - language: 輸出語言，預設是 `en-US`
    /// - Returns: 受測的執行器
    func makeRunner(
        client: MockChatClient,
        recorder: ChatRunRecorder,
        language: LKAIOutputLanguage = .enUS
    ) -> LKAIChatRunner {
        LKAIChatRunner(
            client: client,
            output: recorder.output,
            language: language,
            apiKey: LKAIAPIKey("sk-secret-123")
        )
    }

    /// 組出固定的對話請求；執行器要原樣交給 client，內容與結果無關
    ///
    /// - Returns: 一則使用者訊息、沒有系統指示的請求
    func makeRequest() -> LKAIChatRequest {
        LKAIChatRequest(
            model: "test-model",
            messages: [LKAIMessage(role: .user, text: "hi")],
            systemPrompt: nil,
            maxOutputTokens: 4096
        )
    }
}
