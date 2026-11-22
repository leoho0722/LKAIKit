# 新增供應商的清單

新增一家 AI 供應商（例如 Gemini、Ollama）時要讀的唯一一份清單。它整理了三份封存 design 與之後的 change 中仍然有效的規則、三家供應商的對照，以及還沒處理的事。

## 1. 怎麼使用這份清單

- **什麼時候讀**：新增供應商的 change 開始前，先讀完這份清單，再寫 proposal 與 design。
- **權威順序**：
  - 系統的行為以 `docs/spectra/specs/` 的 spec 為準。這份清單是開發流程、跨供應商的事實與索引；和 spec 不同時，修正這份清單。
  - 封存的 design（`docs/spectra/changes/archive/`）只記錄當時的決定；和這份清單不同時，以這份清單為準。
- **什麼時候更新**：以下的 change 封存前，都要檢查並更新這份清單：
  - 新增供應商的 change。
  - 修改 chat-client spec、任一供應商 spec，或 `LKAICore` 共同流程的 change。
- **來源**：本清單由 `03-revise-chat-client-contract` 建立，取代 `docs/spectra/config.yaml` 原本一層層指向封存 design 的指標。

## 2. 開始前要做的事

1. **逐列核對第 4 章的供應商對照表**：
   - 新供應商的一欄，以官方文件查證；能送實際請求的項目，以實際請求確認。每一列寫上查證的日期與方式。
   - 文件和實際回應不同時，以實際回應為準，並記錄差異。Gemini 查證時，文件與實際回應有四處不同（見第 4 章 Gemini 一欄），只看文件會寫錯。
   - 實際請求用最便宜的模型、很短的輸出上限，費用記在 design 的 Context。
2. **處理第 6 章與第 7 章中屬於這家供應商的項目**，在 design 的 Context 寫明每一項怎麼處理。
3. **讀第 3 章的規則**，在 design 中凡是偏離其中一條的地方，都寫成決策並說明理由。

## 3. 必須遵守的規則

每一條後面的括號是出處：change 名稱與決策標題（`add-chat-abstraction-anthropic` 簡稱「第一份」）。

**架構與命名**

- 供應商 target 只依賴 `LKAICore`，`LKAIKit` 總成重新匯出所有 library target，App 只要 `import LKAIKit`。（`add-swift-package-foundation`「採用多 target 分層：LKAICore、LKAIKit 總成與 LKAIKitCLI」）
- 供應商 target 的頂層型別以 `LK<供應商>` 開頭，例如 `LKOpenAIClient`；型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加，例如 `LKAIOpenAITests`。（`add-swift-package-foundation`「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」；`02-add-openai-provider`「型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加」）
- 非本 package 的型別遵循本 package 的 `public` protocol，只能寫在 `LKAICore`。（第一份「外部型別遵循本 package 的 public protocol 只能寫在 LKAICore」）
- 端點固定為供應商的官方網址；不提供思考深度、推理設定與取樣參數，一律用 API 的預設值。（第一份 Non-Goals）

**串流的共同流程**

- 以 SSE 串流回答的供應商遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只寫 `makeStream(for: request)`，不自行建立 `Task`。（`01-extract-chat-stream-skeleton`「SSE 對話的共同流程以 LKAIServerSentEventChatStreaming 的 extension 提供」「串流的背景 task 只在 LKAIChatStream.init(producing:) 建立」）
- 每條串流的事件狀態與「何時結束」的判斷，由供應商的 mapper（遵循 `LKAIServerSentEventMapping` 的型別）持有。不認得的事件一律略過。（`01-extract-chat-stream-skeleton`「每條串流的事件狀態與結束判斷由供應商的 mapper 持有」）
- 解碼一律經 `LKAISnakeCaseJSON`，不自己建立 `JSONDecoder()`。（`01-extract-chat-stream-skeleton`「snake_case JSON 的解碼設定收成 LKAISnakeCaseJSON」）

**共用型別與 API 演進**

