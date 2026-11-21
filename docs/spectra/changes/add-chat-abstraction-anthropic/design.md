## Context

`add-swift-package-foundation` 建好了 package 骨架：`LKAICore`、`LKAIKit` 總成與 `LKAIKitCLI`。依賴方向固定為供應商 target 只依賴 `LKAICore`，總成重新匯出所有 library target。那個 change 把「各供應商共用的抽象」與「任何供應商的實作」列為 Non-Goals，並在 design 留下三個開放問題：跨供應商組裝邏輯放在哪裡、共用 HTTP 與 SSE 與測試替身放在哪裡、外部型別遵循本 package 的 `public` protocol 算不算違反命名規則。本 change 接手這些項目。

第一個使用端是 BuyLedger 的 AI 摘要（`Features/AISummary/Data/AISummaryService.swift`，2026-11-21 讀取）：

- 只使用 Ollama Cloud（`https://ollama.com/api/chat`）。
- 送出一則 user 訊息，以串流逐段取得文字。
- API 金鑰由 App 保管，模型名稱由呼叫端傳入。
- 錯誤分為 `invalidKey`、`transport`、`http(statusCode:)`、`decoding`、`apiError`、`quotaExceeded` 六類。
- 取消視為正常結束，30 秒的整體逾時由 App 自己控制。

使用者決定：本 change 同時做共用抽象與 Anthropic 實作；共用型別必須同時考慮 OpenAI GPT 與 Google Gemini；串流與非串流各提供一個呼叫方法；token 用量放進共用型別；`LKAIError` 提供英文與正體中文的本地化錯誤說明，預設英文；Anthropic 的拒答備援由 LKAIKit 提供，App 在建立 client 時決定是否開啟；共用結果提供實際產生回應的模型。

三家 API 的實際格式是共用型別的設計依據。來源與查證日期：Anthropic 依 Claude Code 內建的 Claude API 參考資料（快取日期 2026-11-03）；OpenAI Responses API 與 Gemini `generateContent` 依 Context7 收錄的官方文件。三者都在 2026-11-21 查證。

| 共用概念 | Anthropic Messages API | OpenAI Responses API | Gemini `generateContent` |
| --- | --- | --- | --- |
| 系統指示 | 頂層 `system` | 頂層 `instructions` | 頂層 `system_instruction` |
| 訊息角色 | `user`、`assistant` | `user`、`assistant` | `user`、`model` |
| 輸出上限 | `max_tokens`，必填 | `max_output_tokens`，選填 | `generationConfig.maxOutputTokens`，選填 |
| 取樣參數 | API 版本 `2026-10-21` 傳 `temperature`、`top_p`、`top_k` 回 400 | 選填 | 選填 |
| 串流格式 | SSE，文字在 `content_block_delta` 的 `text_delta` | SSE，文字在 `response.output_text.delta` | SSE（`streamGenerateContent`），每段的 `candidates[].content.parts[].text` |
| 思考內容 | `thinking` 區塊；Claude Opus 5.5 思考一律開啟 | reasoning 項目 | thought 片段 |
| 正常完成 | `stop_reason` 為 `end_turn` | `status` 為 `completed` | `finishReason` 為 `STOP` |
| 達到輸出上限 | `stop_reason` 為 `max_tokens` | `incomplete_details.reason` 為 `max_output_tokens` | `finishReason` 為 `MAX_TOKENS` |
| 拒答或被擋 | HTTP 200，`stop_reason` 為 `refusal`，`stop_details` 帶類別 | HTTP 200，`refusal` 內容（附模型說明）或 `incomplete_details.reason` 為 `content_filter` | HTTP 200，`finishReason` 為 `SAFETY` 等，或 `promptFeedback.blockReason` |
| 金鑰無效 | 401 `authentication_error` | 401 | 400 `INVALID_ARGUMENT`，`reason` 為 `API_KEY_INVALID` |
| 頻率限制與額度 | 429 `rate_limit_error`；月度花費上限時 `error.details.error_code` 為 `enforced_spend_limit_reached`；402 `billing_error` | 429 | 429 `RESOURCE_EXHAUSTED`；402 預付額度用完 |
| 服務過載 | 529 `overloaded_error`、500 `api_error` | 5xx | 503、500 |
| 驗證標頭 | `x-api-key` | `Authorization: Bearer` | `x-goog-api-key` |
| 實際回應的模型 | `message_start` 的 `message.model`；拒答備援切換時以 `fallback` 區塊的 `to.model` 為準 | 回應物件的 `model` | `modelVersion` |
| token 用量 | `input_tokens` 不含快取，另有 `cache_creation_input_tokens`、`cache_read_input_tokens`；`output_tokens` 含思考，另有 `output_tokens_details.thinking_tokens` | `input_tokens` 含 `cached_tokens`；`output_tokens` 含 `reasoning_tokens` | `promptTokenCount` 含 `cachedContentTokenCount`；另有 `candidatesTokenCount`、`thoughtsTokenCount` |

以下技術事實已於 2026-11-21 在規劃階段查證，相關決策以此為依據：

- **`AsyncLineSequence`（`URLSession.AsyncBytes.lines`）**：Apple 文件只寫「An asynchronous sequence of lines of text」，沒有說明空行與換行字元。以 Swift 6.4.2 實測：
  - 所有空行都被丟掉，包含 LF、CRLF、連續空行，以及開頭與結尾的空行。
  - 單獨的 `\r` 視為換行。
  - U+2028、U+2029、U+0085 也被當成換行切開。
  - 以 `URLSession.bytes(from:)` 讀取檔案 URL 再取 `lines`，結果相同。
- **自訂 `AsyncSequence` 的 typed throws**：以 `swift-tools-version: 6.2` 與 Swift 6 語言模式實測：
  - 以 `AsyncThrowingStream<Element, any Error>` 為來源，迭代器的 `next(isolation:)` 標 `throws(自訂錯誤)`，建置零警告。
  - `for try await` 的 `catch` 推斷出的錯誤就是自訂錯誤，`switch` 不必轉型。
  - 來源丟出的其他錯誤可以在迭代器內轉換；`CancellationError` 可以轉成正常結束。
  - 迭代的 task 被取消時，迴圈沒有錯誤就結束，來源的 `onTermination` 也被呼叫。
- **SwiftPM 的 String Catalog**：實測 `defaultLocalization: "en"` 加上 `resources: [.process("Resources")]` 時：
  - `.xcstrings` 被編譯進 `Bundle.module` 的 `en.lproj` 與 `zh-Hant.lproj`。
  - `developmentLocalization` 為 `en`，`localizations` 為 `en`、`zh-Hant`，兩種語言都查得到字串。
  - 查不到的 key 會原樣回傳。
- **Anthropic 串流格式**：依官方串流文件（直接讀取 `https://platform.claude.com/docs/en/build-with-claude/streaming.md`）與 Context7 收錄的 API 參考：
  - `ping` 事件為 `event: ping`、`data: {"type": "ping"}`。
  - 串流中的錯誤為 `event: error`、`data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}`，對應非串流時的 HTTP 529。
  - 文件要求程式能略過未知的事件類型。
  - `content_block_delta` 的類型有 `text_delta`、`thinking_delta`、`signature_delta`、`input_json_delta`。
  - `stop_reason` 與 `stop_details` 都在 `message_delta` 的 `delta` 內。`stop_details` 是 `{"type":"refusal","category":...,"explanation":...}` 或 null，`category` 也可能為 null。
  - `stop_reason` 的值有 `end_turn`、`max_tokens`、`stop_sequence`、`tool_use`、`pause_turn`、`refusal`、`model_context_window_exceeded`、`compaction`。
  - `message_delta` 可能有一個以上；它的 `usage` 為累計值，輸入的三個欄位可能為 null。
  - 官方的「開啟思考的串流」範例中，`message_start` 的 `message` 沒有 `usage`，所以 `message_start` 不保證帶用量。
  - `output_tokens_details.thinking_tokens` 是花在內部推理的輸出 token，一定小於等於 `output_tokens`。
- **Anthropic 錯誤格式**：依官方錯誤文件（`https://platform.claude.com/docs/en/api/errors.md`）與頻率限制文件（`https://platform.claude.com/docs/en/api/rate-limits.md`），2026-11-21 讀取：
  - 錯誤類型除了 Implementation Contract 已列的，還有 409 `conflict_error` 與 504 `timeout_error`；`timeout_error` 也可能以 500 回。
  - 文件寫明之後可能出現新的 `type` 值。
  - 串流已回 200 之後發生的錯誤以 `error` 事件送出，不走 HTTP 狀態碼。
  - 組織或工作區自己設定的花費上限：回 400 `invalid_request_error`，訊息以 `You have reached your specified API usage limits` 或 `You have reached your specified workspace API usage limits` 開頭，沒有 `error_code`。
  - 用量等級的月度花費上限：回 429 `rate_limit_error`，`error.details.error_code` 為 `enforced_spend_limit_reached`，沒有 `retry-after`。
- **Anthropic 拒答備援的限制**：依官方拒答與備援文件（`https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback.md`），2026-11-21 讀取：
  - Claude Haiku 5.5 沒有伺服器端備援：送 `fallbacks: "default"` 時拒答照常回報，送指定模型清單時回 400。
  - 指定的備援模型彼此不可重複，也不可與請求的模型相同。
  - 依使用者黏著改由備援模型回答的回合沒有 `fallback` 區塊，此時 `message_start` 的 `model` 已是備援模型。
