//
//  LKAIChatRunnerTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAIChatRunner` 的單元測試：回答完成、被截斷與失敗時，標準輸出與標準錯誤寫什麼、
/// 寫的時機，以及回傳的結果
///
/// - Note: 以 `MockChatClient` 替代真實的 client，以 `ChatRunRecorder` 記錄輸出，不連網
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

    /// 範例表 stream endings 的兩列：串流交出 `Hel`、`lo` 之後，以結束原因 `completed` 的結束事件結束，
    /// 或以 `serviceUnavailable(statusCode: 500, retryAfter: nil)` 失敗
    private static let streamEndingCases = [
        StreamEndingCase(
            events: [
                .textDelta("Hel"),
                .textDelta("lo"),
                .finished(
                    LKAIChatCompletion(finishReason: .completed, usage: nil, respondingModel: nil)
                ),
            ],
            streamError: nil
        ),
        StreamEndingCase(
            events: [.textDelta("Hel"), .textDelta("lo")],
            streamError: .serviceUnavailable(statusCode: 500, retryAfter: nil)
        ),
    ]

    /// 範例表 failing writes 的兩列：回答 `Hello`，失敗的是回答文字那一次，或結尾 LF（`\n`）那一次
    private static let failingWriteCases = [
        FailingWriteCase(failingIndex: 1, expectedAttempts: ["Hello"], expectedOutput: ""),
        FailingWriteCase(
            failingIndex: 2,
            expectedAttempts: ["Hello", "\n"],
            expectedOutput: "Hello"
        ),
    ]

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

    // spectra-scenario: cli-chat / Report the error and its detail
    // spectra-scenario: cli-chat / Report the error and its detail / detail lines
    /// 驗證不加 `--stream` 時 client 丟出 `LKAIError`：標準輸出為空，標準錯誤第一行是 `Error: `
    /// 加上該錯誤的 `en` 說明，第二行是範例表的細節行，沒有細節時標準錯誤只有一行；結果是 `.failed`
    ///
    /// - Parameter testCase: 一列範例：client 丟出的錯誤，以及預期的第二行；沒有第二行時為 nil
    /// - Note: 範例表之外多加一列：細節是空字串時不印 `Details:` 行
    /// - Note: 第一行的期望值以 `errorDescription(localization:)` 查出，不在測試裡寫死說明
    @Test(arguments: [
        DetailLineCase(
            error: .invalidRequest(message: "model not found"),
            expectedSecondLine: "Details: model not found"
        ),
        DetailLineCase(error: .invalidRequest(message: nil), expectedSecondLine: nil),
        DetailLineCase(error: .invalidRequest(message: ""), expectedSecondLine: nil),
        DetailLineCase(error: .refused(detail: "cyber"), expectedSecondLine: "Details: cyber"),
        DetailLineCase(error: .refused(detail: nil), expectedSecondLine: nil),
        DetailLineCase(
            error: .invalidResponse(reason: "Stream ended before a finish event"),
            expectedSecondLine: "Details: Stream ended before a finish event"
        ),
        DetailLineCase(
            error: .transport(underlying: URLError(.timedOut)),
            expectedSecondLine: "Details: URLError -1001"
        ),
        DetailLineCase(
            error: .rateLimited(retryAfter: .seconds(30)),
            expectedSecondLine: "Details: retry after 30 seconds"
        ),
        DetailLineCase(error: .rateLimited(retryAfter: nil), expectedSecondLine: nil),
        DetailLineCase(
            error: .serviceUnavailable(statusCode: 503, retryAfter: nil),
            expectedSecondLine: "Details: status 503"
        ),
        DetailLineCase(
            error: .serviceUnavailable(statusCode: 529, retryAfter: .seconds(10)),
            expectedSecondLine: "Details: status 529, retry after 10 seconds"
        ),
        DetailLineCase(error: .invalidAPIKey, expectedSecondLine: nil),
        DetailLineCase(error: .permissionDenied, expectedSecondLine: nil),
        DetailLineCase(error: .quotaExceeded, expectedSecondLine: nil),
        DetailLineCase(error: .cancelled, expectedSecondLine: nil),
    ])
    func run_invoke失敗_stderr是錯誤說明加上範例表的細節行且stdout為空(
        testCase: DetailLineCase
    ) async {
        // Given
        let recorder = ChatRunRecorder()
        let client = MockChatClient(invokeResult: .failure(testCase.error))
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)
        let expectedDescription = testCase.error.errorDescription(localization: "en")
        let expectedFirstLine = "Error: \(expectedDescription)\n"
        let expectedSecondLine = testCase.expectedSecondLine.map { $0 + "\n" } ?? ""

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        #expect(recorder.standardError == expectedFirstLine + expectedSecondLine)
        #expect(recorder.standardOutput.isEmpty)
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Redact the API key in the detail
    /// 驗證細節裡出現的 API 金鑰，在兩種輸出方式都換成 `[REDACTED]`，標準錯誤不含金鑰
    ///
    /// - Parameters:
    ///   - testCase: 一列範例：client 丟出的 `invalidRequest` 的訊息，以及預期的第二行
    ///   - mode: 輸出方式，不加 `--stream` 或加 `--stream`
    /// - Note: 金鑰是 `sk-secret-123`；第二列是範例之外多加的：同一個金鑰出現兩次，兩次都要換掉
    @Test(
        arguments: [
            RedactionCase(
                message: "Incorrect API key provided: sk-secret-123",
                expectedSecondLine: "Details: Incorrect API key provided: [REDACTED]"
            ),
            RedactionCase(
                message: "sk-secret-123 and sk-secret-123",
                expectedSecondLine: "Details: [REDACTED] and [REDACTED]"
            ),
        ],
        LKAIChatRunnerTests.outputModes
    )
    func run_細節含API金鑰_換成REDACTED且stderr不含金鑰(
        testCase: RedactionCase,
        mode: LKAIChatRunner.OutputMode
    ) async throws {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.invalidRequest(message: testCase.message)
        let client = MockChatClient(
            invokeResult: .failure(error),
            streamEvents: [],
            streamError: error
        )
        let runner = makeRunner(client: client, recorder: recorder)

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLine = try #require(lines.dropFirst().first)
        #expect(secondLine == testCase.expectedSecondLine)
        #expect(!recorder.standardError.contains("sk-secret-123"))
        #expect(outcome == .failed)
    }

    /// 驗證 API 金鑰是空字串時不做遮蔽，細節照原樣印出
    ///
    /// - Note: 空字串當成要換掉的文字，會在細節的每個位置都插入 `[REDACTED]`，所以空字串要略過
    @Test
    func run_金鑰是空字串_細節照原樣印出() async throws {
        // Given
        let recorder = ChatRunRecorder()
        let client = MockChatClient(invokeResult: .failure(.invalidRequest(message: "bad request")))
        let runner = makeRunner(client: client, recorder: recorder, apiKey: "")

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLine = try #require(lines.dropFirst().first)
        #expect(secondLine == "Details: bad request")
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Keep a multi-line detail as received
    /// 驗證細節含 LF（`\n`）時照原樣寫出，所以標準錯誤超過兩行：`Error: ` 加 `en` 的說明、
    /// `Details: first`、`second`，每一行都以 LF 結尾；結果是 `.failed`
    ///
    /// - Note: 輸出語言是 `en-US`，不加 `--stream`，client 丟出 `invalidRequest`，訊息是 `first`、
    ///   LF、`second`
    /// - Note: 第一行的期望值以 `errorDescription(localization:)` 查出，不在測試裡寫死說明
    @Test
    func run_invoke細節含LF_stderr照原樣保留多行() async {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.invalidRequest(message: "first\nsecond")
        let client = MockChatClient(invokeResult: .failure(error))
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)
        let expectedDescription = LKAIError.invalidRequest(message: nil)
            .errorDescription(localization: "en")

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        #expect(recorder.standardError == "Error: \(expectedDescription)\nDetails: first\nsecond\n")
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Write an answer that repeats the key unchanged
    /// 驗證回答的文字含 API 金鑰時，原樣寫到標準輸出，不遮蔽；標準錯誤為空，結果是 `.completed`
    ///
    /// - Note: spec 只保證 `lkai` 自己產生的文字（警告、錯誤說明與細節）不含金鑰；回答是 AI 的輸出，
    ///   照原樣寫出，不當成 `lkai` 的訊息處理
    /// - Note: 金鑰是 `sk-secret-123`，回答文字是 `key: sk-secret-123`，結束原因是 `completed`
    @Test
    func run_invoke回答含API金鑰_stdout原樣寫出且stderr為空() async {
        // Given
        let recorder = ChatRunRecorder()
        let client = makeClient(answer: "key: sk-secret-123", finishReason: .completed)
        let runner = makeRunner(
            client: client,
            recorder: recorder,
            language: .enUS,
            apiKey: "sk-secret-123"
        )

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        #expect(recorder.standardOutput == "key: sk-secret-123\n")
        #expect(recorder.standardError.isEmpty)
        #expect(outcome == .completed)
    }

    // spectra-scenario: cli-chat / Report a timeout
    /// 驗證逾時（`URLError(.timedOut)`）在兩種輸出方式都是 `Details: URLError -1001`，
    /// 位在標準錯誤的第二行，結果是 `.failed`
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    @Test(arguments: LKAIChatRunnerTests.outputModes)
    func run_逾時_第二行是URLError代碼且結果為失敗(mode: LKAIChatRunner.OutputMode) async throws {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.transport(underlying: URLError(.timedOut))
        let client = MockChatClient(
            invokeResult: .failure(error),
            streamEvents: [],
            streamError: error
        )
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLine = try #require(lines.dropFirst().first)
        #expect(secondLine == "Details: URLError -1001")
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-output-language / Translate an error from the AI service
    /// 驗證輸出語言是 `zh-TW` 時，`invalidAPIKey` 的標準錯誤第一行是 `Error: ` 加上 `zh-Hant` 的說明，
    /// 沒有第二行，結果是 `.failed`
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    /// - Note: 期望值以 `errorDescription(localization:)` 查出，不在測試裡寫死翻譯
    @Test(arguments: LKAIChatRunnerTests.outputModes)
    func run_輸出語言為zhTW_錯誤說明是該語言的翻譯(mode: LKAIChatRunner.OutputMode) async {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.invalidAPIKey
        let client = MockChatClient(
            invokeResult: .failure(error),
            streamEvents: [],
            streamError: error
        )
        let runner = makeRunner(client: client, recorder: recorder, language: .zhTW)
        let expectedDescription = error.errorDescription(localization: "zh-Hant")
        let expectedStandardError = "Error: \(expectedDescription)\n"

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        #expect(recorder.standardError == expectedStandardError)
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Keep partial streamed text on failure
    /// 驗證 `--stream` 失敗時，標準輸出保留失敗前收到的文字，結尾不是 LF（`\n`）就補一個 LF，
    /// 補的 LF 先寫到標準輸出，再寫標準錯誤，第一行以 `Error: ` 開頭；結果是 `.failed`
    ///
    /// - Parameters:
    ///   - deltas: 失敗前依序交出的文字片段
    ///   - expectedOutput: 預期的標準輸出；第一列是 spec 的寫法，第二列是結尾已經是 LF 的情況
    /// - Note: 順序以時間軸斷言：標準輸出的寫入都排在第一個標準錯誤寫入之前；第二列沒有補 LF，
    ///   這一項只是確認沒有多寫
    @Test(arguments: [
        (["Hel"], "Hel\n"),
        (["Hel", "lo\n"], "Hello\n"),
    ] as [([String], String)])
    func run_stream中途失敗_stdout保留已收到的文字並補LF(
        deltas: [String],
        expectedOutput: String
    ) async {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.serviceUnavailable(statusCode: 500, retryAfter: nil)
        let client = MockChatClient(
            streamEvents: deltas.map { LKAIChatStreamEvent.textDelta($0) },
            streamError: error
        )
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        #expect(recorder.standardOutput == expectedOutput)
        #expect(standardOutputWritesPrecedeStandardError(in: recorder.timeline))
        #expect(recorder.standardError.hasPrefix("Error: "))
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Fail a stream before any text
    /// 驗證 `--stream` 在沒有任何文字之前就失敗時，標準輸出為空，標準錯誤第一行以 `Error: ` 開頭；
    /// 結果是 `.failed`
    @Test
    func run_stream一開始就失敗_stdout為空且stderr有錯誤() async {
        // Given
        let recorder = ChatRunRecorder()
        let error = LKAIError.serviceUnavailable(statusCode: 500, retryAfter: nil)
        let client = MockChatClient(streamEvents: [], streamError: error)
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        #expect(recorder.standardOutput.isEmpty)
        #expect(recorder.standardError.hasPrefix("Error: "))
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Report a stream that ends without a finish event
    /// 驗證 `--stream` 沒有收到結束事件、也沒有錯誤就結束時，當成 `invalidResponse` 失敗：
    /// 已收到的文字保留並補 LF，標準錯誤第一行是 `Error: ` 加上 `invalidResponse` 的 `en` 說明，
    /// 第二行是 `Details: Stream ended before a finish event`；補的 LF 先寫到標準輸出，再寫標準錯誤；
    /// 結果是 `.failed`
    ///
    /// - Parameters:
    ///   - deltas: 結束前依序交出的文字片段，之後直接結束，沒有結束事件
    ///   - expectedOutput: 預期的標準輸出；第一列是 spec 的寫法，第二列是連文字都沒有的情況
    /// - Note: 順序以時間軸斷言：標準輸出的寫入都排在第一個標準錯誤寫入之前；第二列沒有任何文字，
    ///   所以沒有標準輸出的寫入
    @Test(arguments: [
        (["Hel"], "Hel\n"),
        ([], ""),
    ] as [([String], String)])
    func run_stream沒有結束事件就結束_當成失敗並寫出細節(
        deltas: [String],
        expectedOutput: String
    ) async {
        // Given
        let recorder = ChatRunRecorder()
        let client = MockChatClient(streamEvents: deltas.map { LKAIChatStreamEvent.textDelta($0) })
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)
        let reason = "Stream ended before a finish event"
        let expectedDescription = LKAIError.invalidResponse(reason: reason)
            .errorDescription(localization: "en")
        let expectedStandardError = "Error: \(expectedDescription)\nDetails: \(reason)\n"

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        #expect(recorder.standardOutput == expectedOutput)
        #expect(standardOutputWritesPrecedeStandardError(in: recorder.timeline))
        #expect(recorder.standardError == expectedStandardError)
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Report a failed write of the answer
    // spectra-scenario: cli-chat / Report a failed write of the answer / failing writes
    /// 驗證不加 `--stream` 時，標準輸出的寫入以 `CocoaError(.fileWriteOutOfSpace)` 失敗：
    /// 失敗之後不再寫標準輸出，標準錯誤第一行是 `Error: ` 加 `en` 的寫入失敗訊息，
    /// 第二行正好是 `Details: NSCocoaErrorDomain 640`，沒有其他行；結果是 `.failed`
    ///
    /// - Parameter testCase: 一列範例：失敗的是第幾次寫入，以及預期嘗試寫入與實際寫到的文字，
    ///   對應範例表的兩列
    /// - Note: 回答文字是 `Hello`，結束原因是 `completed`；失敗的那次寫入不算實際寫到標準輸出的文字
    @Test(arguments: LKAIChatRunnerTests.failingWriteCases)
    func run_invoke寫入失敗_stderr是寫入失敗訊息加Details且停止寫回答(
        testCase: FailingWriteCase
    ) async {
        // Given
        let recorder = makeFailingRecorder(failingIndex: testCase.failingIndex)
        let client = makeClient(answer: "Hello", finishReason: .completed)
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)
        let expectedStandardError = makeWriteFailureStandardError(language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: .invoke)

        // Then
        let attemptedWrites = attemptedStandardOutputWrites(in: recorder.timeline)
        #expect(attemptedWrites == testCase.expectedAttempts)
        #expect(recorder.standardOutput == testCase.expectedOutput)
        #expect(recorder.standardError == expectedStandardError)
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Stop reading the stream after a failed write
    /// 驗證 `--stream` 寫第一段文字 `Hel` 就以 `CocoaError(.fileWriteOutOfSpace)` 失敗：
    /// 只讀了第一個事件，失敗之後沒有任何標準輸出的寫入或寫入嘗試（沒有補 LF），
    /// 標準錯誤第二行正好是 `Details: NSCocoaErrorDomain 640`；結果是 `.failed`
    ///
    /// - Note: 事件來源只在迭代器要下一個事件時才交出，所以時間軸上的讀取次數就是實際讀取的事件數
    /// - Note: 串流依序交出 `Hel`、`lo`、結束原因為 `completed` 的結束事件，共三個事件
    @Test
    func run_stream第一段文字寫入失敗_只讀第一個事件且不補LF() async throws {
        // Given
        let recorder = makeFailingRecorder(failingIndex: 1)
        let events: [LKAIChatStreamEvent] = [
            .textDelta("Hel"),
            .textDelta("lo"),
            .finished(makeCompletion(.completed)),
        ]
        let client = MockChatClient(streamSource: recorder.makeStreamSource(events: events))
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        let timeline = recorder.timeline
        #expect(readEventIndexes(in: timeline) == [1])
        #expect(attemptedStandardOutputWrites(in: timeline) == ["Hel"])
        #expect(recorder.standardOutput.isEmpty)
        #expect(outcome == .failed)
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLine = try #require(lines.dropFirst().first)
        #expect(secondLine == "Details: NSCocoaErrorDomain 640")
    }

    // spectra-scenario: cli-chat / Report a failed write instead of a warning
    /// 驗證結束原因是 `maxOutputTokens`、寫 `Partial` 以 `CocoaError(.fileWriteOutOfSpace)` 失敗時，
    /// 兩種輸出方式都是：標準錯誤第一行以 `Error: ` 開頭，沒有任何一行以 `Warning: ` 開頭；
    /// 結果是 `.failed`，不是 `.incomplete`
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    @Test(arguments: LKAIChatRunnerTests.outputModes)
    func run_回答被截斷且寫入失敗_只有Error沒有Warning(mode: LKAIChatRunner.OutputMode) async throws {
        // Given
        let recorder = makeFailingRecorder(failingIndex: 1)
        let client = makeClient(answer: "Partial", finishReason: .maxOutputTokens)
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        let lines = recorder.standardError.split(separator: "\n", omittingEmptySubsequences: false)
        let hasWarningLine = lines.contains { $0.hasPrefix("Warning: ") }
        #expect(!hasWarningLine)
        #expect(outcome == .failed)
        let firstLine = try #require(lines.first)
        #expect(firstLine.hasPrefix("Error: "))
    }

    /// 驗證輸出語言是 `zh-TW` 時，寫入失敗的標準錯誤第一行是 `Error: ` 加 `zh-Hant` 的寫入失敗訊息，
    /// 第二行的 `Details:` 不翻譯；結果是 `.failed`
    ///
    /// - Parameter mode: 輸出方式，不加 `--stream` 或加 `--stream`
    /// - Note: 期望值以 `LKAICLIText` 查出，不在測試裡寫死翻譯
    @Test(arguments: LKAIChatRunnerTests.outputModes)
    func run_輸出語言為zhTW且寫入失敗_錯誤說明是該語言的翻譯(
        mode: LKAIChatRunner.OutputMode
    ) async {
        // Given
        let recorder = makeFailingRecorder(failingIndex: 1)
        let client = makeClient(answer: "Hello", finishReason: .completed)
        let runner = makeRunner(client: client, recorder: recorder, language: .zhTW)
        let expectedStandardError = makeWriteFailureStandardError(language: .zhTW)

        // When
        let outcome = await runner.run(makeRequest(), mode: mode)

        // Then
        #expect(recorder.standardError == expectedStandardError)
        #expect(outcome == .failed)
    }

    // spectra-scenario: cli-chat / Report a failed write of the trailing LF in a stream
    // spectra-scenario: cli-chat / Report a failed write of the trailing LF in a stream / stream endings
    /// 驗證 `--stream` 寫結尾的 LF（`\n`）以 `CocoaError(.fileWriteOutOfSpace)` 失敗時，兩種串流結束方式都是：
    /// 嘗試寫到標準輸出的內容正好是 `Hel`、`lo`、LF；標準錯誤正好是 `Error: ` 加 `en` 的寫入失敗訊息、
    /// LF、`Details: NSCocoaErrorDomain 640`、LF；結果是 `.failed`
    ///
    /// - Parameter testCase: 一列範例：串流交出 `Hel`、`lo` 之後的結束方式，對應範例表 stream endings 的兩列
    /// - Note: 第二列固定了使用者 2026-11-23 的決定：串流先以服務錯誤結束、補 LF 時又寫入失敗，
    ///   優先於串流的錯誤，只回報寫入失敗，不另外印出服務錯誤
    /// - Note: 第 3 次寫到標準輸出的就是結尾的 LF，前兩次是 `Hel`、`lo`
    @Test(arguments: LKAIChatRunnerTests.streamEndingCases)
    func run_stream補LF時寫入失敗_只回報寫入失敗且結果為失敗(testCase: StreamEndingCase) async {
        // Given
        let recorder = makeFailingRecorder(failingIndex: 3)
        let client = MockChatClient(
            streamEvents: testCase.events,
            streamError: testCase.streamError
        )
        let runner = makeRunner(client: client, recorder: recorder, language: .enUS)
        let expectedStandardError = makeWriteFailureStandardError(language: .enUS)

        // When
        let outcome = await runner.run(makeRequest(), mode: .stream)

        // Then
        #expect(attemptedStandardOutputWrites(in: recorder.timeline) == ["Hel", "lo", "\n"])
        #expect(recorder.standardError == expectedStandardError)
        #expect(outcome == .failed)
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

    /// 細節行的一列範例：client 丟出的錯誤，以及預期的第二行
    struct DetailLineCase: Sendable {

        /// client 丟出的錯誤
        let error: LKAIError

        /// 預期的標準錯誤第二行；沒有細節、標準錯誤只有一行時為 nil
        let expectedSecondLine: String?
    }

    /// 寫入失敗的一列範例：哪一次寫到標準輸出失敗，以及預期嘗試寫入與實際寫到的文字
    struct FailingWriteCase: Sendable {

        /// 失敗的是第幾次寫到標準輸出，從 1 開始
        let failingIndex: Int

        /// 預期嘗試寫到標準輸出的文字，依先後排列，失敗的那一次是最後一個
        let expectedAttempts: [String]

        /// 預期實際寫到標準輸出的全部文字，不含失敗的那一次
        let expectedOutput: String
    }

    /// 串流結束方式的一列範例：`Hel`、`lo` 之後的事件，以及讓串流失敗的錯誤
    struct StreamEndingCase: Sendable {

        /// 串流依序交出的事件；有結束事件時，它是最後一個
        let events: [LKAIChatStreamEvent]

        /// 交完事件後讓串流失敗的錯誤；nil 表示串流正常結束
        let streamError: LKAIError?
    }

    /// 遮蔽金鑰的一列範例：`invalidRequest` 的訊息，以及預期的第二行
    struct RedactionCase: Sendable {

        /// client 丟出的 `invalidRequest` 的訊息，含有 API 金鑰
        let message: String

        /// 預期的標準錯誤第二行，金鑰已換成 `[REDACTED]`
        let expectedSecondLine: String
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
    ///   - apiKey: 這次使用的 API 金鑰，預設是 `sk-secret-123`
    /// - Returns: 受測的執行器
    func makeRunner(
        client: MockChatClient,
        recorder: ChatRunRecorder,
        language: LKAIOutputLanguage = .enUS,
        apiKey: String = "sk-secret-123"
    ) -> LKAIChatRunner {
        LKAIChatRunner(
            client: client,
            output: recorder.output,
            language: language,
            apiKey: LKAIAPIKey(apiKey)
        )
    }

    /// 組出讓標準輸出的某一次寫入以 `CocoaError(.fileWriteOutOfSpace)` 失敗的記錄器
    ///
    /// - Parameter failingIndex: 失敗的是第幾次寫到標準輸出，從 1 開始
    /// - Returns: 只有那一次寫入失敗的記錄器
    func makeFailingRecorder(failingIndex: Int) -> ChatRunRecorder {
        let failingWrite: (index: Int, error: any Error) = (
            index: failingIndex,
            error: CocoaError(.fileWriteOutOfSpace)
        )
        return ChatRunRecorder(failingStandardOutputWrite: failingWrite)
    }

    /// 組出寫入失敗時預期的標準錯誤：`Error: ` 加該語言的寫入失敗訊息，再一行 `Details:`
    ///
    /// - Parameter language: 輸出語言
    /// - Returns: 兩行，各以 LF 結尾；`NSCocoaErrorDomain 640` 是 `CocoaError(.fileWriteOutOfSpace)`
    ///   的 domain 與 code
    func makeWriteFailureStandardError(language: LKAIOutputLanguage) -> String {
        let message = LKAICLIText.errorAnswerWriteFailed.string(in: language)
        return "Error: \(message)\nDetails: NSCocoaErrorDomain 640\n"
    }

    /// 取出時間軸上嘗試寫到標準輸出的文字，失敗的那一次也算
    ///
    /// - Parameter timeline: 記錄器的時間軸
    /// - Returns: 依先後排列的文字
    func attemptedStandardOutputWrites(in timeline: [ChatRunRecorder.TimelineEntry]) -> [String] {
        timeline.compactMap { entry in
            switch entry {
            case .writeStandardOutput(let text), .failedWriteStandardOutput(let text):
                return text

            case .readEvent, .writeStandardError:
                return nil
            }
        }
    }

    /// 判斷標準輸出的寫入（含失敗的那一次）是不是都排在第一個標準錯誤寫入之前
    ///
    /// - Parameter timeline: 記錄器的時間軸
    /// - Returns: 標準輸出的最後一次寫入排在標準錯誤的第一次寫入之前時為 true；
    ///   其中一邊沒有寫入時沒有先後可比，也是 true，是否有寫入由其他斷言檢查
    func standardOutputWritesPrecedeStandardError(
        in timeline: [ChatRunRecorder.TimelineEntry]
    ) -> Bool {
        let lastStandardOutputWrite = timeline.lastIndex { entry in
            switch entry {
            case .writeStandardOutput, .failedWriteStandardOutput:
                true

            case .readEvent, .writeStandardError:
                false
            }
        }
        let firstStandardErrorWrite = timeline.firstIndex { entry in
            guard case .writeStandardError = entry else {
                return false
            }
            return true
        }
        guard let lastStandardOutputWrite, let firstStandardErrorWrite else {
            return true
        }
        return lastStandardOutputWrite < firstStandardErrorWrite
    }

    /// 取出時間軸上讀取事件的序號
    ///
    /// - Parameter timeline: 記錄器的時間軸
    /// - Returns: 依先後排列的序號，每讀一次事件就有一個
    func readEventIndexes(in timeline: [ChatRunRecorder.TimelineEntry]) -> [Int] {
        timeline.compactMap { entry in
            guard case .readEvent(let index) = entry else {
                return nil
            }
            return index
        }
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
