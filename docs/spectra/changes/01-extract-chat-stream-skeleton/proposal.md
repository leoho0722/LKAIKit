## Why

第二家供應商 OpenAI 要開始實作（`02-add-openai-provider`）。但目前下列流程整段寫在 `LKAnthropicClient` 裡：建立串流的背景 task、檢查狀態碼、逐行解析 SSE、收到結束事件就停止讀取、轉換取消。

- 照抄到 OpenAI 時可能漏掉取消接線，App 釋放串流後請求仍繼續計費。
- 之後修一個取消或提前結束的問題，也要每一家都改。

`add-chat-abstraction-anthropic` 封存後的 design 在 Open Questions 建議，第二家供應商開始前先把這段共同流程抽進 `LKAICore`，並列出四項一併處理的事項。現在正是那個時機。

## What Changes

- **背景 task 只建立一次**：`LKAIChatStream` 新增 `package init(producing:)`，每條串流的背景 task 只在這裡建立，只由 `onTermination` 取消，不存進任何屬性。生產端只拿得到交出事件的 closure，碰不到取消接線。
- **共同流程搬進 `LKAICore`**：新增以 SSE 串流回答的共同流程，包括 `package` protocol `LKAIServerSentEventChatStreaming`，以及每條串流一份的事件對應 protocol `LKAIServerSentEventMapping`。
  - protocol 的 extension 依序檢查請求、送出、讀取非 2xx 的錯誤內容並分類、逐行解析 SSE，交出結束事件後就停止讀取。
  - 供應商只需要分類錯誤內容，讀取內容與預設分類由共同流程處理。
- **取消判斷收成一處**：`LKAIError.streamFailure(for:)` 改成也接收「task 是否已取消」，`LKAIChatStream` 與 `LKAIHTTPLines` 改為傳入 `Task.isCancelled`。
- **snake_case 解碼收成一處**：`LKAICore` 新增 `LKAISnakeCaseJSON`，`LKAnthropicStreamEvent` 與 `LKAnthropicErrorBody` 改用它。
- **Anthropic 改用共同流程**：
  - `LKAnthropicClient` 改為遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只轉呼叫共同流程。
  - `LKAnthropicStreamState` 改為遵循 `LKAIServerSentEventMapping`，`error` 事件與 `message_stop` 也在它裡面處理。
- **共用的測試 helper 搬進 `LKAITestSupport`**：與供應商無關的 helper 從 `LKAnthropicClientTestSupport` 與 `LKAnthropicClientCancellationTests` 搬過去，包括呼叫方式、收集串流結果、取得呼叫丟出的錯誤、取得第一個事件、等待條件成立。
- **替身擋下第二次請求**：`LKAIMockHTTPClient` 收到第二次以上的 `fetch` 時，另以 Swift Testing 記錄測試失敗。否則「供應商誤送兩次請求」會被只比對錯誤種類的測試當成通過。新增測試 target `LKAITestSupportTests` 驗證這個行為（使用者決定）。
- **補兩個回歸測試**：補上目前沒有測試的兩個既有行為：串流途中連線中斷，以及讀取錯誤內容時連線中斷。
- **直接測試共同流程自己的行為**：在 `LKAICoreTests` 直接測試 `init(producing:)`，以及同一個陣列交出多個事件時在 `.finished` 停止。這兩處 Anthropic 的測試走不到；實作審查後由使用者決定補上。
- **更新 `config.yaml`**：`docs/spectra/config.yaml` 的 API 演進規則指向本 change 的 design，並寫明以 SSE 串流的供應商一律走共同流程。

範圍外的項目與否決的做法記在 design 的 Goals / Non-Goals 與各決策。

## Impact

- Affected specs: none
- Affected code:
  - New:
    - `Sources/LKAICore/Chat/LKAIServerSentEventChatStreaming.swift`
    - `Sources/LKAICore/Chat/LKAIServerSentEventMapping.swift`
    - `Sources/LKAICore/Networking/LKAISnakeCaseJSON.swift`
    - `Sources/LKAITestSupport/LKAIChatClientProtocolTestSupport.swift`
    - `Sources/LKAITestSupport/LKAITestWaiting.swift`
    - `Tests/LKAITestSupportTests/LKAIMockHTTPClientTests.swift`
    - `Tests/LKAICoreTests/Chat/LKAIServerSentEventChatStreamingTests.swift`
  - Modified:
    - `Package.swift`（新增 `LKAITestSupportTests` 測試 target）
    - `docs/spectra/config.yaml`（API 演進規則的指標）
    - `Sources/LKAICore/Chat/LKAIChatClientProtocol.swift`（`stream(_:)` 的說明）
    - `Sources/LKAICore/Chat/LKAIChatStream.swift`
    - `Sources/LKAICore/Chat/LKAIError.swift`
    - `Sources/LKAICore/Networking/LKAIHTTPLines.swift`
    - `Sources/LKAIAnthropic/LKAnthropicClient.swift`
    - `Sources/LKAIAnthropic/LKAnthropicStreamState.swift`
    - `Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift`
    - `Sources/LKAIAnthropic/LKAnthropicErrorBody.swift`
    - `Sources/LKAITestSupport/LKAIMockHTTPClient.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift`
    - `Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift`
    - `Tests/LKAICoreTests/Chat/LKAIChatStreamTests.swift`
  - Removed: (none)
- Dependencies: `LKAITestSupport` 開始 `import Testing`。Swift Testing 隨工具鏈提供，`Package.swift` 不需要為它新增依賴。
- Compatibility: no capability-level observable behavior changes。唯一的文字差異：串流沒有結束事件就結束時，`.invalidResponse` 的開發者說明文字由「Stream ended before message_stop」改為不分供應商的說明；錯誤種類不變。