- **串流的生命週期與取消**：以 Swift 6.4.2 實測（審查後補充）：
  - 迭代到一半以 `break` 離開迴圈時，`onTermination` 不會立即被呼叫；要等串流的值被釋放才呼叫。App 把串流存在屬性裡時，生產端與網路請求會一直進行，直到串流被釋放。
  - 建立後從未迭代就被釋放的串流，也會呼叫 `onTermination`。
  - 迭代的 task 被取消後，若生產端剛好在取消的空檔以錯誤結束來源，消費端會收到那個錯誤。2000 次重複中出現 10 次。
- **`URLSession` 的取消與 `URLProtocol`**：以 Swift 6.4.2 實測（審查後補充）：
  - task 被取消時，不論是在等 `bytes(for:)` 回傳，還是在逐位元組讀取，都丟出 `URLError(.cancelled)`（代碼 -999），`URLProtocol` 的 `stopLoading()` 也被呼叫。
  - Swift 6 語言模式下，`URLProtocol` 子類別的 `static var` 編譯失敗（nonisolated global shared mutable state）。
  - `URLProtocol.setProperty(_:forKey:in:)` 掛在請求上的值，`URLProtocol` 讀得到，所以每個測試可以把假回應掛在自己的請求上。
  - 回應沒有 `Content-Type` 時，`URLSession` 會先緩衝內容，不立即交出位元組；設定 `Content-Type: text/event-stream` 後立即交出。
- **存取層級與 enum 擴充**：以 Swift 6.4.2 實測（審查後補充）：
  - `public` protocol 的要求若只由 `package` 層級的 extension 提供預設實作，另一個模組的 `public` 型別遵循時編譯失敗（must be declared public）；改成 `public` extension 才通過。
  - `@nonexhaustive`（SE-0487，狀態為 Implemented，Swift 6.2.3）不需要任何編譯旗標，也不需要 library evolution。
    - 其他 package 的模組對它做窮舉 `switch`、沒有 `@unknown default` 時，Swift 6 語言模式下編譯錯誤，Swift 5 語言模式下是警告。
    - 同一個 package 的其他模組不受影響。
  - 依 SE-0487 原文：在非 resilient 模組加上 `@nonexhaustive` 是 API 破壞性變更，拿掉則不會破壞。
  - `Int(_:)` 解析字串時接受正負號：`Int("+5")` 為 5，`Int("-1")` 為 -1，`Int(" 30")` 為 nil。
- **SwiftPM 的建置範圍**：以 Swift 6.4.2 實測（審查後補充）：`swift test --filter X` 仍會建置所有 test target 與它們的依賴；任何一個 target 改到一半編譯失敗，所有 `swift test` 都建置失敗。
- **套件資源的語言與位置**：以 macOS 27.2 實測（審查後補充，iOS 未實測）：
  - 套件 `Bundle.module` 的字串跟隨 App 本身支援的語言：只支援英文的 App 在偏好語言為正體中文時仍顯示英文；同時支援英文與正體中文的 App 顯示正體中文。
  - SwiftPM 產生的 `Bundle.module` 存取器只在 App 的資源資料夾、framework 的資源資料夾與執行檔旁尋找 resource bundle，找不到就 `fatalError`。只複製執行檔、沒帶 resource bundle 時，第一次讀取字串就會終止程式。
- **Gemini 的回應模型**：`GenerateContentResponse` 有 `modelVersion`，官方說明為「The model version used to generate the response」（Context7 收錄的 Gemini API 參考）。
- **Anthropic 伺服器端拒答備援**：依 Claude Code 內建的 Claude API 參考資料（快取日期 2026-11-03）：
  - **開啟方式**：加上標頭 `anthropic-beta: server-side-fallback-2026-07-01`，請求內容加上 `fallbacks`，有兩種形式：
    - `"default"`：由 Anthropic 依拒答類別挑選備援模型。
    - `[{"model": ...}]`：1 到 3 個、不可重複，而且必須在原模型的 `allowed_fallback_models` 內。
  - **觸發條件**：只在政策性拒答時觸發；頻率限制、過載與伺服器錯誤照常回報，不會改用備援。
  - **串流途中切換**：在同一條串流接著跑，已收到的內容不會作廢。
    - 切換點以一般的 `content_block_start`／`content_block_stop` 送出 `fallback` 類型的區塊（`{"type": "fallback", "from": {"model": ...}, "to": {"model": ...}}`），沒有專屬的事件類型。
    - 已產生的文字會交給備援模型作為接續的上下文。
  - **一開始就由備援模型回答**：`message_start` 直接寫備援模型；同一段對話之後約 1 小時內也可能直接由備援模型回答。
  - **仍然拒答**：備援模型也拒答，或備援模型正被限流而沒有嘗試時，最後的 `stop_reason` 仍是 `refusal`。
  - **用量**：頂層 `usage` 只涵蓋最後產生回應的那一次嘗試，各次嘗試的明細在 `usage.iterations`。
  - **適用範圍**：不適用於 Message Batches、Amazon Bedrock、Vertex AI、Microsoft Foundry。

## Goals / Non-Goals

**Goals:**

- 定義一組公開的共用對話型別，三家供應商都能在不修改這組型別的前提下實作。
- 同時提供串流與非串流兩種呼叫，分別給邊產生邊顯示與需要完整結果的情境。
- 統一錯誤分類與可重試性、token 用量口徑、拒答與取消的行為，讓 App 換供應商時不必改錯誤處理；錯誤附帶可直接顯示給使用者的本地化說明。
- 以 `LKAnthropicClient` 實作並驗證共用型別，App 只需 `import LKAIKit`。
- 回答上一個 change 留下的三個開放問題，並把答案寫進規範。

**Non-Goals:**

- OpenAI、Gemini、Ollama 的實作，各自另開 change。
- 工具呼叫、圖片與檔案輸入、結構化輸出、embeddings、Message Batches。
- 跨供應商的組裝邏輯：依設定挑選供應商、失敗時改用另一家。
- 自動重試。App 依 `isRetryable` 自行決定。
- 思考深度與推理設定（Anthropic `output_config.effort`、OpenAI `reasoning.effort`、Gemini thinking 設定）。本 change 不提供設定，一律採用 API 預設值。
- Anthropic 拒答備援的以下部分不在本 change：每次呼叫各自設定、SDK 的用戶端備援 middleware、`fallback_credit_token` 退費流程，以及加總 `usage.iterations` 的逐次用量。
- 自訂 API 端點（例如 App 自建的轉送伺服器）。端點固定為 Anthropic 官方網址。
- 精確計費。共用的 token 用量只供觀察與粗估。
- `lkai` 的子指令、BuyLedger 改用 LKAIKit、版本號調整與 release tag。

## Decisions

### 共用對話介面以 LKAIChatClientProtocol 定義，供應商各自實作

`LKAICore` 宣告公開的 `LKAIChatClientProtocol: Sendable`，每家供應商在自己的 target 實作一個 `Sendable` 的 struct（本 change 為 `LKAnthropicClient`）。App 依設定建立具體 client，存成 `any LKAIChatClientProtocol`。protocol 命名依 ios-dev-kit `data/Service.swift` 樣板，把 `Service` 換成 `Client`，成為 `<Name>ClientProtocol`。依 ios-dev-kit `coding-style.md`，protocol 只在有第二個實作或需要 mock 時才定義；這裡至少有三家供應商加上測試替身，所以成立。

兩個呼叫方法命名為 `stream(_:)` 與 `invoke(_:)`，由使用者決定。參數不加標籤，呼叫端寫成 `client.stream(request)` 與 `client.invoke(request)`。

考慮過的替代方案：

- 每家各自提供 API、不定義共用 protocol：App 換供應商就要改呼叫端，否決。
- 方法命名為仿照 `URLSession` 的 `responseStream(for:)` 與 `response(for:)`：使用者改用 `stream` 與 `invoke`。
- 以 associated type 或泛型描述供應商差異：App 無法用一個 `any` 值切換供應商，否決。

### 共用型別依三家 API 的實際格式設計

依 Context 的對照表：

- 系統指示是請求上的獨立欄位 `systemPrompt`，不是一則 system 訊息，因為三家都是頂層欄位。
- 訊息角色只有 `user` 與 `assistant`，Gemini 的 `model` 由它的 client 轉換。
- `maxOutputTokens` 為必填，因為 Anthropic 必填、另外兩家都有對應欄位；不在函式庫內藏預設值。
- 不放取樣參數，因為 Anthropic 新版 API 會拒絕它們。
- 內容只有文字。

驗收方式：每接一家供應商，該 change 的 design 必須逐列核對本表；之後的供應商 change 不得為了自己的格式修改這組公開型別，除非另開 change 修改 `chat-client` spec。

考慮過的替代方案：只依 Anthropic 設計，等接第二家再調整。調整時會改動公開型別、影響所有 App，否決。

### 同時提供串流與非串流呼叫，非串流預設由串流彙整

`stream(_:)` 回傳 `LKAIChatStream`；`invoke(_:)` 回傳 `LKAIChatResponse`。

