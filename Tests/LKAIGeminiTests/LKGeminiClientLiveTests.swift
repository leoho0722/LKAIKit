//
//  LKGeminiClientLiveTests.swift
//  LKAIGeminiTests
//
//  Created by Leo Ho on 2026/11/22.
//

import Foundation
import LKAICore
import Testing

@testable import LKAIGemini

/// `LKGeminiClient` 對真實 Gemini API 的測試，確認串流與非串流都能得到完成的回答與實際回應的模型
///
/// - Note: 只在設定環境變數 `LKAI_GEMINI_API_KEY` 時執行，沒有設定時顯示為略過
/// - Note: 會連線到真實的 API 並產生少量費用，由 owner 以自己的金鑰手動執行
/// - Note: 金鑰只從環境變數讀取，不寫進程式碼，也不放進任何輸出或斷言訊息
/// - Note: 以預設設定建立 client，不讓 Gemini 保存這次的回應
/// - Note: 只確認回應的模型不是 nil 也不是空字串，不比對模型名稱，因為請求的模型可能被換成別的模型
struct LKGeminiClientLiveTests {

    // MARK: - Properties

    /// 儲存 API 金鑰的環境變數名稱，給 trait 與測試本體共用
    private static let apiKeyEnvironmentName = "LKAI_GEMINI_API_KEY"

    /// 兩個測試共用的請求：要求模型只回一個詞，輸出上限 64 個 token
    private let request = LKAIChatRequest(
        model: "gemini-3.5-flash-lite",
        messages: [LKAIMessage(role: .user, text: "Reply with the single word OK.")],
        maxOutputTokens: 64
    )

    /// 驗證串流呼叫真實 API 時，以完成結束，串接出的文字去掉空白後不為空，而且回報了實際回應的模型
    @Test(.enabled(if: LKGeminiClientLiveTests.isAPIKeyConfigured), .timeLimit(.minutes(2)))
    func stream_要求只回一個詞_以完成結束且文字與回應模型不為空() async throws {
        // Given
        let apiKey = try #require(ProcessInfo.processInfo.environment[Self.apiKeyEnvironmentName])
        let client = LKGeminiClient(
            apiKey: apiKey,
            urlSession: URLSession(configuration: .ephemeral)
        )
        let expectedFinishReason = LKAIFinishReason.completed
        var text = ""
        var finishReason: LKAIFinishReason?
        var respondingModel: String?

        // When
        for try await event in client.stream(request) {
            switch event {
            case .textDelta(let delta):
                text += delta

            case .finished(let completion):
                finishReason = completion.finishReason
                respondingModel = completion.respondingModel
            }
        }

        // Then
        #expect(finishReason == expectedFinishReason)
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let model = try #require(respondingModel)
        #expect(!model.isEmpty)
    }

    /// 驗證非串流呼叫真實 API 時，結果以完成結束，文字去掉空白後不為空，而且回報了實際回應的模型
    @Test(.enabled(if: LKGeminiClientLiveTests.isAPIKeyConfigured), .timeLimit(.minutes(2)))
    func invoke_要求只回一個詞_結果以完成結束且文字與回應模型不為空() async throws {
        // Given
        let apiKey = try #require(ProcessInfo.processInfo.environment[Self.apiKeyEnvironmentName])
        let client = LKGeminiClient(
            apiKey: apiKey,
            urlSession: URLSession(configuration: .ephemeral)
        )
        let expectedFinishReason = LKAIFinishReason.completed

        // When
        let response = try await client.invoke(request)

        // Then
        #expect(response.completion.finishReason == expectedFinishReason)
        #expect(!response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let model = try #require(response.completion.respondingModel)
        #expect(!model.isEmpty)
    }
}

// MARK: - Private Method

private extension LKGeminiClientLiveTests {

    /// 環境變數是否有設定 API 金鑰，沒有設定時整個測試略過
    static var isAPIKeyConfigured: Bool {
        ProcessInfo.processInfo.environment[apiKeyEnvironmentName] != nil
    }
}
