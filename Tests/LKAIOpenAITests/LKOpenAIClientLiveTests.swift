//
//  LKOpenAIClientLiveTests.swift
//  LKAIOpenAITests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAICore
import Testing

@testable import LKAIOpenAI

/// `LKOpenAIClient` 對真實 OpenAI API 的測試，確認串流與非串流都能得到完成的回答
///
/// - Note: 只在設定環境變數 `LKAI_OPENAI_API_KEY` 時執行，沒有設定時顯示為略過
/// - Note: 會連線到真實的 API 並產生少量費用，由 owner 以自己的金鑰手動執行
/// - Note: 金鑰只從環境變數讀取，不寫進程式碼，也不放進任何輸出或斷言訊息
/// - Note: 以預設設定建立 client，不讓 OpenAI 保存這次的回應
struct LKOpenAIClientLiveTests {

    // MARK: - Properties

    /// 儲存 API 金鑰的環境變數名稱，給 trait 與測試本體共用
    private static let apiKeyEnvironmentName = "LKAI_OPENAI_API_KEY"

    /// 兩個測試共用的請求：要求模型只回一個詞，輸出上限 4096 個 token
    private let request = LKAIChatRequest(
        model: "gpt-6-luna",
        messages: [LKAIMessage(role: .user, text: "Reply with the single word OK.")],
        maxOutputTokens: 4096
    )

    /// 驗證串流呼叫真實 API 時，以完成結束，而且串接出的文字去掉空白後不為空
    @Test(.enabled(if: LKOpenAIClientLiveTests.isAPIKeyConfigured), .timeLimit(.minutes(2)))
    func stream_要求只回一個詞_以完成結束且文字不為空() async throws {
        // Given
        let apiKey = try #require(ProcessInfo.processInfo.environment[Self.apiKeyEnvironmentName])
        let client = LKOpenAIClient(
            apiKey: apiKey,
            urlSession: URLSession(configuration: .ephemeral)
        )
        let expectedFinishReason = LKAIFinishReason.completed
        var text = ""
        var finishReason: LKAIFinishReason?

        // When
        for try await event in client.stream(request) {
            switch event {
            case .textDelta(let delta):
                text += delta

            case .finished(let completion):
                finishReason = completion.finishReason
            }
        }

        // Then
        #expect(finishReason == expectedFinishReason)
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 驗證非串流呼叫真實 API 時，結果以完成結束，而且文字去掉空白後不為空
    @Test(.enabled(if: LKOpenAIClientLiveTests.isAPIKeyConfigured), .timeLimit(.minutes(2)))
    func invoke_要求只回一個詞_結果以完成結束且文字不為空() async throws {
        // Given
        let apiKey = try #require(ProcessInfo.processInfo.environment[Self.apiKeyEnvironmentName])
        let client = LKOpenAIClient(
            apiKey: apiKey,
            urlSession: URLSession(configuration: .ephemeral)
        )
        let expectedFinishReason = LKAIFinishReason.completed

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.completion.finishReason == expectedFinishReason)
        #expect(!response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// MARK: - Private Method

private extension LKOpenAIClientLiveTests {

    /// 環境變數是否有設定 API 金鑰，沒有設定時整個測試略過
    static var isAPIKeyConfigured: Bool {
        ProcessInfo.processInfo.environment[apiKeyEnvironmentName] != nil
    }
}