`LKAICore` 以 `public` 的 protocol extension 提供 `invoke(_:)` 的預設實作：迭代串流、串接文字，遇到結束事件時回傳結果。各供應商只需實作串流，需要時可以覆寫非串流方法。

- **存取層級必須是 `public`**：實測 `package` 層級的預設實作無法讓另一個模組的 `public` 型別滿足 `public` protocol 的要求（見 Context），App 自己寫的測試替身也看不到它。
- **取消**：迭代中收到錯誤時，若等待呼叫的 task 已被取消，一律丟出 `.cancelled`，不丟出生產端在取消空檔送出的其他錯誤；串流沒有結束事件就結束時，task 已被取消則丟出 `.cancelled`，否則丟出 `.invalidResponse`。

理由：Claude API 參考資料建議，輸出可能較長或 `max_tokens` 較大時一律用串流，以免 HTTP 請求逾時；官方 SDK 的完整結果也是由串流彙整（例如 `get_final_message()`）。Claude Opus 5.5 思考一律開啟，第一段文字出來前可能要等一段時間，真正的非串流請求更容易逾時。彙整邏輯只寫在 `LKAICore` 一處，各供應商不必重複。

考慮過的替代方案：非串流改送 `stream: false` 的請求。每家要多寫一套回應解析，且較易逾時，否決；之後確實需要（例如接 Message Batches）時，由該供應商覆寫預設實作。

### 以自訂 AsyncSequence 提供 typed throws 的串流

`LKAIChatStream` 是自訂的 `AsyncSequence`，`Element` 為 `LKAIChatStreamEvent`、`Failure` 為 `LKAIError`，迭代器的 `next(isolation:)` 標 `throws(LKAIError)`。內部以 `AsyncThrowingStream<LKAIChatStreamEvent, any Error>` 為來源，並在這一處統一轉換錯誤：

- 迭代的 task 已被取消時，不論來源丟出什麼錯誤，串流都正常結束。實測取消後仍可能收到生產端在空檔送出的錯誤，見 Context。
- 來源丟出 `CancellationError` 或 `LKAIError.cancelled` 時串流正常結束。
- 來源丟出其他 `LKAIError` 時原樣交出。
- 其他錯誤轉成 `.invalidResponse`。

`LKAIChatStream` 提供公開的 `init(_ source:)`，App 可以用它為 `LKAIChatClientProtocol` 寫自己的測試替身。

**生產端 task 的擁有權**：

- 供應商的 `stream(_:)` 建立 `AsyncThrowingStream`，在它的建構 closure 內建立一個 `Task` 執行請求與事件對應。這個 task 不存進任何屬性，只由 `continuation.onTermination` 取消。
- 請求在呼叫 `stream(_:)` 時就送出。App 釋放串流時，不論是否迭代過，`onTermination` 都會取消 task 與底層請求（實測，見 Context）。
- 只以 `break` 離開迴圈、但仍持有串流時，請求會繼續進行並計費，直到串流被釋放。這一點寫在 `LKAIChatClientProtocol.stream(_:)` 與 `LKAIChatStream` 的 `///` 說明。
- 偏離 ios-dev-kit `coding-style.md`「`Task { }` 只在兩個地方建立」：函式庫沒有 View 或 ViewModel，把非同步的生產端接到 `AsyncSequence` 只能建立非結構化 task。改以「每條串流一個 task、只由 `onTermination` 取消、不存進屬性」限制它的生命週期。

理由：ios-dev-kit 鐵則 7 要求 Client 一律用 typed throws；`AsyncThrowingStream` 的初始化器只接受 `any Error`，無法直接表達具體的錯誤型別。這個做法已在規劃階段實測可行，見 Context。

考慮過的替代方案：直接回傳 `AsyncThrowingStream<LKAIChatStreamEvent, any Error>`。這違反鐵則 7，App 的 `catch` 也拿不到具體型別，否決。

### 錯誤以 LKAIError 統一分類並標示可否重試

`LKAIError` 的 case：

- `invalidAPIKey`、`permissionDenied`
- `rateLimited(retryAfter: Duration?)`、`quotaExceeded`
- `serviceUnavailable(statusCode: Int)`
- `invalidRequest(message: String?)`
- `refused(detail: String?)`
- `cancelled`
- `transport(underlying: URLError)`
- `invalidResponse(reason: String)`

`isRetryable` 只在 `rateLimited`、`serviceUnavailable`、`transport` 時為 `true`。

- `transport` 依 ios-dev-kit `coding-style.md`「包裝底層錯誤時用 `underlying` label」命名。
- `LKAIError` 遵循 `Equatable`，偏離同一份規範的「避免 `Equatable` 遵循」。該規則的理由是 `underlying: any Error` 無法自動合成，這裡包的是具體且遵循 `Equatable` 的 `URLError`，理由不成立；`Equatable` 讓 App 與測試可以直接比對錯誤。
- 因取消而產生的 `URLError(.cancelled)` 不會成為 `transport`，而是 `.cancelled`，見「共用 HTTP client 與 SSE 解析放在 LKAICore，以 package 存取層級提供」。

- 頻率限制與額度用完分開：前者稍後重試可能成功，後者要等額度恢復或處理帳務。
- 拒答帶選填的原因說明：OpenAI 有模型的說明文字、Gemini 有 `finishReason`、Anthropic 有拒答類別。
- `LKAIError` 實作 `LocalizedError`，提供可直接顯示給使用者的說明，細節見決策「錯誤說明以 String Catalog 提供英文與正體中文」。使用端不只 BuyLedger，有些 App 會直接把錯誤顯示給使用者。

考慮過的替代方案：

- 直接沿用各家的錯誤型別：App 換供應商就要改錯誤處理，否決。
- 在函式庫內自動重試：BuyLedger 自己控制整體逾時，自動重試會讓總時間不可預期，否決。

### 錯誤說明以 String Catalog 提供英文與正體中文

- **讀取方式**：`LKAIError` 在獨立的 `LocalizedError` extension 實作 `errorDescription`，以 `String(localized: "error.lkai.<case 名稱>", bundle: .module)` 讀取字串。key 依 ios-dev-kit `file-templates.md` 的 `error.<領域>.<case>` 命名，領域為 `lkai`。
- **字串位置與語言**：字串放在 `Sources/LKAICore/Resources/Localizable.xcstrings`，提供 `en` 與 `zh-Hant`。`Package.swift` 宣告 `defaultLocalization: "en"`，`LKAICore` 以 `resources: [.process("Resources")]` 納入資源。App 的語言不是這兩種時，系統以英文顯示。語言與預設語言由使用者決定。
- **說明內容**：每個 case 一則通用說明。下列附帶資料都不放進說明，但仍保留在 case 中，供 App 記錄 log 或自行組成文案：
  - `invalidRequest` 的供應商訊息與 `refused` 的原因說明：多半是給開發者看的英文技術文字。
  - `transport` 的 `URLError` 文字。
  - `rateLimited` 的秒數：會牽涉單複數與數字格式。
- **驗證方式**：測試檢查每個 case 在 `en` 與 `zh-Hant` 都查得到非空字串、且不是 key 本身，並確認 `LKAICore` 資源的開發語言是 `en`。測試不逐字比對文案：文案是固定內容，逐字比對只會在改文案時失敗；程式裡的 key 與字串檔對不上才是要擋下的錯誤。
  - `LKAIError` 帶有附加值，無法自動遵循 `CaseIterable`，測試要手動列出每個 case 的一個值。
  - `errorDescription` 以不含 `default` 的窮舉 `switch` 決定 key，新增 case 時編譯器會要求補上 key；但測試的清單與字串檔不會自動跟著補，由 review 檢查。
- **已實測**：SwiftPM 會把 `.xcstrings` 編譯進 `Bundle.module` 的 `en.lproj` 與 `zh-Hant.lproj`；查不到的 key 原樣回傳，所以測試以「不等於 key」判斷字串存在（見 Context）。
- **顯示的語言**：在 macOS 實測，字串跟隨 App 本身支援的語言，只支援英文的 App 顯示英文（見 Context）；iOS 未實測。

考慮過的替代方案：

- 不實作 `LocalizedError`，由 App 自己轉成文案：不能假設每個使用端都會自己轉，使用者指出這一點，否決。
- 把供應商訊息直接當成說明：多半是英文技術文字，不適合直接顯示給使用者，否決。

### HTTP 狀態碼的預設分類放在 LKAICore，供應商依自己的錯誤格式覆寫

`LKAICore` 提供 `package` 層級的預設分類（見 `chat-client` spec 的「Default HTTP status classification」），各家先解析自己的錯誤內容，分類不了時才用預設。

理由：只看狀態碼會分錯。Gemini 的 `generateContent` 金鑰無效時回 400，錯誤內容的 `reason` 是 `API_KEY_INVALID`；Anthropic 的 429 可能是暫時的頻率限制，也可能是月度花費上限。

### token 用量以統一口徑放進共用型別

`LKAIUsage` 有四個欄位：

- `inputTokens`：一律包含讀自快取的部分。
- `outputTokens`：一律包含思考或推理的部分。
- `cachedInputTokens`、`reasoningOutputTokens`：選填，供應商沒提供時為 `nil`，而不是 0。

