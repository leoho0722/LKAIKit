## Why

LKAIKit 目前支援 Anthropic 與 OpenAI。`config.yaml` 的專案定位列了 Google Gemini，而 `03-revise-chat-client-contract` 已先修改共同規則，並在 `docs/adding-a-provider.md` 第 6 章列出 Gemini 已定好的事。現在加上第三家供應商，同時處理前兩家留下的重複：金鑰遮蔽各寫一次、與供應商無關的測試 helper 各一份。

## What Changes

- **`LKAICore`**：
  - 新增 `package` 的金鑰包裝型別。它的 `description`、`debugDescription` 與 `customMirror` 只給出遮蔽後的內容；三家 client 以它保存金鑰，只在組請求時讀原始值。三家 client 原本的三個遵循保留，公開的建立方式不變。
  - `LKAIFinishReason` 的 `.maxOutputTokens` 只改說明，例子加上 Gemini：它在生成途中塞滿 context window 時也以 `.maxOutputTokens` 回報。`.contextWindowExceeded` 的說明「目前只有 Anthropic」不變，型別與 case 都不變。
- **`LKAITestSupport`**：與供應商無關的測試 helper 從 Anthropic 與 OpenAI 的測試搬進來，兩家的測試改用它們，測試名稱、期望值與測試數不變：
  - JSON 比對用的 `jsonObject(from:)`、`jsonFragment(from:)`，收進 `LKAITestJSON`。
  - 組事件 JSON 用的 `optionalField(_:_:)`，同樣收進 `LKAITestJSON`。
  - 確認請求內容的 JSON 布林：兩家各一份的 `decodeBooleanFlags(of:)` 與 `decodeStreamFlag(of:)`，改成 `LKAITestJSON` 的同一個方法。
  - 錯誤的期望值（`.error` 與 `.invalidResponse(containing:)`）與比對；OpenAI 串流測試的 `ErrorExpectation` 與 `isInvalidResponse(_:)` 併進同一個型別。
- **新增 `LKAIGemini`**（只依賴 `LKAICore`）：
  - `LKGeminiClient` 以 Gemini Interactions API 的 `v1` 實作 `LKAIChatClientProtocol`，串流與非串流都以 `stream: true` 送出，遵循 `LKAIServerSentEventChatStreaming`。
  - 回應保存預設關閉，送 `store: false`；App 建立 client 時可以開啟。
  - 文字只取 `model_output` 步驟的文字片段；`interaction.completed` 的 `completed` 回報完成，`incomplete` 回報 `.maxOutputTokens`。
  - 用量依 `LKAIUsage` 的口徑換算：輸出包含思考的 token。
  - 錯誤處理 Interactions 與 Google 通用兩種格式：生成被擋下的代碼回報 `.refused`；Google 通用格式中 `ErrorInfo.reason` 為 `API_KEY_INVALID` 時回報金鑰無效；串流中對應不到的錯誤依 chat-client 的共同規則。
  - 實際 API 測試以 `gemini-3.5-flash-lite` 執行，只在設定 `LKAI_GEMINI_API_KEY` 時執行。
- **`LKAIKit`**：依賴並重新匯出 `LKAIGemini`。
- **`docs/adding-a-provider.md`**：Gemini 一欄改成本 change 的查證結果，第 6 章的內容移進第 3、4、7 章後清空，第 7 章對帳本 change 的 Open Questions。

## Non-Goals (optional)

見 design.md 的 Goals / Non-Goals。

## Capabilities

### New Capabilities

- `gemini-provider`: `LKGeminiClient` 如何以 Gemini Interactions API `v1` 履行 chat-client 的約定：送出的 HTTP 請求、回應保存設定、串流事件、結束原因、用量與錯誤的對應，以及金鑰不出現在診斷輸出。

### Modified Capabilities

(none)

## Impact

- 新增的程式碼：`Sources/LKAIGemini/`、`Tests/LKAIGeminiTests/`、`Sources/LKAICore/` 中金鑰包裝型別的檔案與它在 `Tests/LKAICoreTests/` 的測試、`Sources/LKAITestSupport/` 中搬進來的 helper 與它們在 `Tests/LKAITestSupportTests/` 的測試。
- 修改的程式碼：
  - `Package.swift`：新增 `LKAIGemini` 與 `LKAIGeminiTests`，`LKAIKit` 加上依賴。
  - `Sources/LKAIKit/Exports.swift` 與 `Tests/LKAIKitTests/ExportsTests.swift`。
  - `Sources/LKAIAnthropic/LKAnthropicClient.swift`、`Sources/LKAIOpenAI/LKOpenAIClient.swift`：改用金鑰包裝型別。
  - `Sources/LKAICore/Chat/LKAIFinishReason.swift`：只改說明。
  - `Tests/LKAIAnthropicTests/` 與 `Tests/LKAIOpenAITests/` 中定義或使用搬走的 helper 的測試檔。
- 文件：`docs/adding-a-provider.md`。
- 公開 API：新增 `LKGeminiClient`；既有的公開型別與建立方式不變。
- 外部依賴：沒有新增。
