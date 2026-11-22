## Why

Anthropic 與 OpenAI 已經實作，下一家 Gemini 的格式也在 2026-11-22 以官方文件與實際請求查證過，三家的證據都齊了。前兩個供應商的 change 留下四個要改 chat-client 共同規則的項目，依 `config.yaml`，供應商的 change 不能順手修改。所以在實作 Gemini 之前先修改這份規則，讓 Gemini 只需照最終的規則寫一次，而且在第一個 release tag 之前修改公開 API，成本最低。

## What Changes

- **BREAKING** `LKAIError.serviceUnavailable(statusCode:)` 改成 `serviceUnavailable(statusCode:retryAfter:)`，和 `rateLimited(retryAfter:)` 同一種寫法，`retryAfter` 不給預設值。
  - 預設的狀態碼分類在 5xx 也讀 `retry-after` 標頭，規則和 429 相同，只接受純 ASCII 數字的秒數。
  - Anthropic 以 HTTP 回報的 `api_error`、`overloaded_error`、`timeout_error` 一併帶上等待時間；OpenAI 的 503 經由預設分類帶上等待時間。
  - 串流中途的錯誤沒有標頭，等待時間一律為 nil。
  - 建立這個 case 的程式碼都要補上 `retryAfter:`；package 內有 35 處。
  - App 以 `case .serviceUnavailable(statusCode: let code)` 取狀態碼時，`code` 會變成整個 tuple，沒有警告（Swift 6.4.2 實測）。
  - 目前沒有 App 使用 LKAIKit。
- **不認得的串流錯誤改成三家共用的規則**：
  - 有錯誤代碼但供應商不認得時，回報不可重試的 `invalidResponse`，說明帶代碼與訊息。
  - 完全沒有代碼時，回報可重試的 `serviceUnavailable`，狀態碼 500。
  - 規則集中在 `LKAICore` 的 `package` 函式 `LKAIError.unrecognizedStreamError(code:message:)`，兩家供應商都改用它。
  - 哪個欄位算錯誤代碼、錯誤資料缺到什麼程度算無法解碼，由各供應商的 spec 寫明。
  - 只管串流中的錯誤；HTTP 錯誤有狀態碼可以判斷，仍交給預設的狀態碼分類。
  - Anthropic 的行為因此改變：不認得的 `error.type` 原本是可重試的 500，改成 `invalidResponse`；沒有 `error.type` 的 `error` 事件原本是無法解碼，改成 500。
- **「Context window limit」需求加上條件**：只有把「context window 塞滿」和「達到輸出上限」分開回報的供應商，才回報 `.contextWindowExceeded`；分不開的供應商回報 `.maxOutputTokens`。`LKAIFinishReason` 的說明一併改寫，只改文字。
- **`refused(detail:)` 的公開說明補上隱私提醒**：detail 可能是模型寫的文字，會引用使用者的內容，記錄 log 時要留意。只改文字。
- **新增供應商的清單**：新增 `docs/adding-a-provider.md`，取代 `config.yaml` 裡一層層「以某份 design 為準」的指標。
  - 內容包括三家供應商的對照表（Gemini 一欄用 2026-11-22 的查證）、新增供應商要遵守的規則、封存 design 中已被改寫的段落、留給下一家供應商的事，以及三份封存 design 的 Open Questions 的對帳。
  - 系統的行為仍以 spec 為準，清單是流程、跨供應商的事實與索引。
  - `config.yaml` 的 API 演進規則改成只指向這份清單。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `chat-client`: 服務不可用的錯誤帶上可選的等待時間，5xx 的預設分類讀 `retry-after`；新增不認得的串流錯誤的共同規則；「Context window limit」只適用於把兩種原因分開回報的供應商。
- `anthropic-provider`: HTTP 的服務不可用錯誤帶上 `retry-after` 的等待時間；串流中不認得的 `error.type` 與沒有 `error.type` 的 `error` 事件改依 chat-client 的共同規則，並寫明沒有 `error` 物件的資料算無法解碼。
- `openai-provider`: HTTP 503 經預設分類帶上 `retry-after` 的等待時間；串流中不認得的代碼依 chat-client 的共同規則，並寫明 `error` 事件的資料在什麼情況下算可解碼：`code` 與 `message` 出現時必須是字串或 null。

## Impact

- Affected specs: `chat-client`、`anthropic-provider`、`openai-provider`（修改）
- Affected code:
  - New:
    - `docs/adding-a-provider.md`
  - Modified:
    - `Sources/LKAICore/Chat/LKAIError.swift`
    - `Sources/LKAICore/Chat/LKAIFinishReason.swift`（只改說明文字）
    - `Sources/LKAIAnthropic/LKAnthropicErrorBody.swift`
    - `Sources/LKAIAnthropic/LKAnthropicStreamState.swift`
    - `Sources/LKAIAnthropic/LKAnthropicClient.swift`（只改說明文字）
    - `Sources/LKAIOpenAI/LKOpenAIErrorBody.swift`
    - `Sources/LKAIOpenAI/LKOpenAIStreamState.swift`
    - `Sources/LKAIOpenAI/LKOpenAIClient.swift`（只改說明文字）
    - `Tests/LKAICoreTests/Chat/LKAIErrorTests.swift`
    - `Tests/LKAICoreTests/Chat/LKAIChatClientProtocolTests.swift`（只補 `retryAfter: nil`）
    - `Tests/LKAICoreTests/Chat/LKAIChatStreamTests.swift`（只補 `retryAfter: nil`）
    - `Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift`
    - `Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift`（只加 spec 標記）
    - `docs/spectra/config.yaml`（API 演進規則的指標）
  - Removed: (none)
- Dependencies: 不新增外部套件，target 之間的依賴不變。
- APIs: `LKAIError.serviceUnavailable` 的 associated value 改變（BREAKING）；新增的 `unrecognizedStreamError(code:message:)` 是 `package` 層級，App 看不到。