`usage` 本身也是選填：供應商沒回報時為 `nil`，不讓已經成功的生成變成錯誤。拒答、取消、失敗時拿不到用量。各家 client 負責換算成這個口徑，例如 Anthropic 要把三個輸入欄位相加。

範圍：共用用量只供觀察與粗估，不保證能精確計費。例如 Anthropic 寫入快取的 token 單價較高，共用欄位不區分這一點。

考慮過的替代方案：只放各家原始欄位。同一個欄位在不同供應商代表不同的意思，否決。

### 共用 HTTP client 與 SSE 解析放在 LKAICore，以 package 存取層級提供

這個決策回答上一個 change 的開放問題二的前半。

- **`LKAIHTTPClientProtocol`**（`package`）只有一個方法：送出 `URLRequest`，回傳 `LKAIHTTPResponse`。
- **`LKAIHTTPClient`**：以 App 注入的 `URLSession` 實作。逾時與連線設定由 App 透過 `URLSession` 決定。
  - task 被取消時，`URLSession` 丟出 `URLError(.cancelled)`（實測，見 Context）。收到 `URLError(.cancelled)` 時，若 task 已被取消就轉成 `.cancelled`；task 沒有被取消（例如 App 讓 `URLSession` 失效）時轉成 `.transport(underlying:)`。其他 `URLError` 一律轉成 `.transport(underlying:)`。
  - 逐行內容由 `URLSession.AsyncBytes` 餵給切行器，再以 `LKAIHTTPLines` 的 `package init` 包起來；`LKAIHTTPLines` 被釋放或迭代的 task 被取消時，取消 `URLSession` 的資料傳輸。
- **`LKAIHTTPResponse`**：帶狀態碼、標頭（key 一律轉小寫）與 `lines: LKAIHTTPLines`。
  - 讀取錯誤內容的方法 `readErrorBody()` 建在 `lines` 之上，以 `\n` 串接各行、最多保留 64 KiB（UTF-8 位元組數），達到上限就停止迭代並釋放逐行內容，以免異常的大型回應耗盡記憶體。
  - 64 KiB 是估計值，足以容納三家已知的錯誤格式；以測試確認超過上限時截斷而不失敗。
- **`LKAIHTTPLines`**（`package`）：`AsyncSequence`，`Element` 為 `String`、`Failure` 為 `LKAIError`。
  - `package init(_ source: AsyncThrowingStream<String, any Error>)`，讓 `URLSession` 版本與測試替身用同一種方式建立。
  - 錯誤轉換規則同 `LKAIChatStream`：迭代的 task 已被取消或來源丟出 `CancellationError`、`.cancelled` 時正常結束；其他 `LKAIError` 原樣交出；其他錯誤轉成 `.invalidResponse`。
- **`LKAIHTTPLineSplitter`**（`package`）：把位元組切成行，可以直接餵位元組測試，不必透過 `URLProtocol`。
  - 依 SSE 規格，只把 CRLF、LF 與單獨的 CR 當成換行，CR 後緊接 LF 算一次換行；保留空行；U+2028、U+2029、U+0085 不算換行。
  - 只比對 `0x0A` 與 `0x0D` 兩個位元組。UTF-8 的多位元組字元不會包含這兩個值，所以不會切壞字元；每行以 UTF-8 解碼。
  - 提供逐位元組輸入的方法，以及串流結束時交出最後一段未換行內容的收尾方法。
  - 不用 `URLSession.AsyncBytes.lines`，理由見 Context 的實測：它會丟掉所有空行，而 SSE 靠空行判斷一筆事件結束；它也會在 U+2028 等字元處切開，JSON 字串裡可以合法出現這些字元，資料行會被切壞。
- **`LKAIServerSentEventParser`**：依 WHATWG HTML 規格的 event stream 解析規則逐行解析：
  - 以 `:` 開頭的行是註解，略過。
  - 其他行以第一個 `:` 分成欄位名與值；值開頭若是一個空白，移除這一個空白。沒有 `:` 的行，整行是欄位名、值為空字串。
  - `event`：設定事件名稱。`data`：把值加進資料，多個 `data` 以 `\n` 串接。`id`、`retry` 與其他欄位名：略過，本 package 不使用重新連線。
  - 遇到空行時：資料為空就不送出事件，只清除事件名稱；否則送出事件，並清除事件名稱與資料。
  - 串流結束時，丟棄尚未以空行收尾的事件，不送出。這與規格相同；供應商因此收不到結束事件，由各自的規則判定為 `.invalidResponse`。

三家都用 SSE，所以這份解析可以共用。名稱依 ios-dev-kit 的 Core 層後綴規則取 `Client`。依命名規則，`package` 層級的共用程式只寫在 `LKAICore`。

考慮過的替代方案：

- 每家供應商各自處理 HTTP 與 SSE：重複的程式容易各自出錯，否決。
- 使用 `URLSession.AsyncBytes.lines` 切行：實測會丟空行，並在 Unicode 換行字元處切開，否決。

### 測試替身放在不屬於任何 product 的 LKAITestSupport target

這個決策回答上一個 change 的開放問題二的後半。

- **新增 `LKAITestSupport`**：以 `.target` 宣告，只依賴 `LKAICore`，不列進任何 product，`LKAIKit` 也不依賴它（`package-distribution` spec 的新需求）。
- **`LKAIMockHTTPClient`**：
  - 記錄收到的請求，回傳測試預先設定的狀態碼、標頭與逐行內容；逐行內容以 `LKAIHTTPLines` 的 `package init` 建立。
  - 測試可以控制何時送出下一行與何時結束。
  - 測試可以讓 `send` 直接丟出指定的 `LKAIError`，也可以在逐行內容途中丟出指定的錯誤。
  - 記錄底層請求是否被取消，也就是逐行內容是否因迭代的 task 被取消或被釋放而終止。
- **同步方式**：以 Synchronization 模組的 `Mutex` 保護可變狀態，型別是不帶 `@unchecked` 的 `Sendable` `final class`。

理由：Anthropic 與之後每家供應商的測試都需要同一個替身，測試 target 之間無法互相依賴，所以只能放進一般 target。ios-dev-kit `tests/MockService.swift` 樣板以「測試為單執行緒存取」為由使用 `@unchecked Sendable`，但串流測試會讓 client 的背景 task 與測試同時存取替身，這個前提不成立，所以改用 `Mutex`。

考慮過的替代方案：每個測試 target 各寫一份替身，會重複且容易不一致，否決。

### 跨供應商組裝邏輯暫不提供

這個決策回答上一個 change 的開放問題一。

本 change 不提供依設定挑選供應商或失敗時改用另一家的邏輯，App 自己建立具體的 client。BuyLedger 一次只用一家，目前沒有需求。上一個 design 也指出，新增組裝 target 必須修改 spec「Module dependency direction」，等真的需要時再修改。

### 外部型別遵循本 package 的 public protocol 只能寫在 LKAICore

這個決策回答上一個 change 的開放問題三。

允許讓非本 package 的型別遵循本 package 宣告的 `public` protocol，但只能寫在 `LKAICore`，供應商 target 不得這樣寫。

- protocol 屬於本 package，不會和其他套件撞名。
- Swift 6 只在型別與 protocol 都來自外部時才視為追溯遵循。
- 限定寫在單一定義點，可以避免兩家供應商各自為同一個型別加上同一個遵循。

本 change 沒有實際用到這條規則，但把它寫進 `docs/spectra/config.yaml` 的命名規則，之後的 change 讀得到。

### LKAnthropicClient 以 API 金鑰與 URLSession 建立，金鑰不出現在診斷輸出

- **公開 init**：`init(apiKey: String, urlSession: URLSession)`。依 ios-dev-kit 鐵則 7，依賴以 init 注入、不給預設值。
- **測試用 init**：`package init(apiKey: String, httpClient: any LKAIHTTPClientProtocol)`。
- **請求格式**：端點固定為 `https://api.anthropic.com/v1/messages`；`anthropic-version` 固定為 `2026-10-21`。非串流也送 `stream: true`，再由共用的預設實作彙整。
- **金鑰保密**：
  - 實作 `CustomStringConvertible`、`CustomDebugStringConvertible` 與 `CustomReflectable`，讓 `String(describing:)`、`String(reflecting:)` 與 `dump(_:)` 都不輸出金鑰。
  - 回報的錯誤不帶入金鑰。

理由：struct 預設的描述會印出全部的 stored property，App 一不小心記錄這個 client 就會把金鑰寫進 log。

### Anthropic 串流事件的對應規則

`LKAnthropicClient` 依序處理 SSE 事件：

- **`message_start`**：讀取 `message.model`；有 `usage` 時讀取用量，沒有時不視為錯誤（官方範例就有這種情況，見 Context）。
- **`content_block_start`**：類型為 `fallback` 時，記下 `to.model` 作為 `respondingModel`，不送出事件；其他類型不處理。
- **`content_block_delta`**：只有 `text_delta` 送出文字片段；`thinking_delta`、`signature_delta` 等其他類型略過。
- **`message_delta`**：可能有一個以上。
  - `stop_reason` 取最後一個不是 null 的值；`stop_details` 跟著它讀取，`category` 為 null 時拒答不帶原因說明。
  - 用量是累計值，包含 `output_tokens_details.thinking_tokens`。值為 null 或沒有出現的欄位視為沒有回報，保留先前的值。
  - 從頭到尾都沒有收到 `input_tokens` 或 `output_tokens` 時，結束事件不帶用量，因為 `LKAIUsage` 的這兩個欄位不是選填。