- 不為自己的格式修改 `LKAICore` 的共用公開型別；需要修改時另開 change 修改 chat-client spec。只改說明文字可以。（`docs/spectra/config.yaml` 的 API 演進規則；`02-add-openai-provider` Non-Goals）
- 公開 enum 標 `@nonexhaustive`；公開 struct 新增欄位時 `init` 的新參數給預設值；公開 enum 的 case 不增減 associated value，第一個 release tag 之後要加資料時改用 struct。（`config.yaml` 的 API 演進規則；第一份「公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值」；`03-revise-chat-client-contract`「服務不可用的錯誤帶上等待時間，不給預設值」）
- token 用量依 `LKAIUsage` 的統一口徑：`inputTokens` 包含讀自快取的部分，`outputTokens` 包含思考或推理的部分。供應商的欄位口徑不同時，在 client 內換算。（第一份「token 用量以統一口徑放進共用型別」）
- 實際產生回應的模型取自供應商的回報，不用請求的模型代替；沒有回報時為 nil。（第一份「實際回應的模型放進共用結果」）

**錯誤**

- HTTP 錯誤由 `httpError(statusCode:headers:body:)` 依供應商的錯誤格式分類，分類不了就回傳 nil，交給共同流程的預設狀態碼分類。（第一份「HTTP 狀態碼的預設分類放在 LKAICore，供應商依自己的錯誤格式覆寫」）
- 自己分類 HTTP 5xx 時讀 `retry-after`，以 `LKAIError.retryDelay(from:)` 換算；能回傳 nil 交給預設分類時就回傳 nil。建立 `.serviceUnavailable` 時一律明寫 `retryAfter:`，串流中途的錯誤傳 nil。（`03-revise-chat-client-contract`「5xx 的預設分類與 Anthropic 的 HTTP 錯誤讀 retry-after」）
- 串流中對應不到任何錯誤種類的錯誤，一律呼叫 `LKAIError.unrecognizedStreamError(code:message:)`：有代碼回報不可重試的 `.invalidResponse`，沒有代碼回報可重試的 500。（`03-revise-chat-client-contract`「不認得的串流錯誤以 unrecognizedStreamError 統一回報」）
  - 供應商的 spec 要寫明：哪個欄位算錯誤代碼、錯誤資料缺到什麼程度算無法解碼。
  - 供應商 spec 的串流錯誤範例表，要有「不認得的代碼」與「沒有代碼」兩列。
- 政策性阻擋回報 `.refused`，而且 HTTP 與串流兩條路徑得到同一種錯誤。（`02-add-openai-provider`「錯誤依 error.code 與 error.type 分類」）
- 分不開「生成途中塞滿 context window」與「達到輸出上限」的供應商，回報 `.maxOutputTokens`，並寫進 `LKAIFinishReason` 的說明與該供應商的 spec。（`03-revise-chat-client-contract`「Context window limit 只適用於分開回報的供應商」）

**金鑰與隱私**

- API 金鑰不出現在 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡；client 實作三個遵循，由測試逐一檢查。（第一份「LKAnthropicClient 以 API 金鑰與 URLSession 建立，金鑰不出現在診斷輸出」；`02-add-openai-provider`「金鑰遮蔽由每家 client 各自實作三個遵循」，04 預定加上包裝型別，見第 6 章）
- 有伺服器端保存的供應商預設不保存，由 App 在建立 client 時選擇開啟。（`02-add-openai-provider`「回應保存由 App 在建立 client 時選擇，預設不保存」）

**測試**

- 共同流程的分支（請求驗證、連線失敗、沒有結束事件、取消與釋放串流）不在供應商的測試重寫一份。（`02-add-openai-provider`「共同流程的分支不在 OpenAI 的測試重寫一份」）
- SSE 分框用 `LKAITestSupport` 的 `LKAIServerSentEventTestSupport.lines(of:)`；與供應商無關的測試 helper 放 `LKAITestSupport`，它不屬於任何 product。（`02-add-openai-provider`「SSE 分框的測試 helper 搬進 LKAITestSupport」；第一份「測試替身放在不屬於任何 product 的 LKAITestSupport target」）
- 每個測試上方，依 spec 加 `spectra-scenario: <capability> / <情境>` 標記，有範例時再加 ` / <範例>`。
- 實際 API 測試只在設定環境變數 `LKAI_<供應商>_API_KEY` 時執行，由 owner 手動跑；金鑰存在 Keychain 的 service `lkai-<供應商>-api-key`。超過 128 字元的金鑰要用 `security add-generic-password -s <service> -a "$USER" -w "$(pbpaste)"` 存，`-w` 不帶值時的密碼提示會把超過 128 字元的部分丟掉。（`02-add-openai-provider`「實際 API 測試以 gpt-6-luna 執行，由 owner 手動跑」與任務 4.2 的執行紀錄）

