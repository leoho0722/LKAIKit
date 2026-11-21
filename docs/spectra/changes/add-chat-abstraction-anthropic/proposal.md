## Why

LKAIKit 目前只有 package 骨架，App 還無法透過它呼叫任何 AI 供應商。BuyLedger 的 AI 摘要因此自己手寫 Ollama 的 HTTP 請求、串流解析與錯誤分類。之後要陸續接入 OpenAI GPT、Anthropic Claude、Google Gemini，若沒有先定好三家都能套用的共用介面，每加一家就要改動 `LKAICore` 的公開型別，App 也得為每家寫不同的呼叫方式。這次建立共用對話介面，並以 Anthropic 實作驗證它真的能用。

## What Changes

- `LKAICore` 新增公開的共用對話介面：
  - `LKAIChatClientProtocol` 提供兩個呼叫方法：串流的 `stream(_:)` 用於邊產生邊顯示，非串流的 `invoke(_:)` 用於需要完整結果才能使用的情境。
  - 共用資料型別：`LKAIChatRequest`、`LKAIMessage`、`LKAIMessageRole`、`LKAIChatStream`、`LKAIChatStreamEvent`、`LKAIChatCompletion`、`LKAIChatResponse`、`LKAIFinishReason`、`LKAIUsage`、`LKAIError`。
  - 非串流的 `invoke(_:)` 有由串流彙整而成的公開預設實作，供應商與 App 的測試替身只需實作串流。
  - 型別依 OpenAI、Anthropic、Gemini 三家 API 的實際格式設計；token 用量以統一的計算口徑提供。
  - `LKAIError`、`LKAIFinishReason`、`LKAIChatStreamEvent` 標為 `@nonexhaustive`，之後新增 case 不會讓 App 編譯失敗；App 的 `switch` 要寫 `@unknown default`。
  - `LKAIError` 實作 `LocalizedError`，以英文與正體中文提供可直接顯示給使用者的錯誤說明，App 的語言不是這兩種時用英文。
- `LKAICore` 新增只給 package 內使用（`package` 存取層級）的共用基礎：可注入的 HTTP client、以 `URLSession` 實作的版本、位元組切行、SSE（server-sent events）解析，以及依 HTTP 狀態碼的預設錯誤分類。
- 新增 `LKAIAnthropic` target 與 `LKAnthropicClient`：呼叫 Anthropic Messages API（`anthropic-version: 2026-10-21`），支援串流與非串流，並提供預設關閉、由 App 在建立 client 時選擇開啟的伺服器端拒答備援；`LKAIKit` 總成依賴並重新匯出它。
- 新增不屬於任何 product 的 `LKAITestSupport` target，提供測試用的 HTTP client 替身。
- 新增測試 target `LKAIAnthropicTests`；`LKAICoreTests` 與 `LKAIKitTests` 補上對應測試。
- `docs/spectra/config.yaml` 的命名規則補上一條：外部型別遵循本 package 的 `public` protocol，只能寫在 `LKAICore`。
- 回答 `add-swift-package-foundation` 的 design 留下的三個開放問題：跨供應商組裝邏輯、共用 HTTP 與測試替身的位置、外部型別遵循本 package protocol 的規則。

## Capabilities

### New Capabilities

- `chat-client`：與供應商無關的對話呼叫契約，包含請求內容與驗證、串流與非串流兩種呼叫、結束原因、實際回應的模型、token 用量口徑、拒答、取消、錯誤分類、可重試性與本地化錯誤說明，以及供 App 撰寫測試替身的串流建構方式
- `anthropic-provider`：`LKAnthropicClient` 對 Anthropic Messages API 的請求格式、預設關閉的拒答備援、串流事件對應、結束原因、用量與回應模型的對應、錯誤對應、API 金鑰不外洩，以及透過 `import LKAIKit` 取用

### Modified Capabilities

- `package-distribution`：新增「測試支援 target 不得進入 library 的建置範圍」需求，`LKAIKit` 與它可達的 target 都不得依賴 `LKAITestSupport`，`LKAITestSupport` 也不屬於任何 product

## Impact

- 新增來源：`Sources/LKAICore/Chat/`（共用對話型別與 protocol）、`Sources/LKAICore/Resources/Localizable.xcstrings`（錯誤說明的英文與正體中文字串）、`Sources/LKAICore/Networking/`（HTTP client 與 SSE 解析）、`Sources/LKAIAnthropic/`、`Sources/LKAITestSupport/`
- 新增測試：`Tests/LKAIAnthropicTests/`，以及 `Tests/LKAICoreTests/` 下的新測試檔
- 修改：`Package.swift`、`Sources/LKAIKit/Exports.swift`、`Tests/LKAIKitTests/ExportsTests.swift`、`docs/spectra/config.yaml`、`.gitignore`（新增 `.worktrees/`，供平行實作的 git worktree 使用）
- 依賴：不新增外部套件，只使用 Foundation 與 Swift 工具鏈內建的 Synchronization 模組
- 資源：`LKAICore` 開始帶有字串資源，`Package.swift` 宣告 `defaultLocalization: "en"`
- 公開 API：新增上述共用型別與 `LKAnthropicClient`；既有公開 API 不變
- 使用端：App 需要自備 Anthropic API 金鑰與 `URLSession` 傳給 `LKAnthropicClient`；BuyLedger 目前沒有依賴 LKAIKit，不受影響