- **`message_stop`**：依 `stop_reason` 送出結束事件（`model_context_window_exceeded` 對應 `.contextWindowExceeded`），或丟出拒答錯誤、非預期回應錯誤。
- **`ping`**：略過。
- **`error`**：依 `error.type` 丟出對應的 `LKAIError`。串流中沒有 HTTP 狀態碼可用，所以：
  - 已知類型帶固定的狀態碼：`api_error` 為 500、`overloaded_error` 為 529、`timeout_error` 為 504。
  - 不認得的 `error.type` 視為伺服器端錯誤，對應 `.serviceUnavailable(statusCode: 500)`。官方文件寫明之後可能出現新類型，而串流中途的錯誤都發生在伺服器端。
  - 事件內容無法解碼時丟出 `.invalidResponse`。
- **其他未知事件**：略過，以容納 API 之後新增的事件類型。

對應表見 `anthropic-provider` spec。

### 使用者自設的花費上限以錯誤訊息的開頭辨識

Anthropic 對組織或工作區自己設定的花費上限回 400 `invalid_request_error`，沒有 `error_code`，只有訊息以 `You have reached your specified` 開頭（見 Context）。`LKAnthropicClient` 以這段開頭把它對應為 `.quotaExceeded`，其他 `invalid_request_error` 仍是 `.invalidRequest`。

- 理由：照狀態碼與類型會變成「請求不合法」，App 會顯示錯誤的說明，使用者也無從得知是額度用完（使用者決定）。
- 比對官方文件寫明的開頭文字；文字日後若改變，只會退回成 `.invalidRequest`，不會比現在更糟。
- 用量等級的月度花費上限照 `error.details.error_code` 判斷，不受這條規則影響。

考慮過的替代方案：維持 `.invalidRequest` 並寫進 Risks。App 顯示的說明會不正確，使用者選擇辨識。

### 生成途中塞滿 context window 以獨立的結束原因回報

`LKAIFinishReason` 有三個 case：`completed`、`maxOutputTokens` 與 `contextWindowExceeded`。後兩者都不視為錯誤：串流以對應的結束原因收尾，非串流仍回傳已產生的文字。

理由：兩者原因與解法不同。

- `maxOutputTokens`：呼叫端自己設的輸出上限用完了，調高 `maxOutputTokens` 就能解決。
- `contextWindowExceeded`：輸入加上輸出塞滿了模型本身的容量，調高上限沒用，要縮短對話或輸入，或換更大的模型。

併成同一個結束原因，App 就無法給使用者正確的處理方式。這個區分由使用者指出並決定。

範圍：只涵蓋生成途中塞滿的情況，對應 Anthropic 的 `stop_reason` `model_context_window_exceeded`。輸入本身就已經過長、在生成前就被拒絕的 HTTP 400 錯誤，照預設分類回報為 `.invalidRequest`；要不要為它設專屬錯誤，見 Open Questions。其他供應商有沒有生成途中的對應狀態，由各自的 change 查證。

考慮過的替代方案：

- 併入 `.maxOutputTokens`：App 分不出兩種情況，否決。
- 視為 `.invalidResponse`：App 拿不到已經產生的文字，否決。

### 實際回應的模型放進共用結果

- 結束時的資訊整理成 `LKAIChatCompletion`，帶 `finishReason`、`usage`、`respondingModel` 三個欄位。串流的結束事件為 `.finished(LKAIChatCompletion)`。
- `LKAIChatResponse` 只帶 `text` 與 `completion: LKAIChatCompletion`，App 寫成 `response.completion.finishReason`。結束資訊只在 `LKAIChatCompletion` 維護一處，非串流的預設實作直接帶入串流的結束資訊（使用者決定）。之後三家都有的回應識別碼這類欄位，只需加在 `LKAIChatCompletion`。
- `respondingModel` 是供應商回報的、實際產生最後輸出的模型識別碼，沒有回報時為 `nil`。三家都有對應欄位，見 Context 的對照表。
- 理由：
  - 開啟拒答備援時，App 要知道是否改由備援模型回答，以及該用哪個模型的費率。
  - 模型別名被解析成具體版本時也用得到。
  - 由使用者決定加入。
- 結束事件用 struct 帶資料，而不是在 enum 再加一個 associated value：增減 enum 的 associated value 一定會讓 App 的程式碼編譯失敗；在 struct 加屬性時，只要遵守決策「公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值」，App 讀取與建立這個 struct 的程式碼都不受影響。

考慮過的替代方案：

- 不提供：App 就無法得知是否改由備援模型回答，使用者否決。
- `LKAIChatResponse` 把結束資訊的三個欄位再寫一次：之後每加一個結束資訊要改兩個 struct、兩個 init 與彙整邏輯，使用者選擇改持有 `completion`。

### 公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值

- **`@nonexhaustive`**：`LKAIError`、`LKAIFinishReason`、`LKAIChatStreamEvent` 標上 `@nonexhaustive`（使用者決定）。
  - 這三個 enum 都看得到之後會增加 case：Open Questions 已在考慮新的錯誤種類；Gemini 的 `finishReason` 除了 `STOP`、`MAX_TOKENS`、`SAFETY` 還有其他值，要到 Gemini 的 change 才決定如何對應；三家都有思考內容，之後可能成為串流事件。
  - App 對它們的 `switch` 必須寫 `@unknown default`，否則在 Swift 6 語言模式下編譯錯誤；本 package 內的程式不受影響（實測，見 Context）。
  - 依 SE-0487，日後再加是 API 破壞性變更、日後拿掉則不會，所以在 App 開始依賴之前加上。
  - `LKAIMessageRole` 與 `LKAnthropicRefusalFallback` 不標：前者增加角色等於改變請求內容的契約，要另開 change 修改 `chat-client` spec；後者是 App 傳入的設定值，App 很少對它做 `switch`。
- **公開 struct 的 init**：`LKAIChatRequest`、`LKAIMessage`、`LKAIUsage`、`LKAIChatCompletion`、`LKAIChatResponse` 之後新增欄位時，`public init` 的新參數一律給預設值（選填欄位給 `nil`），讓 App 為測試替身建立這些值的程式碼不必修改。本 change 定義的參數不受此限，依原本是否選填決定。

考慮過的替代方案：先不標 `@nonexhaustive`、等 1.0 前再評估。App 開始依賴之後再加就是破壞性變更，使用者選擇現在就標。

### Anthropic 的拒答備援由 App 在建立 client 時選擇開啟

- **設定方式**：`LKAnthropicClient` 的 init 多一個參數 `refusalFallback: LKAnthropicRefusalFallback`，預設 `.disabled`。這個預設值屬於設定選項，不是 ios-dev-kit 鐵則 7 所說的依賴注入，所以可以給預設值。`LKAnthropicRefusalFallback` 有三個 case：
  - `.disabled`：不使用備援。
  - `.automatic`：送出 `"fallbacks": "default"`，由 Anthropic 依拒答類別挑選備援模型。
  - `.models([String])`：指定 1 到 3 個不重複的備援模型。
- **請求內容**：開啟時加上 `anthropic-beta: server-side-fallback-2026-07-01`，請求內容加上 `fallbacks`；關閉時兩者都不送。
- **本地驗證**：`.models` 的清單為空、超過 3 個、有重複或含空字串時，不送請求，直接丟出 `.invalidRequest`。以下由 API 判斷，不允許時 API 回 400，依錯誤對應規則成為 `.invalidRequest`：
  - 模型是否在原模型允許的備援名單內。
  - 備援模型是否與請求的模型相同：請求的模型每次呼叫才指定，client 建立時無從檢查。
- **`///` 說明**：`LKAnthropicRefusalFallback` 的說明寫明以下事項（見 Context）：
  - 開啟後頂層用量只涵蓋最後產生回應的那次嘗試。
  - Claude Haiku 5.5 沒有伺服器端備援：`.automatic` 時拒答照常回報，`.models` 時 API 回 400。
  - 備援模型不可與請求的模型相同。
- **串流途中切換**：
  - `fallback` 區塊依「其他類型的區塊略過」處理，文字片段照常送出。
  - 備援模型接續寫完時正常完成；最後仍拒答時丟出 `.refused`。
  - `respondingModel` 取最後一個 `fallback` 區塊的 `to.model`；沒有 `fallback` 區塊時取 `message_start` 的 `message.model`。
- **用量**：開啟備援時，頂層用量只涵蓋最後產生回應的那一次嘗試，被拒答的那次嘗試另外計費。本 change 不加總 `usage.iterations`。
- **理由**：LKAIKit 提供能力，App 決定是否使用（使用者決定）。
  - 預設關閉，因為開啟後可能改由另一個模型回答，並以那個模型的費率計費。
  - 在 client 層級設定，就不必為共用的 `LKAIChatRequest` 增加一套供應商專屬選項的機制（使用者決定）。

考慮過的替代方案：

- 每次呼叫各自設定：共用請求需要一套供應商專屬選項的機制，使用者選擇在 client 層級設定。
- 預設開啟：會在 App 不知情時改變回答的模型與費用，否決。
- 不提供：LKAIKit 應該提供這項能力，使用者否決。