## 4. 供應商對照表

「本套件的處理」是 LKAIKit 對應成共用型別的方式；其餘是供應商 API 的事實。Gemini 一欄標「實測」的項目以實際請求確認，標「文件」的只依官方文件。

| 項目 | Anthropic Messages API | OpenAI Responses API | Gemini Interactions API `v1` |
| --- | --- | --- | --- |
| 查證日期與方式 | 2026-11-21，官方文件與 Claude Code 內建的 Claude API 參考資料（快取日期 2026-11-03）；實際 API 測試以 `claude-opus-5-5` 於 2026-11-22 通過 | 2026-11-22，Context7 收錄的官方文件；實際 API 測試以 `gpt-6-luna` 於 2026-11-22 通過 | 2026-11-22，Context7 收錄的官方文件，以及對 `v1/interactions` 的 9 次實際請求（主要用 `gemini-3.5-flash-lite`） |
| 端點與驗證 | `POST https://api.anthropic.com/v1/messages`；`x-api-key`、`anthropic-version: 2026-10-21` | `POST https://api.openai.com/v1/responses`；`Authorization: Bearer` | `POST https://generativelanguage.googleapis.com/v1/interactions`；`x-goog-api-key`（實測）。文件範例全用 `v1beta`，`v1beta` 在 2026 年 5 月改過一次結構 |
| 系統指示 | 頂層 `system` | 頂層 `instructions` | 頂層 `system_instruction`，純文字（實測） |
| 訊息角色與多輪歷史 | `user`、`assistant` | `input` 訊息陣列，`user`、`assistant` | `input` 步驟陣列：`user_input` 與 `model_output`，`content` 為 `[{"type":"text","text":…}]`（實測）。文件寫思考步驟「MUST」照原樣送回，實測只送文字也成功 |
| 輸出上限 | `max_tokens`，必填 | `max_output_tokens`，選填，文件寫最小值 16 | `generation_config.max_output_tokens`，必須大於 0，0 回 400 `invalid_request`（實測） |
| 取樣參數 | API 版本 `2026-10-21` 傳 `temperature`、`top_p`、`top_k` 回 400 | 推理模型在 effort 不是 `none` 時，文件要求不要送 `temperature`、`top_p` | 文件寫 Gemini 4 與 3.6 以上的模型忽略自訂的 `temperature`、`top_p`、`top_k` |
| 伺服器端保存 | 沒有回應保存的參數 | `store` 預設 true，保存至少 30 天；本套件預設送 `store: false` | `store` 預設 true，付費方案保存 55 天（文件）；`store: false` 被接受（實測）。04 預定比照 OpenAI 預設不保存 |
| 串流格式 | SSE，`event:` 與 `data:`；文字在 `content_block_delta` 的 `text_delta` | SSE，`event:` 與 `data:`，`data` 帶 `type`；文字在 `response.output_text.delta` | SSE，`event:` 與 `data:`，`data` 帶 `event_type`；文字在 `model_output` 步驟的 `step.delta`，`delta.type` 為 `text`；另有 `: keep-alive` 註解行（實測） |
| 串流的結束方式 | `message_delta` 帶 `stop_reason`，`message_stop` 時結束 | `response.completed`、`response.incomplete`、`response.failed` 或 `error`；沒有 `[DONE]` | `interaction.completed`，結果看 `interaction.status`；之後還有 `event: done` 與 `data: [DONE]`（實測）。文件寫的 `interaction.in_progress` 實際是 `interaction.status_update` |
| 思考內容 | `thinking` 區塊 | reasoning 項目 | `thought` 步驟，串流中只帶 `thought_signature`（實測） |
| 正常完成 | `stop_reason` 為 `end_turn` 或 `stop_sequence` | `response.completed` | `status` 為 `completed`（實測） |
| 達到輸出上限 | `stop_reason` 為 `max_tokens` | `incomplete_details.reason` 為 `max_output_tokens` | `status` 為 `incomplete`，沒有附原因（實測） |
| 生成途中塞滿 context window | `stop_reason` 為 `model_context_window_exceeded`；本套件回報 `.contextWindowExceeded` | 也回報 `max_output_tokens`；本套件回報 `.maxOutputTokens` | 文件的狀態表只寫 `incomplete` 是用完 `max_output_tokens`，沒有獨立的原因 |
| 輸入在生成前就超過 context window | 沒有專屬代碼 | 沒有專屬代碼 | Interactions 的錯誤表沒有專屬代碼；generateContent 的錯誤表把它列在 500 底下。`v1` 的實際狀態碼未實測 |
| 拒答或被擋 | HTTP 200，`stop_reason` 為 `refusal`，`stop_details` 帶類別；本套件回報 `.refused(detail: 類別)` | 拒答內容（`status` 仍是 `completed`）、`content_filter`、政策性阻擋的代碼（`cyber_policy` 等）；本套件都回報 `.refused` | HTTP 400 或串流中的 `error` 事件，`code` 為 `safety`、`jailbreak`、`prohibited_content` 或 `blocklist`（文件，未實測） |
| 金鑰無效 | 401 `authentication_error` | 401 | 401，Google 通用格式 `"status": "UNAUTHENTICATED"`，外面包一層 JSON 陣列（實測）；沒帶金鑰時是同一種格式的 403 `PERMISSION_DENIED`（實測） |
| 頻率限制與額度 | 429 `rate_limit_error`；`error.details.error_code` 為 `enforced_spend_limit_reached` 時是額度；402 `billing_error`；400 訊息以「You have reached your specified」開頭時是自設的花費上限 | 429，以 `error.code` 分出額度代碼（`insufficient_quota`、`credit_balance_exhausted` 等）與頻率限制（`rate_limit_exceeded`、`slow_down`） | 429 `rate_limit_exceeded`、`quota_exceeded`、`too_many_requests`；402 `payment_required`（文件） |
| 服務過載 | 529 `overloaded_error`、500 `api_error`、504 `timeout_error` | 503 `server_is_overloaded`、500 `server_error` | 503 `service_unavailable`（實測，訊息為模型忙碌）；500 `api_error`（文件） |
| 5xx 的 `Retry-After` | 文件只寫 429 帶；5xx 未查證，有帶就讀 | 文件寫暫時性的頻率限制與 503 過載會帶 | 未實測 |
| 錯誤格式 | `{"type":"error","error":{"type","message"}}`，串流中的 `error` 事件相同 | HTTP 為 `{"error":{"code","message","param","type"}}`；串流的 `error` 事件是平的 `{"type":"error","code","message",…}` | Interactions 格式 `{"error":{"code","message"}}`，`code` 是 snake_case（實測：404 `not_found`、400 `invalid_request`、503 `service_unavailable`，文件寫的 `model_not_found` 實際沒出現）；Google 通用格式見「金鑰無效」；串流的 `error` 事件為 `{"event_type":"error","error":{"code","message"}}`（文件）；文件寫沒列出的代碼改用 HTTP 狀態的 snake_case 名稱 |
| 不認得的串流錯誤（本套件的處理） | `error.type` 為錯誤代碼；不認得時 `.invalidResponse`，沒有 `type` 時 500，沒有 `error` 物件或不是 JSON 時無法解碼 | `code` 為錯誤代碼；不認得時 `.invalidResponse`，null 或沒有時 500；`code`、`message` 型別不對時無法解碼 | 由 04 決定，見第 6 章 |
| 實際回應的模型 | `message_start` 的 `message.model`；拒答備援切換時以 `fallback` 區塊的 `to.model` 為準 | 結束事件的 `response.model` | `interaction.created` 與 `interaction.completed` 的 `model`；請求 `gemini-3.5-flash` 時回的是 `gemini-3.6-flash`（實測） |
| token 用量 | `input_tokens` 不含快取，另有 `cache_creation_input_tokens`、`cache_read_input_tokens`；`output_tokens` 含思考 | `input_tokens` 含 `cached_tokens`；`output_tokens` 含 `reasoning_tokens` | `interaction.completed` 的 `interaction.usage`：`total_input_tokens` 含 `total_cached_tokens`（實測：同一段 5000 token 的請求，第二次快取 2033）；`total_output_tokens` **不含** `total_thought_tokens`（實測：41 + 3 + 528 = 572 = `total_tokens`）。文件一處範例寫成 `prompt_tokens`／`completion_tokens`，實際不是 |

