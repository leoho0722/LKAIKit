## Why

LKAIKit 要整合多家 AI 供應商，目前只有 Anthropic。第二家是 OpenAI：前一個 change `01-extract-chat-stream-skeleton` 已經把以 SSE 串流的共同流程抽進 `LKAICore`，新增供應商只需提供請求、錯誤分類與事件對應。App 因此可以用同一組型別呼叫 OpenAI 的模型，換供應商時不必改呼叫端。

## What Changes

- **新增 `LKAIOpenAI` 模組與 `LKOpenAIClient`**：以 OpenAI Responses API（`POST https://api.openai.com/v1/responses`）實作 `LKAIChatClientProtocol`，串流與非串流都可以用。
  - 遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只轉呼叫共同流程，不自行建立 `Task`。
  - App 以 API 金鑰與 `URLSession` 建立；金鑰不會出現在 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡。
- **回應保存由 App 選擇**：OpenAI 的 `store` 預設會保存回應至少 30 天。`LKOpenAIClient` 預設送 `store: false`，App 在建立 client 時可以改成保存（使用者決定）。
- **事件與結果的對應**：
  - 文字片段來自 `response.output_text.delta`。
  - 結束原因、實際回應的模型、token 用量來自 `response.completed` 與 `response.incomplete`。
  - 拒答文字與 `content_filter` 回報為拒答錯誤。
- **錯誤的對應**：
  - HTTP 錯誤依 `error.code` 與 `error.type` 區分額度用完與頻率限制，其餘 4xx 帶上 OpenAI 的錯誤訊息。
  - 串流中的 `error` 事件與 `response.failed` 依 `code` 分類。
  - 都對應到既有的 `LKAIError`，不新增錯誤種類。
- **`LKAIKit` 總成**：依賴並重新匯出 `LKAIOpenAI`，App 只要 `import LKAIKit`。
- **測試**：
  - 新增 `LKAIOpenAITests`。
  - SSE 分框的測試 helper 從 Anthropic 的測試支援搬進 `LKAITestSupport`，兩家共用。這是前一個 change 的 Open Questions 留下的項目。
  - 實際 API 測試以 `gpt-6-luna` 執行，只在設定環境變數 `LKAI_OPENAI_API_KEY` 時執行（使用者決定）。

## Capabilities

### New Capabilities

- `openai-provider`: `LKOpenAIClient` 如何以 OpenAI Responses API 履行 chat-client 的契約，包括送出的請求、回應保存設定、串流事件、結束原因、token 用量與錯誤的對應，以及 API 金鑰的保密。

### Modified Capabilities

(none)

## Impact

- Affected specs: `openai-provider`（新增）
- Affected code:
  - New:
    - `Sources/LKAIOpenAI/LKOpenAIClient.swift`
    - `Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift`
    - `Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift`
    - `Sources/LKAIOpenAI/LKOpenAIStreamState.swift`
    - `Sources/LKAIOpenAI/LKOpenAIErrorBody.swift`
    - `Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift`
    - `Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift`
    - `Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientTests.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift`
    - `Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift`
  - Modified:
    - `Package.swift`（新增 `LKAIOpenAI` 與 `LKAIOpenAITests`，`LKAIKit` 依賴 `LKAIOpenAI`）
    - `Sources/LKAIKit/Exports.swift`
    - `Sources/LKAICore/Chat/LKAIFinishReason.swift`（只改說明文字：OpenAI 以 `.maxOutputTokens` 回報 context window 塞滿）
    - `docs/spectra/config.yaml`（API 演進規則的指標）
    - `Tests/LKAIKitTests/ExportsTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift`
  - Removed: (none)
- Dependencies: 不新增外部套件。`LKAIOpenAI` 只依賴 `LKAICore`，符合 `package-distribution` 的依賴方向。
- APIs: 新增公開型別 `LKOpenAIClient`；`LKAICore` 的共用公開型別不變。