### 型別依 ios-dev-kit 樣板建立

| 檔案 | 建立方式 |
| --- | --- |
| `LKAIChatClientProtocol.swift` | `data/Service.swift` 的 Protocol 區（`Service` 換成 `Client`）；實作分散在各供應商 target，所以刪掉 Implementation 區 |
| `LKAIHTTPClient.swift` | `data/Service.swift`，protocol 與 `URLSession` 實作同檔 |
| `LKAnthropicClient.swift` | `data/Service.swift` 的 Implementation 區與 protocol 遵循 extension |
| `LKAIMockHTTPClient.swift` | `tests/MockService.swift`，以 `Mutex` 取代 `@unchecked Sendable`（見上方決策） |
| `LKAIMessage.swift`、`LKAIChatRequest.swift`、`LKAIUsage.swift`、`LKAIChatResponse.swift`、`LKAIServerSentEvent.swift` | `domain/Model.swift`，依該檔規則拿掉用不到的 `Identifiable`、`Codable` |
| `LKAIHTTPResponse.swift` | `domain/Model.swift`，另外拿掉 `Equatable`，因為它帶著逐行內容 |
| `LKAIMessageRole.swift`、`LKAIFinishReason.swift` | `domain/Enum.swift`，不設 raw type，拿掉 `Codable` 與 `title`；傳輸格式由各供應商轉換 |
| `LKAIChatStreamEvent.swift` | `domain/EnumWithAssociatedValue.swift`，依該檔規則刪掉整組 `Codable`，並拿掉 `title` |
| `LKAIError.swift` | `domain/Error.swift`，保留 `LocalizedError` extension，字串以 `bundle: .module` 讀取 |
| `Localizable.xcstrings` | 沒有對應樣板，以 Xcode 的 String Catalog 格式建立 |
| `LKAIChatCompletion.swift` | `domain/Model.swift`，拿掉 `Identifiable`、`Codable` |
| `LKAnthropicRefusalFallback.swift` | `domain/EnumWithAssociatedValue.swift`，刪掉整組 `Codable` 與 `title` |
| `LKAIChatStream.swift`、`LKAIHTTPLines.swift`、`LKAIHTTPLineSplitter.swift`、`LKAIServerSentEventParser.swift`、Anthropic 的內部傳輸型別 | 沒有對應樣板，依 `file-templates.md` 檔頭規則、`formatting.md` 與 `coding-style.md` 手寫 |
| 所有測試檔 | `tests/Tests.swift` |

上一個 change 的決策「只有測試檔使用 ios-dev-kit 樣板」只適用於它自己的檔案：當時只有測試檔對得上樣板。本 change 的 Client、Model、Error 都有樣板，依鐵則 1 從樣板複製，與那個決策不衝突。

### 測試 target 依受測 target 增加 LKAIAnthropicTests

延續上一個 change 的決策「測試採 Swift Testing 並依受測 target 分成三個測試 target」：

- **新增 `LKAIAnthropicTests`**：依賴 `LKAIAnthropic`、`LKAICore`、`LKAITestSupport`。依該決策，測試檔直接 import 的模組都要列為依賴。
- **`LKAICoreTests`**：
  - 切行規則直接餵位元組給 `LKAIHTTPLineSplitter` 測試。
  - 測試 HTTP client 時，用測試檔內自訂的 `URLProtocol` 攔截請求，不連網、也不依賴 `LKAITestSupport`。
  - 每個測試以 `URLProtocol.setProperty(_:forKey:in:)` 把自己的假回應（狀態碼、標頭、內容、是否不結束）掛在請求上，`URLProtocol` 從請求讀取。不使用 `static` 可變狀態或指向 lock 的 `static let`：前者在 Swift 6 編譯失敗（實測，見 Context），後者違反 ios-dev-kit `coding-style.md`，而且 Swift Testing 預設平行執行，共用狀態會讓測試互相干擾。
  - 假回應一律帶 `Content-Type: text/event-stream`，否則 `URLSession` 會先緩衝內容（實測，見 Context）。
  - 取消的測試讓假回應不結束，取消迭代的 task 後確認得到 `.cancelled`（而不是 `.transport`）。`URLError(.cancelled)` 只在 `URLSession` 真的取消資料傳輸時出現，`stopLoading()` 也同時被呼叫（實測），所以不需要跨物件回報 `stopLoading()`。
- **`LKAITestSupport` 不設測試 target**：它由 `LKAIAnthropicTests` 實際使用來驗證。
- **實際 API 的測試**：放在 `LKAnthropicClientTests`，只在環境變數 `LKAI_ANTHROPIC_API_KEY` 有設定時執行（Swift Testing 的 `.enabled(if:)`），沒設定時略過。
  - 一般的 `swift test` 不連網、不花錢。
  - 由 owner 帶上金鑰手動執行一次，作為與真實 API 相容的驗證。
  - 提示詞要求只回一個詞，`maxOutputTokens` 設 4096：Claude Opus 5.5 思考一律開啟，思考的 token 也計入上限，上限太小時可能還沒輸出文字就以 `.maxOutputTokens` 結束。

### 平行實作時兩位實作者各用一個 git worktree

實測 `swift test --filter` 仍會建置所有 target（見 Context）。任務 1.1 到 3.3 幾乎都在 `LKAICore` 與 `LKAICoreTests`，先寫測試的階段整個 target 都編譯不過，兩人在同一個工作目錄會互相打壞建置，「沒有編譯警告」的判定也會混到對方的警告。

- 每位實作者在自己的 git worktree 修改檔案，由主對話分別在各 worktree 執行建置與測試（使用者決定）。
- **位置**：worktree 建在 repo 根目錄下的 `.worktrees/<名稱>/`，並在 `.gitignore` 新增 `.worktrees/`（使用者決定）。2026-11-21 在 scratchpad 以 Swift 6.4.2 實測：
  - 加入 `.gitignore` 後，根目錄的 `git status` 看不到 worktree 的內容。
  - 根目錄的 `swift package dump-package` 只列出根目錄 manifest 的 target。worktree 內的檔案改到一半而編譯失敗時，根目錄的 `swift test` 不受影響。
  - worktree 內可以各自建置，`.build/` 也各自獨立。
- **建立時機**：主對話先完成任務 5.2（含 `.gitignore` 的這一行），再建立 worktree 並派出第一批任務。
- 主對話驗證完一個任務後，把它合併回這個 change 的工作分支，再讓下一個任務從合併後的狀態開始。
- 多個任務都會改 `Package.swift`（1.1、3.3、4.1、5.1），合併時由主對話處理衝突並重新驗證。

考慮過的替代方案：

- 依序派工：最單純，但失去平行的好處。
- 只平行不同 target 的任務：本 change 前半幾乎都在 `LKAICore`，實際上多半變成依序。

## Implementation Contract

**行為（App 可觀察）：**

- App 只需 `import LKAIKit`，以 `LKAnthropicClient(apiKey:urlSession:)` 建立 client，存成 `any LKAIChatClientProtocol`。
- `stream(_:)` 依序送出 `.textDelta(String)`，最後送出一次 `.finished(LKAIChatCompletion)`，然後結束。
- `invoke(_:)` 回傳 `LKAIChatResponse(text:completion:)`。
- 結束事件與非串流結果都帶 `respondingModel`，也就是供應商回報的實際回應模型。
- 以 `LKAnthropicClient(apiKey:urlSession:refusalFallback:)` 開啟拒答備援時，拒答會先改由備援模型重答，`respondingModel` 指出實際回答的模型；預設不開啟。
- 達到輸出上限時回報結束原因 `.maxOutputTokens`，不視為錯誤；非串流仍回傳已產生的文字。
- 生成途中塞滿模型的 context window 時回報結束原因 `.contextWindowExceeded`，同樣不視為錯誤；非串流仍回傳已產生的文字。
- 拒答時丟出 `.refused(detail:)`；非串流不回傳半截內容。
- 迭代串流的 task 被取消時，串流正常結束並取消底層請求，取消後才收到的錯誤不會交給 App；非串流丟出 `.cancelled`。
- App 釋放串流時，不論是否迭代過，都取消底層請求；只離開迴圈、仍持有串流時，請求繼續進行。
- App 對 `LKAIError`、`LKAIFinishReason`、`LKAIChatStreamEvent` 的 `switch` 必須寫 `@unknown default`。
- 請求的模型為空字串、訊息為空、`maxOutputTokens` 小於 1 時，不送出網路請求，直接丟出 `.invalidRequest`。
- 所有失敗都以 `LKAIError` 回報，`isRetryable` 依 `chat-client` spec 決定。
- 每個 `LKAIError` 都有英文與正體中文的本地化說明（`errorDescription`），App 的語言不是這兩種時用英文；說明不含供應商訊息、拒答原因、`URLError` 文字或 API 金鑰。

**公開介面（`LKAICore`）：**