## 5. 封存 design 中已被改寫的段落

**收錄標準**：封存 design 中被之後的 change 改寫的決策、決策理由、流程與結構。行為本身以 spec 為準，不另列行為；但封存 design 裡描述該行為、而且已經不成立的句子要列。

| 原位置 | 現行依據 |
| --- | --- |
| 第一份的決策「生產端 task 的擁有權」 | `01-extract-chat-stream-skeleton`：背景 task 只在 `LKAIChatStream.init(producing:)` 建立 |
| 第一份的「`LKAITestSupport` 不設測試 target」 | `01-extract-chat-stream-skeleton`：新增 `LKAITestSupportTests` |
| 第一份 Open Questions 的「抽出 `stream(_:)` 的共同骨架」 | `01-extract-chat-stream-skeleton` |
| 第一份 Open Questions 的「輸入超過 context window 的錯誤要不要專屬 case」 | `02-add-openai-provider`「輸入超過 context window 的錯誤不設專屬種類」；`03-revise-chat-client-contract` Non-Goals |
| 第一份 Open Questions 的「只 `import LKAIKit` 的使用端檢查」 | `02-add-openai-provider` 的 Context：延後到 BuyLedger 整合 |
| 01 Open Questions 的「共同流程分支的測試位置」 | `02-add-openai-provider`「共同流程的分支不在 OpenAI 的測試重寫一份」 |
| 01 Open Questions 的「SSE 分框的測試 helper」 | `02-add-openai-provider`「SSE 分框的測試 helper 搬進 LKAITestSupport」 |
| 01 Open Questions 的「金鑰遮蔽」 | `02-add-openai-provider`「金鑰遮蔽由每家 client 各自實作三個遵循」 |
| 第一份的決策「Anthropic 串流事件的對應規則」中，`error` 事件「不認得的 `error.type` 視為伺服器端錯誤，對應 500」 | `03-revise-chat-client-contract`「不認得的串流錯誤以 unrecognizedStreamError 統一回報」：改成 `.invalidResponse` |
| 同一個決策中「事件內容無法解碼時丟出 `.invalidResponse`」 | 同上：有 `error` 物件但沒有 `error.type` 時改成 500 |
| 第一份的決策「錯誤以 LKAIError 統一分類並標示可否重試」列的 `serviceUnavailable(statusCode: Int)` | `03-revise-chat-client-contract`「服務不可用的錯誤帶上等待時間，不給預設值」：`serviceUnavailable(statusCode:retryAfter:)` |
| 02 的決策「錯誤依 error.code 與 error.type 分類」中「null 為什麼仍當成 500：……沿用 Anthropic 的處理」 | `03-revise-chat-client-contract`：改以 chat-client「Unrecognized stream errors」的共同規則為依據 |
| 02 的決策「Responses API 沒有 context window 的結束原因」中「`LKOpenAIClient` 做不到這條需求」 | `03-revise-chat-client-contract`：修改後的「Context window limit」需求只要求分開回報的供應商回報 `.contextWindowExceeded`，OpenAI 符合 |
| 01 的決策「config.yaml 的指標改為同時指向本 change」、02 的決策「config.yaml 的指標加上本 change」 | `03-revise-chat-client-contract`「新增供應商的清單取代 config.yaml 的層層指標」：`config.yaml` 只指向本清單 |
| 02 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」 | 預定由 `04-add-gemini-provider` 改寫：加上 `LKAICore` 的 `package` 金鑰包裝型別，三個遵循保留 |

