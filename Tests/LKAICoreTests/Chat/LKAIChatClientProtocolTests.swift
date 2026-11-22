//
//  LKAIChatClientProtocolTests.swift
//  LKAICoreTests
//
//  Created by Leo Ho on 2026/11/21.
//

import Testing

@testable import LKAICore

/// `LKAIChatClientProtocol` 的單元測試，以只實作串流的測試替身驗證非串流呼叫的預設實作
struct LKAIChatClientProtocolTests {

    // MARK: - Properties

    /// 測試共用的合法請求，各測試只讀取、不改動
    private let request = LKAIChatRequest(
        model: "claude-opus-5-5",
        messages: [LKAIMessage(role: .user, text: "Hi")],
        maxOutputTokens: 1024
    )

    // spectra-scenario: chat-client / Receive a complete response
    /// 驗證來源依序送出兩段文字與結束事件後，非串流呼叫回傳串接好的文字，並原樣帶入結束資訊
    @Test
    func invoke_正常完成_串接文字並原樣帶入結束資訊() async throws {
        // Given
        let usage = LKAIUsage(
            inputTokens: 10,
            outputTokens: 5,
            cachedInputTokens: nil,
            reasoningOutputTokens: nil
        )
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: usage,
            respondingModel: "claude-opus-4-8"
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.yield(.textDelta("lo"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.text == "Hello")
        #expect(response.completion.finishReason == .completed)
        #expect(response.completion == completion)
    }

    // spectra-scenario: chat-client / Non-streaming call stops at the output token limit
    /// 驗證生成到輸出上限時，非串流呼叫回傳已生成的文字，結束原因是輸出上限，而且不丟錯
    @Test
    func invoke_達到輸出上限_回傳已生成的文字與maxOutputTokens() async throws {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .maxOutputTokens,
            usage: nil,
            respondingModel: nil
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Partial"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.text == "Partial")
        #expect(response.completion.finishReason == .maxOutputTokens)
    }

    // spectra-scenario: chat-client / Non-streaming call stops when the context window is full
    /// 驗證生成途中塞滿 context window 時，非串流呼叫回傳已生成的文字，結束原因是 context window 已滿，而且不丟錯
    @Test
    func invoke_塞滿contextWindow_回傳已生成的文字與contextWindowExceeded() async throws {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .contextWindowExceeded,
            usage: nil,
            respondingModel: nil
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Partial"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.text == "Partial")
        #expect(response.completion.finishReason == .contextWindowExceeded)
    }

    // spectra-scenario: chat-client / Non-streaming call refused after partial text
    /// 驗證生成到一半被拒答時，非串流呼叫丟出帶著拒答原因的錯誤，而且不回傳前面已生成的文字
    @Test
    func invoke_生成一半被拒答_丟出refused且不回傳結果() async throws {
        // Given
        var response: LKAIChatResponse?
        var actualError: LKAIError?
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Sure"))
        sourceContinuation.finish(throwing: LKAIError.refused(detail: "cyber"))
        let client = ScriptedChatClient(source: source)

        // When
        do {
            response = try await client.invoke(request)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == .refused(detail: "cyber"))
        #expect(response == nil)
    }

    // spectra-scenario: chat-client / Non-streaming call on a stream without a finish
    /// 驗證來源送出一段文字後直接關閉、沒有結束事件時，非串流呼叫丟出無效回應錯誤
    @Test
    func invoke_沒有結束事件就關閉_丟出invalidResponse() async throws {
        // Given
        var actualError: LKAIError?
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        do {
            _ = try await client.invoke(request)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        let isInvalidResponse = if case .invalidResponse = error {
            true
        } else {
            false
        }
        #expect(isInvalidResponse)
    }

    // spectra-scenario: chat-client / Cancel a non-streaming call
    /// 驗證等待中的非串流呼叫被取消時，丟出 cancelled 錯誤，不回傳已收到的文字
    ///
    /// - Note: 等替身的串流被請求之後才取消，避免取消落在 invoke 開始之前
    @Test(.timeLimit(.minutes(1)))
    func invoke_等待中被取消_丟出cancelled() async throws {
        // Given
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        let (streamStartedSignals, streamStartedSignal) = AsyncStream<Void>.makeStream()
        let client = ScriptedChatClient(source: source, streamStarted: streamStartedSignal)

        // When
        let task = Task<LKAIError?, Never> {
            do throws(LKAIError) {
                _ = try await client.invoke(request)
                return nil
            } catch {
                return error
            }
        }
        for await _ in streamStartedSignals {
            break
        }
        task.cancel()
        let actualError = await task.value

        // Then
        let error = try #require(actualError)
        #expect(error == .cancelled)
    }

    // spectra-scenario: chat-client / Cancel a non-streaming call
    /// 驗證非串流呼叫的 task 已被取消、而來源的結束事件已在緩衝區時，呼叫丟出 cancelled 錯誤，不回傳任何結果
    ///
    /// - Note: `AsyncThrowingStream` 取消後仍會交出緩衝區裡的元素，所以取消要在收到結束事件後再檢查
    @Test(.timeLimit(.minutes(1)))
    func invoke_task已取消且結束事件已緩衝_丟出cancelled且不回傳結果() async throws {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: nil
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.yield(.finished(completion))
        let client = ScriptedChatClient(source: source)
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()

        // When
        let task = Task<(response: LKAIChatResponse?, error: LKAIError?), Never> {
            for await _ in gate {}
            do throws(LKAIError) {
                let response = try await client.invoke(request)
                return (response: response, error: nil)
            } catch {
                return (response: nil, error: error)
            }
        }
        task.cancel()
        gateContinuation.finish()
        let outcome = await task.value

        // Then
        let error = try #require(outcome.error)
        #expect(error == .cancelled)
        #expect(outcome.response == nil)
    }

    /// 驗證非串流呼叫被取消後，來源才丟出頻率限制錯誤，呼叫仍丟出 cancelled，錯誤不外漏
    @Test(.timeLimit(.minutes(1)))
    func invoke_取消後來源才丟出頻率限制_仍丟出cancelled() async throws {
        // Given
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.onTermination = { termination in
            if case .cancelled = termination {
                sourceContinuation.finish(throwing: LKAIError.rateLimited(retryAfter: .seconds(30)))
            }
        }
        sourceContinuation.yield(.textDelta("Hel"))
        let client = ScriptedChatClient(source: source)

        // When
        let task = Task<LKAIError?, Never> {
            do throws(LKAIError) {
                _ = try await client.invoke(request)
                return nil
            } catch {
                return error
            }
        }
        task.cancel()
        let actualError = await task.value

        // Then
        let error = try #require(actualError)
        #expect(error == .cancelled)
    }

    /// 驗證來源丟出對話錯誤而且呼叫沒有被取消時，非串流呼叫原樣丟出該錯誤，不改寫成其他錯誤
    ///
    /// - Parameter sourceError: 來源丟出的對話錯誤，範例是限流、服務暫時無法使用與 API 金鑰無效
    @Test(arguments: [
        LKAIError.rateLimited(retryAfter: .seconds(30)),
        .serviceUnavailable(statusCode: 529, retryAfter: nil),
        .invalidAPIKey,
    ] as [LKAIError])
    func invoke_串流丟出對話錯誤且未取消_原樣丟出(sourceError: LKAIError) async throws {
        // Given
        var actualError: LKAIError?
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.finish(throwing: sourceError)
        let client = ScriptedChatClient(source: source)

        // When
        do {
            _ = try await client.invoke(request)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == sourceError)
    }

    /// 驗證供應商回報的回應模型原樣帶進非串流結果
    @Test
    func invoke_供應商回報回應模型_原樣帶進結果() async throws {
        // Given
        let usage = LKAIUsage(
            inputTokens: 10,
            outputTokens: 5,
            cachedInputTokens: nil,
            reasoningOutputTokens: nil
        )
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: usage,
            respondingModel: "claude-opus-4-8"
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.completion.respondingModel == "claude-opus-4-8")
    }

    // spectra-scenario: chat-client / Provider reports no model
    /// 驗證供應商正常結束卻沒有回報實際產生輸出的模型時，非串流結果不帶回應模型
    @Test
    func invoke_供應商沒有回報回應模型_回應模型為nil() async throws {
        // Given
        let usage = LKAIUsage(
            inputTokens: 10,
            outputTokens: 5,
            cachedInputTokens: nil,
            reasoningOutputTokens: nil
        )
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: usage,
            respondingModel: nil
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.completion.respondingModel == nil)
    }