```swift
public protocol LKAIChatClientProtocol: Sendable {
    func stream(_ request: LKAIChatRequest) -> LKAIChatStream
    func invoke(_ request: LKAIChatRequest) async throws(LKAIError) -> LKAIChatResponse
}
// public 的 protocol extension 提供 invoke(_:) 的預設實作：彙整 stream(_:)

public struct LKAIChatRequest: Equatable, Sendable {
    public let model: String
    public let messages: [LKAIMessage]
    public let systemPrompt: String?
    public let maxOutputTokens: Int
    public init(model: String, messages: [LKAIMessage], systemPrompt: String? = nil, maxOutputTokens: Int)
}
public struct LKAIMessage: Equatable, Sendable {
    public let role: LKAIMessageRole
    public let text: String
    public init(role: LKAIMessageRole, text: String)
}
public enum LKAIMessageRole: CaseIterable, Sendable { case user, assistant }
@nonexhaustive
public enum LKAIFinishReason: CaseIterable, Sendable { case completed, maxOutputTokens, contextWindowExceeded }
public struct LKAIUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?
    public init(inputTokens: Int, outputTokens: Int, cachedInputTokens: Int?, reasoningOutputTokens: Int?)
}
@nonexhaustive
public enum LKAIChatStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case finished(LKAIChatCompletion)
}
public struct LKAIChatCompletion: Equatable, Sendable {
    public let finishReason: LKAIFinishReason
    public let usage: LKAIUsage?
    public let respondingModel: String?
    public init(finishReason: LKAIFinishReason, usage: LKAIUsage?, respondingModel: String?)
}
public struct LKAIChatResponse: Equatable, Sendable {
    public let text: String
    public let completion: LKAIChatCompletion
    public init(text: String, completion: LKAIChatCompletion)
}
public struct LKAIChatStream: AsyncSequence, Sendable {
    // Element == LKAIChatStreamEvent, Failure == LKAIError
    public init(_ source: AsyncThrowingStream<LKAIChatStreamEvent, any Error>)
}
@nonexhaustive
public enum LKAIError: Error, Equatable, Sendable {
    case invalidAPIKey, permissionDenied
    case rateLimited(retryAfter: Duration?)
    case quotaExceeded
    case serviceUnavailable(statusCode: Int)
    case invalidRequest(message: String?)
    case refused(detail: String?)
    case cancelled
    case transport(underlying: URLError)
    case invalidResponse(reason: String)
    // public var isRetryable: Bool
    // 另在獨立 extension 遵循 LocalizedError，提供 errorDescription
}
```

以上 Swift 片段只表達名稱、型別、存取層級與屬性標記。實作時依 ios-dev-kit 樣板補上 `///`、MARK 分區，並把 protocol 遵循放進獨立 extension。`LKAIChatStream` 只支援單一消費者，跟 `AsyncThrowingStream` 相同。

`///` 說明另外寫明以下事項：

- `LKAIChatClientProtocol.stream(_:)` 與 `LKAIChatStream`：請求在呼叫時就送出；釋放串流才會取消請求，只離開迴圈不會。
- `LKAIFinishReason.contextWindowExceeded`：本 change 只有 Anthropic 會回報；其他供應商是否有對應狀態由各自的 change 查證，沒有時同樣情況可能以 `.maxOutputTokens` 或 `.invalidRequest` 出現。
- `LKAIError.serviceUnavailable(statusCode:)`：串流中途的錯誤沒有 HTTP 狀態碼，狀態碼由供應商依錯誤類型指定。
- `LKAIError.refused(detail:)`：各家的原因說明格式不同（類別代碼、說明文字或列舉名），只適合記錄 log，不適合依內容判斷。

**package 層級介面（`LKAICore`，只給本 package 內使用）：**

- **`LKAIChatRequest` 的驗證方法**：違反請求規則時丟出 `.invalidRequest(message:)`，訊息指出哪一條規則。
- **`LKAIError` 的預設分類**：依 HTTP 狀態碼與 `retry-after` 標頭產生錯誤。`retry-after` 只有在完全由 ASCII 數字組成時才當成秒數；帶正負號、空白或 HTTP 日期等其他格式，視為沒有提供重試延遲。不直接用 `Int(_:)` 判斷，因為它接受正負號（實測，見 Context）。
- **`LKAIHTTPClientProtocol`**：`func send(_ request: URLRequest) async throws(LKAIError) -> LKAIHTTPResponse`。
- **`LKAIHTTPResponse`**：`statusCode: Int`、`headers: [String: String]`（key 一律轉小寫）、`lines: LKAIHTTPLines`，以及 `func readErrorBody() async throws(LKAIError) -> String`：以 `\n` 串接各行，最多 64 KiB（UTF-8 位元組數），超過時截斷而不失敗，並停止讀取。
- **`LKAIHTTPLines`**：`AsyncSequence`，`Element` 為 `String`、`Failure` 為 `LKAIError`；`package init(_ source: AsyncThrowingStream<String, any Error>)`。錯誤轉換規則與 `LKAIChatStream` 相同。
- **`LKAIHTTPLineSplitter`**：逐位元組輸入，交出完成的行；串流結束時交出最後一段未換行的內容。以 CRLF、LF、單獨的 CR 換行，保留空行，U+2028、U+2029、U+0085 不算換行。
- **`LKAIHTTPClient(session:)`**：`URLSession` 實作。
  - `URLError(.cancelled)` 且 task 已被取消時轉成 `.cancelled`；其他 `URLError` 轉成 `.transport(underlying:)`。
  - 以 `LKAIHTTPLineSplitter` 切行，以 `LKAIHTTPLines` 交出；逐行內容被釋放或迭代的 task 被取消時，取消底層的資料傳輸。
- **`LKAIServerSentEvent`、`LKAIServerSentEventParser`**：`LKAIServerSentEvent` 帶選填的 `event` 名稱與 `data` 字串；`LKAIServerSentEventParser` 提供逐行解析與串流結束時的收尾方法，規則見決策「共用 HTTP client 與 SSE 解析放在 LKAICore，以 package 存取層級提供」。收尾時丟棄尚未以空行收尾的事件。

**Anthropic（`LKAIAnthropic`）：**

- **`public struct LKAnthropicClient: Sendable`**：
  - `public init(apiKey: String, urlSession: URLSession, refusalFallback: LKAnthropicRefusalFallback = .disabled)`
  - `package init(apiKey: String, httpClient: any LKAIHTTPClientProtocol, refusalFallback: LKAnthropicRefusalFallback = .disabled)`
  - 遵循 `LKAIChatClientProtocol`、`CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable`。
- **請求**：
  - POST `https://api.anthropic.com/v1/messages`。
  - 標頭為 `x-api-key`、`anthropic-version: 2026-10-21`、`content-type: application/json`。
  - 內容為 `model`、`max_tokens`、`messages`（`role` 與文字 `content`）、`stream: true`，有系統指示時才帶 `system`。
  - 開啟拒答備援時，另帶標頭 `anthropic-beta: server-side-fallback-2026-07-01` 與內容欄位 `fallbacks`：`.automatic` 為 `"default"`，`.models` 為每個模型一個 `{"model": ...}`。
- **`stream(_:)`**：依決策「以自訂 AsyncSequence 提供 typed throws 的串流」的「生產端 task 的擁有權」建立一個 task，請求在呼叫時送出，由 `onTermination` 取消。
- **錯誤對應**：依 `anthropic-provider` spec 的「Error mapping」，包含 `timeout_error`、以訊息開頭辨識的自設花費上限，以及串流中 `error` 事件的狀態碼。
- **`public enum LKAnthropicRefusalFallback: Equatable, Sendable`**：`case disabled, automatic, models([String])`。
- **內部傳輸型別**（名稱可調整，但頂層型別一律用 `LKAnthropic` 開頭）：請求內容的 `Encodable` 型別、串流事件與錯誤內容的 `Decodable` 型別，以及累積用量與 `stop_reason` 的串流狀態型別。

**`LKAITestSupport`：**

`package final class LKAIMockHTTPClient: LKAIHTTPClientProtocol, Sendable`：

- 記錄收到的 `URLRequest`。
- 回傳預先設定的狀態碼、標頭與逐行內容，測試可逐行推送並決定何時結束。
- 可設定 `send` 直接丟出的 `LKAIError`，以及在逐行內容途中丟出的錯誤。
- 公開是否偵測到底層請求被取消：逐行內容的來源因迭代的 task 被取消或被釋放而終止。

存取層級：它遵循的是 `package` protocol，只供同 package 的測試使用，所以型別與成員都標 `package`。

**檔案位置：**

- `Sources/LKAICore/Chat/`：`LKAIChatClientProtocol.swift`、`LKAIChatCompletion.swift`、`LKAIChatRequest.swift`、`LKAIMessage.swift`、`LKAIMessageRole.swift`、`LKAIChatStream.swift`、`LKAIChatStreamEvent.swift`、`LKAIChatResponse.swift`、`LKAIFinishReason.swift`、`LKAIUsage.swift`、`LKAIError.swift`
- `Sources/LKAICore/Resources/`：`Localizable.xcstrings`（`en`、`zh-Hant`）
- `Sources/LKAICore/Networking/`：`LKAIHTTPClient.swift`、`LKAIHTTPResponse.swift`、`LKAIHTTPLines.swift`、`LKAIHTTPLineSplitter.swift`、`LKAIServerSentEvent.swift`、`LKAIServerSentEventParser.swift`
- `Sources/LKAIAnthropic/`：`LKAnthropicClient.swift`、`LKAnthropicRefusalFallback.swift`，以及 Anthropic 的內部傳輸型別各自的檔案
- `Sources/LKAITestSupport/`：`LKAIMockHTTPClient.swift`
- 測試：
  - `Tests/LKAICoreTests/`：`LKAIChatRequestTests.swift`、`LKAIErrorTests.swift`、`LKAIChatStreamTests.swift`、`LKAIChatClientProtocolTests.swift`、`LKAIServerSentEventParserTests.swift`、`LKAIHTTPLineSplitterTests.swift`、`LKAIHTTPClientTests.swift`
  - `Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift`
  - 既有的 `Tests/LKAIKitTests/ExportsTests.swift` 新增一個測試