## 6. 下一家供應商（`04-add-gemini-provider`）已定好的事

使用者在 2026-11-22 為 Gemini 決定的事項，詳細依據見 `03-revise-chat-client-contract` 的 design Context。

**這一章的生命週期**：`04-add-gemini-provider` 封存時，把這一章的內容移進第 3 章的規則與第 4 章的對照表，清空這一章，章名改成再下一家供應商。

- **API**：使用 Interactions API 的 `v1`，不用 generateContent，也不用 `v1beta`。
- **回應保存**：預設送 `store: false`，App 可以在建立 client 時改成保存。
- **事件對應**：
  - 文字只取 `model_output` 步驟中 `delta.type` 為 `text` 的 `step.delta`。
  - 結束看 `interaction.completed` 的 `interaction.status`：`completed` 回報完成，`incomplete` 回報 `.maxOutputTokens`，其他狀態為錯誤。
  - 其餘事件一律略過，因為已經看到文件沒寫的事件名稱。
- **實際回應的模型**：取自 `interaction.completed` 的 `model`。
- **用量**：`outputTokens` 等於 `total_output_tokens` 加 `total_thought_tokens`；`reasoningOutputTokens` 為 `total_thought_tokens`；`inputTokens` 為 `total_input_tokens`；`cachedInputTokens` 為 `total_cached_tokens`。
- **錯誤**：
  - 要處理 Interactions 與 Google 通用兩種格式；Google 通用格式交給共同流程的預設狀態碼分類。
  - 串流錯誤的錯誤代碼是哪個欄位、資料缺到什麼程度算無法解碼，由 04 依兩種格式決定，寫進 04 的 spec。Google 通用格式的 `code` 是數字。