    /// 驗證供應商沒有回報用量時，非串流結果的用量為 nil，呼叫不因此失敗
    @Test
    func invoke_供應商沒有回報用量_用量為nil() async throws {
        // Given
        let completion = LKAIChatCompletion(
            finishReason: .completed,
            usage: nil,
            respondingModel: "claude-opus-4-8"
        )
        let (source, sourceContinuation) = Source.makeStream()
        sourceContinuation.yield(.textDelta("Hel"))
        sourceContinuation.yield(.finished(completion))
        sourceContinuation.finish()
        let client = ScriptedChatClient(source: source)

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.completion.usage == nil)
    }
}

// MARK: - Nested Types

extension LKAIChatClientProtocolTests {

    /// 來源序列的型別，寫短一點方便閱讀
    typealias Source = AsyncThrowingStream<LKAIChatStreamEvent, any Error>

    /// 只實作串流呼叫的測試替身，非串流呼叫走協定的預設實作
    struct ScriptedChatClient: LKAIChatClientProtocol {

        /// 事件的來源，由測試決定何時送出事件、何時結束或丟出錯誤
        let source: Source

        /// 串流被請求時送出一個訊號的通道，讓測試知道非串流呼叫已開始；不需要時為 nil
        let streamStarted: AsyncStream<Void>.Continuation?

        /// 建立測試替身
        ///
        /// - Parameters:
        ///   - source: 事件的來源
        ///   - streamStarted: 串流被請求時送出訊號的通道，預設為 nil
        init(source: Source, streamStarted: AsyncStream<Void>.Continuation? = nil) {
            self.source = source
            self.streamStarted = streamStarted
        }

        /// 把來源包成串流交回，不檢查請求的內容
        ///
        /// - Parameter request: 要送出的請求，測試替身不使用
        /// - Returns: 依來源送出事件的串流
        func stream(_ request: LKAIChatRequest) -> LKAIChatStream {
            streamStarted?.yield()
            return LKAIChatStream(source)
        }
    }
}