**manifest 與總成：**

- `Package(...)` 新增 `defaultLocalization: "en"`；`LKAICore` 改為 `.target(name: "LKAICore", resources: [.process("Resources")])`。
- 新增 targets：
  - `.target(name: "LKAIAnthropic", dependencies: ["LKAICore"])`
  - `.target(name: "LKAITestSupport", dependencies: ["LKAICore"])`
  - `.testTarget(name: "LKAIAnthropicTests", dependencies: ["LKAIAnthropic", "LKAICore", "LKAITestSupport"])`
- `LKAIKit` 改為依賴 `["LKAICore", "LKAIAnthropic"]`；`Sources/LKAIKit/Exports.swift` 新增 `@_exported import LKAIAnthropic`。
- products 不變：只有 `LKAIKit` library 與 `lkai` executable。
- 不新增外部套件。

**命名規則：**

`docs/spectra/config.yaml` 的命名規則新增一條：「非本 package 的型別遵循本 package 的 `public` protocol，只能寫在 LKAICore。」並在既有「非供應商 target」的清單補上 `LKAITestSupport`。

**驗收方式：**

- 每條 delta spec 的 scenario 與 example 都有對應的測試，並以 `spectra-scenario` 註解標記：
  - `chat-client` 的 scenario 由 `LKAICoreTests` 對應共用的預設行為，或由 `LKAIAnthropicTests` 對應實際供應商。
  - `anthropic-provider` 的 scenario 由 `LKAIAnthropicTests` 對應。
  - `package-distribution` 的新需求由驗收時的 `swift package dump-package` 檢查。
- `swift package clean` 後 `swift build` 與完整 `swift test` 通過，LKAIKit 自身的 target 沒有編譯警告。
- XcodeBuildMCP 對 iOS 26 模擬器建置 `LKAIKit` scheme 成功。
- `swift package dump-package` 確認：
  - `LKAIAnthropic` 與 `LKAITestSupport` 都只依賴 `LKAICore`，`LKAIKit` 依賴 `LKAICore` 與 `LKAIAnthropic`。
  - 從 `LKAIKit` 可達的 target 不含 `LKAITestSupport`，也不含外部套件。
  - products 不變。
- owner 以真實金鑰執行實際 API 的測試一次，串流與非串流各成功一次。
- Swift 檔案符合 ios-dev-kit 鐵則，依上方樣板表建立，頂層型別名稱符合命名規則。
- `LKAIError`、`LKAIFinishReason`、`LKAIChatStreamEvent` 的宣告帶 `@nonexhaustive`，以內容審查確認（本 package 內的測試看不出有沒有標）。

**範圍：**

- 範圍內：上述 `LKAICore`、`LKAIAnthropic`、`LKAITestSupport` 的來源與測試，`Package.swift`、`Sources/LKAIKit/Exports.swift`、`Tests/LKAIKitTests/ExportsTests.swift`、`docs/spectra/config.yaml`，以及 `.gitignore` 新增 `.worktrees/` 這一行（見決策「平行實作時兩位實作者各用一個 git worktree」）。
- 範圍外：Non-Goals 的所有項目；`LKAIKitCLI` 與它的測試不修改；`LKAIKitInfo.version` 不修改；`.gitignore` 除了 `.worktrees/` 以外不修改。

## Risks / Trade-offs

- [typed throws 的實測只涵蓋最小範例] → 實作時若遇到原型沒涵蓋的限制，停下並以 `/spectra-ingest` 修改「以自訂 AsyncSequence 提供 typed throws 的串流」，不在實作中途改用 `any Error`。
- [`@nonexhaustive` 需要 Swift 6.2.3 以上的編譯器，`swift-tools-version: 6.2` 擋不住 6.2.0 到 6.2.2] → 舊編譯器的行為未實測；本機開發環境為 Swift 6.4.2。若有使用端回報無法編譯，再以 `/spectra-ingest` 決定是否提高 tools version。
- [只照 Anthropic 成形的地方：`.contextWindowExceeded` 目前只有 Anthropic 回報、串流中的 `serviceUnavailable(statusCode:)` 由供應商指定狀態碼、`refused(detail:)` 三家格式不同] → 都不需要修改型別，寫在各自的 `///` 說明。
- [偏離 ios-dev-kit 的地方：每條串流建立一個非結構化 `Task`、`LKAIError` 遵循 `Equatable`] → 理由見各自的決策。
- [使用者自設花費上限的辨識依賴錯誤訊息的開頭文字] → 文字改變時只會退回 `.invalidRequest`；升級 API 版本時與 `anthropic-provider` spec 一起檢查。
- [`lkai` 若只複製執行檔、沒帶 `LKAICore` 的 resource bundle，第一次讀取 `LKAIError` 的說明就會 `fatalError`（實測，見 Context）] → 目前 CLI 沒有讀取錯誤說明，不受影響；第一個會印出 `localizedDescription` 的子指令出現時，由該 change 決定如何發佈 resource bundle。
- [字串跟隨 App 支援的語言只在 macOS 實測，iOS 未實測] → 任務 5.3 以 iOS 模擬器建置時不驗證語言；若 iOS 行為不同，以 `/spectra-ingest` 修改 spec 的敘述。
- [平行實作時兩個 worktree 都會改 `Package.swift`] → 主對話合併時處理衝突，合併後重新執行受影響的測試。
- [測試與 Anthropic 錯誤對應逐字依賴 `error.type`、`stop_reason` 等字串，以及 `anthropic-version: 2026-10-21`] → 升級 API 版本時，`anthropic-provider` spec、對應表與測試一起檢查。
- [App 若把 API 金鑰放在 `Info.plist`，金鑰可以從 App 套件中取出（BuyLedger 目前就是這樣）] → 屬於 App 的部署決定，LKAIKit 只保證不把金鑰寫進描述與錯誤；自訂端點以支援轉送伺服器已列為 Non-Goal，有需求時另開 change。
- [逐位元組讀取 `URLSession.AsyncBytes` 再自行切行，效能較差] → 對話回應只有數 KB 到數十 KB（估計值，未量測），可以接受；實際使用若發現延遲，再以量測決定是否改成整塊讀取。
- [錯誤回應的讀取上限 64 KiB 是估計值] → 以測試確認超過上限時會截斷而不失敗；若遇到合法但更大的錯誤內容再調整。
- [實際 API 的測試會花錢且需要金鑰] → 預設略過，只在設定 `LKAI_ANTHROPIC_API_KEY` 時執行，由 owner 決定何時跑。
- [package 內驗不到存取層級：`LKAIAnthropicTests` 與 `LKAITestSupport` 看得到 `package` 成員，公開 API 標錯層級時 package 內仍全部通過] → 沿用上一個 change 的做法以 review 把關；`ExportsTests` 透過 `import LKAIKit` 使用 `LKAnthropicClient`，可擋下最主要的公開 API 少標 `public` 的錯誤。
- [新增 `LKAIError` 的 case 時，可能忘了補兩種語言的字串] → `errorDescription` 的窮舉 `switch` 會在編譯時要求補上 key；任務 1.1 的測試手動列出每個 case，測試清單與字串檔要在新增 case 時一起補，由 review 檢查。
- [`server-side-fallback-2026-07-01` 是 beta 功能，格式可能變動] → 標頭與 `fallbacks` 的格式集中在 `LKAnthropicClient`，只在 App 開啟時才送出；變動時，`anthropic-provider` spec、對應表與測試一起更新。
- [`LKAIChatStream` 只支援單一消費者，第二次迭代的行為與 `AsyncThrowingStream` 相同] → 寫在型別的 `///` 說明。

## Open Questions

以下不影響本 change，留給之後的 change 決定：

- 輸入本身就超過 context window、在生成前被拒絕的 HTTP 400 錯誤，三家是否有專屬的錯誤代碼，值不值得在 `LKAIError` 設專屬 case（與 `.contextWindowExceeded` 對應），由之後的 change 查證後決定。
- Gemini 要用 `generateContent` 還是較新的 Interactions API，以及 `candidatesTokenCount` 是否不含 `thoughtsTokenCount`（影響輸出總數要不要相加），由 Gemini 的 change 查證。
- 本 change 完成後是否調整 `LKAIKitInfo.version` 並打第一個 release tag，屬於版本與 release 流程，另行決定。
- 第二家供應商的 change 開始時，建議先把 `stream(_:)` 的共同骨架抽進 `LKAICore`，再實作該供應商。骨架包含建立 task、狀態碼檢查、SSE 迴圈、提前結束與取消接線，抽出後修一個取消或提前結束的問題不必改三家。它是 `package` 層級，延後不影響公開 API。