- **實際 API 測試**：用 `gemini-3.5-flash-lite`，只在設定 `LKAI_GEMINI_API_KEY` 時執行；只檢查回應的模型不是空字串，因為實測看到會換成別的模型。金鑰已存在 Keychain 的 `lkai-gemini-api-key`。
- **第一組任務**：
  - 與供應商無關的測試 helper 搬進 `LKAITestSupport`：`optionalField(_:_:)`、`jsonObject(from:)`、`jsonFragment(from:)`、`isInvalidResponse(_:)`，以及 Anthropic 與 OpenAI 錯誤測試都有的 `Expectation`（`.error`、`.invalidResponse(containing:)`）與 `matches(_:_:)`。
  - `LKAICoreTests` 的 `LKAIErrorTests` 也有一份同形狀的 `UnrecognizedStreamCase.Expectation`；`LKAICoreTests` 不依賴 `LKAITestSupport`（`01-extract-chat-stream-skeleton` 任務 4.3），要不要一併處理由 04 決定。
  - `LKAICore` 加一個 `package` 的金鑰包裝型別，它的 `description`、`debugDescription`、`customMirror` 都只給出遮蔽後的內容；三家 client 以它保存金鑰，只有組請求時讀原始值。三家原本的三個遵循保留。這會修改 02 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」，使用者已同意，由 04 的 design 記錄。以 Swift 6.4.2 實測，client 完全不寫三個遵循時，包裝型別也能讓三種描述與 `dump(_:)` 都不含金鑰。
- **不做的事**：`makeURLRequest(for:)` 與 `encodeBody(for:)` 不收進 `LKAICore`。02 設的條件是「Gemini 要統一加標頭或改編碼設定時再收」，Gemini 都不需要。
- **還沒實測、04 要確認的項目**：
  - 串流中途的 `error` 事件格式。
  - 被安全過濾擋下時的狀態碼與代碼。
  - 503 是否帶 `Retry-After`。
  - 輸入超過 context window 時 `v1` 回的狀態碼：如果是 500，預設分類會把它當成可重試，要評估是否在 Gemini 的錯誤對應中處理。

## 7. Open Questions 的對帳

三份封存 design 的 Open Questions，逐項標成「已解決」（附依據）、「屬於下一家」（見第 6 章）或「留給之後」。新的 change 留下 Open Questions 時，也加進這張表。

| 出處 | 項目 | 狀態 | 依據或之後的處理 |
| --- | --- | --- | --- |
| 第一份 | 輸入本身超過 context window 的 HTTP 400 要不要設專屬 case | 已解決：不設 | Anthropic 與 OpenAI 都沒有可辨識的代碼，02 設的條件「至少兩家可辨識」不成立（02「輸入超過 context window 的錯誤不設專屬種類」、03 Non-Goals）；Gemini 的實際狀態碼列在第 6 章待實測 |
| 第一份 | Gemini 用 generateContent 還是 Interactions API；`candidatesTokenCount` 是否不含思考 | 已解決 | 使用者選定 Interactions API 的 `v1`；用量改看 `total_*` 欄位，`total_output_tokens` 不含思考（03 Context 實測） |
| 第一份 | 調整 `LKAIKitInfo.version` 並打第一個 release tag | 留給之後 | 屬於版本與 release 流程，另行決定 |
| 第一份 | 抽出 `stream(_:)` 的共同骨架，並處理實作審查留下的四項 | 已解決 | `01-extract-chat-stream-skeleton` |
| 第一份 | 只 `import LKAIKit` 的使用端檢查 package | 留給之後 | 使用者決定延後到 BuyLedger 整合（02 Context） |
| 01 | `LKAIHTTPClient.makeLines(from:)` 的 task 寫法是否收進共用的建構方式 | 留給之後 | 等出現第二個建立逐行內容的地方 |
| 01 | 共同流程分支的測試長期放哪裡 | 已解決 | 02「共同流程的分支不在 OpenAI 的測試重寫一份」 |
| 01 | Gemini 沒有獨立的結束事件，用量可能漏掉 | 已解決 | Interactions API 有 `interaction.completed`，用量在裡面（03 Context 實測）；不必修改 `LKAIServerSentEventMapping` |
| 01 | `LKAITestWaiting.waitUntil(_:)` 之後要對同一個條件斷言；Anthropic 非串流取消測試少了這個斷言 | 留給之後 | 02 沒有寫取消測試；之後寫取消測試的 change，等待之後一律對同一個條件斷言，順手補上 Anthropic 那一處 |
| 01 | SSE 分框的測試 helper | 已解決 | 02「SSE 分框的測試 helper 搬進 LKAITestSupport」 |
| 01 | 金鑰遮蔽的三個遵循要每家各寫一次 | 已解決，04 再加強 | 02「金鑰遮蔽由每家 client 各自實作三個遵循」；04 加上包裝型別，見第 6 章 |
| 01 | Ollama 原生串流若為 NDJSON，要重用 `makeStream(for:)` 的步驟、只換分框方式 | 留給之後 | Ollama 的 change 查證並處理 |
| 02 | 輸入超過 context window 的 400 是否設專屬錯誤種類 | 已解決：不設 | 同第一份的同一項 |
| 02 | `max_output_tokens` 的最小值要不要加進共用的請求檢查 | 已解決：不加 | Gemini 只要求大於 0，和共用檢查相同（03 Context 實測）；只有 OpenAI 有最小值 16，由 API 檢查 |
| 02 | `OpenAI-Organization`、`OpenAI-Project` 標頭 | 留給之後 | 等使用端需要多個組織或專案時再加 |
| 02 | chat-client「Context window limit」要不要加上「供應商有回報時」的條件 | 已解決 | 03 修改 chat-client 的「Context window limit」 |
| 02 | 金鑰遮蔽改用 `LKAICore` 的 `package` 包裝型別 | 屬於下一家 | 04 的第一組任務，見第 6 章 |
| 02 | `makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 各寫一份 | 已解決：不收 | 02 的條件沒有成立，見第 6 章 |
| 02 | 與供應商無關的測試 helper 兩家各一份，Gemini 會是第三份 | 屬於下一家 | 04 的第一組任務，名單見第 6 章 |
| 02 | 503 的 `Retry-After` 沒有欄位可放 | 已解決 | 03「服務不可用的錯誤帶上等待時間，不給預設值」 |
| 02 | `LKAIError.refused(detail:)` 的說明沒有提到 detail 可能是模型寫的文字 | 已解決 | 03「refused 的 detail 說明補上隱私提醒」 |
| 02 | 串流 `error` 事件的欄位都是 Optional，沒有 `code` 也沒有 `message` 時當成可重試的 500 | 留給之後 | 使用者決定有實例時再改 spec；03 已在 openai-provider spec 寫明怎樣算可解碼 |
| 02 | 不認得的串流錯誤兩家結果不同，要不要訂共同規則 | 已解決 | 03「不認得的串流錯誤以 unrecognizedStreamError 統一回報」 |
| 02 | `config.yaml` 的新增供應商指標每多一家就多一層 | 已解決 | 03 建立本清單 |
