## Context

依 `docs/spectra/config.yaml` 的 API 演進規則，本 change 開始前讀了 `add-chat-abstraction-anthropic` 與 `01-extract-chat-stream-skeleton` 封存後的 design。

- **三家對照表的 OpenAI 一欄**：系統指示、訊息角色、輸出上限、串流格式、結束原因、拒答、金鑰無效、頻率限制、驗證標頭、實際回應的模型、token 用量，已逐列以 2026-11-22 的官方文件重新核對，結果記在下方。
  - 和對照表不同的地方：輸出上限有文件寫明的最小值 16。
  - 額度用完以 `error.code` 區分；舊表只寫 429。
  - 拒答或被擋：除了拒答內容與 `content_filter`，還有政策性阻擋的錯誤代碼，例如 `cyber_policy`、`misalignment_policy_violation`，舊表沒有列。
  - context window：生成途中塞滿 context window 時，回報的也是 `max_output_tokens`，沒有獨立的原因。
- **兩份 design 的 Open Questions 留給下一家供應商的項目**，在本 change 的處理方式：
  - 共同流程分支的測試長期放哪裡：見決策「共同流程的分支不在 OpenAI 的測試重寫一份」。
  - SSE 分框的測試 helper：見決策「SSE 分框的測試 helper 搬進 LKAITestSupport」。
  - 金鑰遮蔽的三個遵循：見決策「金鑰遮蔽由每家 client 各自實作三個遵循」。
  - 等待之後要斷言同一個條件：本 change 不寫取消測試。取消由共同流程負責，見前一個決策，所以沒有用到 `LKAITestWaiting`。
  - 輸入超過 context window 的 400 錯誤要不要專屬 case：見決策「輸入超過 context window 的錯誤不設專屬種類」。
  - 只 `import LKAIKit` 的使用端檢查 package：使用者已決定延後到 BuyLedger 整合，本 change 不做。
  - Gemini 的事件結束時機、Ollama 的 NDJSON、`makeLines(from:)` 的寫法：與 OpenAI 無關，留在原處。

**OpenAI Responses API 的查證**（2026-11-22，Context7 收錄的 OpenAI API 參考與官方指南；細節另以下載的參考頁面比對）：

- **請求**：
  - `POST https://api.openai.com/v1/responses`，標頭 `Authorization: Bearer <金鑰>` 與 `Content-Type: application/json`。
  - `input` 可以是訊息陣列；每則訊息是 `{"role": ..., "content": ...}`，`role` 可為 `user`、`assistant`、`system`、`developer`。`content` 可以是純文字，文件寫明「Can also contain previous assistant responses」。
  - `instructions`：「A system (or developer) message inserted into the model's context」。
  - `max_output_tokens`：包含可見輸出與推理 token 的上限，文件寫 `minimum 16`。
  - `stream` 預設 false；`store` 預設 true，「response data will be stored for at least 30 days」。
  - 推理模型在 effort 不是 `none` 時，文件要求不要送 `temperature`、`top_p`。
- **串流**：
  - 每則事件有 `event:` 一行與 `data:` 一行，`data` 是帶 `type` 欄位的 JSON。範例中也有 SSE 註解行 `: ...`。
  - 沒有 `[DONE]` 結尾。
  - 事件種類很多，包括生命週期、輸出項目、文字、拒答、推理摘要、工具呼叫、音訊；除了 `error`，名稱都以 `response.` 開頭。
  - **文字**：`response.output_text.delta` 的欄位是 `item_id`、`output_index`、`content_index`、`delta`、`sequence_number`、`logprobs`；文件另提到可能多一個 `obfuscation` 欄位。
  - **拒答**：
    - `response.refusal.delta` 帶 `delta`，`response.refusal.done` 帶完整的 `refusal`。
    - 官方的拒答範例中，回應的 `status` 仍是 `completed`，內容是 `{"type":"refusal","refusal":"I'm sorry, I cannot assist with that request."}`。
    - 文件對兩者只寫「Emitted when there is a partial refusal text」與「Emitted when refusal text is finalized」，沒有寫順序，也沒有保證至少有一則 delta。
  - **結束**：
    - `response.completed`、`response.incomplete`、`response.failed` 的 `data` 都是 `{"type", "response", "sequence_number"}`，`response` 是完整的回應物件。
    - SDK 範例把這三者與 `error` 視為結束。
  - **`error` 事件**：是平的 `{"type":"error","code":...,"message":...,"param":...,"sequence_number":...}`，`code` 可為 null。WebSocket 的 `error` 是巢狀格式，與本 change 無關。
- **回應物件**：
  - `status` 為 `completed`、`failed`、`in_progress`、`cancelled`、`queued`、`incomplete` 之一。
  - `model` 是實際產生回應的模型。
  - **`usage`**：
    - 欄位有 `input_tokens`、`input_tokens_details.cached_tokens`、`output_tokens`、`output_tokens_details.reasoning_tokens`、`total_tokens`。
    - 文件寫明「Cached tokens are included in `input_tokens`, and reasoning tokens are included in `output_tokens`」。
    - `response.created` 的 `usage` 為 null。
  - **`incomplete_details.reason`**：只有 `max_output_tokens`、`max_messages`、`content_filter`、`steered`；`steered` 只出現在 WebSocket。
    - 推理指南寫「If the generated tokens reach the context window limit or the `max_output_tokens` value you've set, you'll receive a response with a `status` of `incomplete` and `incomplete_details` with `reason` set to `max_output_tokens`」（Context7 guides/reasoning，規劃審查時 fable 指出，主對話重查確認）。
  - **`error`**：`{code, message, param?, type?}`，`code` 有 21 個值。
    - 一般：`server_error`、`rate_limit_exceeded`、`invalid_prompt`、`data_residency_mismatch`、`bio_policy`、`misalignment_policy_violation`、`vector_store_timeout`。
    - 其餘 14 個都和圖片有關，例如 `image_content_policy_violation`、`invalid_image`。
- **HTTP 錯誤**：
  - 內容格式是 `{"error": {"code", "message", "param", "type"}}`。
  - **429 的額度與帳務**：`credit_balance_exhausted`、`organization_spend_limit_exceeded`、`project_spend_limit_exceeded`、`organization_usage_limit_exceeded`。
    - 文件寫「For billing-related errors, inspect `error.code` … The broader `error.type` can still be `insufficient_quota`」，也寫重試不會恢復。
    - 頻率限制指南的範例另把 `insufficient_quota` 與 `billing_hard_limit_reached` 視為不可重試。
  - **429 的頻率限制**：「Rate limit reached for requests」（文件沒有寫 `code`），以及 `slow_down`（`type` 為 `rate_limit_error`）。
  - **503**：`server_is_overloaded`，`type` 為 `service_unavailable_error`。
  - **`Retry-After`**：只在暫時性的頻率限制與 503 過載時出現，單位是秒。
  - **政策性阻擋**（規劃審查時 fable 與 opus 指出，主對話以 Context7 重查確認）：
    - 資安檢查指南（guides/safety-checks/cybersecurity）：「If a request is classified as potentially suspicious you may receive an API error with the error code `cyber_policy`. For streaming requests, these errors may be returned in the midst of other streaming events.」
      - 超過門檻時，整個組織的模型存取會被暫停，請求同樣回 `cyber_policy`。
      - 文件沒有寫狀態碼。
    - misalignment 監測指南（guides/safety-checks/misalignment-monitoring）：「When misalignment monitoring blocks a request before streaming begins, the API returns HTTP `403`, with error type `invalid_request_error` and code `misalignment_policy_violation`.」
    - `bio_policy` 只出現在 `response.error.code` 的列舉，HTTP 狀態碼文件沒有寫。
  - **文件沒有寫明 `code` 或 `type` 的情況**：401（金鑰無效）、403（不支援的地區）、404（模型不存在）、500，以及關閉截斷時輸入超過 context window 的 400。頻率限制指南只提到 `model_not_found` 這個代碼，沒寫狀態碼。
- **模型**（官方模型頁）：
  - 目前的文字模型有 `gpt-6.2-astra`、`gpt-6.2-sol`、`gpt-6.1-terra`、`gpt-6-luna`，都是推理模型。
  - `gpt-6-luna` 最便宜（每百萬 token 輸入 $0.10、輸出 $0.50），預設推理 effort 為 `medium`。
  - `gpt-5-nano` 已列為淘汰。

**目前的程式碼**（2026-11-22 讀取 `main` 的 `fcb2c47`）：

- 以 SSE 串流的供應商遵循 `LKAIServerSentEventChatStreaming`，提供 `httpClient`、`makeURLRequest(for:)`、`httpError(statusCode:headers:body:)`、`makeEventMapper()`，`stream(_:)` 只寫 `makeStream(for: request)`。
- `LKAnthropicClient` 的結構可以照抄：
  - `public init(apiKey:urlSession:...)` 與給測試注入替身的 `package init(apiKey:httpClient:...)`。
  - `CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable` 三個遵循讓金鑰不出現。
  - 請求內容以明寫 `CodingKeys` 的 `Encodable` 型別編碼。
- `LKAIMessageRole` 只有 `user`、`assistant`，沒有 raw value，角色字串由各家自己對應。
- `LKAIError.retryDelay(from:)` 與 `LKAIError(httpStatusCode:retryAfter:)` 是 `package`，可以重用。
- SSE 分框的測試 helper `SSEEvent`（`name`、`data`）與 `lines(of:)` 寫在 `Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift`，Anthropic 的事件建構函式寫成它的 static 方法。
- 正式的 `LKAIServerSentEvent` 已有 `package init(event:data:)`，`event` 是 Optional。
- `LKAIError.refused(detail:)` 的公開說明寫 detail「只適合記錄 log，不適合依內容判斷」。
- `LKAIFinishReason.contextWindowExceeded` 的說明寫「目前只有 Anthropic 會回報這個狀態」，並預告其他供應商可能以 `.maxOutputTokens` 出現。
- **測試數**：2026-11-22 合併 PR #3 前量測，共 122 個：LKAICore 66、LKAIAnthropic 45、LKAIKitCLI 7、LKAIKit 2、LKAITestSupportTests 2。

## Goals / Non-Goals

**Goals:**

- App 只要 `import LKAIKit`，就能以 API 金鑰與 `URLSession` 建立 `LKOpenAIClient`，用同一組共用型別呼叫 OpenAI 的模型，串流與非串流都可以。
- OpenAI 的事件、結束原因、拒答、token 用量與錯誤，都對應到既有的共用型別，App 換供應商時不必改錯誤處理。
- 預設不讓 OpenAI 保存對話內容；App 需要時在建立 client 時明確開啟。
- 處理兩份封存 design 留給下一家供應商的項目，見 Context。

**Non-Goals:**

- 修改 `LKAICore` 的共用公開型別：依 `config.yaml`，供應商的 change 不為自己的格式修改它們，所以不新增錯誤種類與結束原因。唯一的例外是 `LKAIFinishReason` 兩個 case 的說明文字，只改文字、不改型別，見決策「Responses API 沒有 context window 的結束原因」。
- 修改 chat-client spec 的「Context window limit」需求：要另開 change，記在 Open Questions。
- 推理 effort、`reasoning` 摘要、`temperature` 等取樣參數：沿用 `add-chat-abstraction-anthropic` 的 Non-Goal「思考深度與推理設定……一律採用 API 預設值」。
- 工具呼叫、內建工具（web search、file search、code interpreter 等）、圖片與檔案輸入、結構化輸出、`previous_response_id` 與 conversation 物件、背景模式、WebSocket 模式。
- `OpenAI-Organization`、`OpenAI-Project` 標頭與自訂端點：端點固定為 OpenAI 官方網址。
- 在送出前檢查 `max_output_tokens` 的最小值，見決策「輸出上限照原樣送出，由 API 檢查最小值」。
- 共同流程的分支測試在 OpenAI 重寫一份，見決策「共同流程的分支不在 OpenAI 的測試重寫一份」。
- 只 `import LKAIKit` 的使用端檢查 package：使用者決定延後到 BuyLedger 整合。
- 自動重試、精確計費、`lkai` 的子指令、版本號與 release tag。

## Decisions

### LKOpenAIClient 照 LKAnthropicClient 的結構建立並遵循共同流程

`Sources/LKAIOpenAI/` 新增 `public struct LKOpenAIClient: Sendable`，結構與 `LKAnthropicClient` 相同：

- **建立方式**：
  - `public init(apiKey: String, urlSession: URLSession, shouldStoreResponses: Bool = false)`，以 `LKAIHTTPClient(session:)` 送出。
  - `package init(apiKey: String, httpClient: any LKAIHTTPClientProtocol, shouldStoreResponses: Bool = false)`，給測試注入替身。
- **共同流程**：
  - 遵循 `LKAIChatClientProtocol`，`stream(_:)` 只有 `makeStream(for: request)` 一行。
  - 遵循 `LKAIServerSentEventChatStreaming`：滿足要求的成員宣告為 `package`，`httpClient` 也是 `package`。
  - 不自行建立 `Task`。這依 `01-extract-chat-stream-skeleton` 的決策「SSE 對話的共同流程以 LKAIServerSentEventChatStreaming 的 extension 提供」，與 `config.yaml` 的規則。
- **金鑰**：`apiKey` 為 `private`，只放進 `Authorization` 標頭。
- **解碼**：OpenAI 的 JSON 鍵是 snake_case，一律用 `LKAISnakeCaseJSON` 解碼，依 `01-extract-chat-stream-skeleton` 的決策「snake_case JSON 的解碼設定收成 LKAISnakeCaseJSON」。
- **命名**：模組名 `LKAIOpenAI`，型別以 `LKOpenAI` 開頭，依 `add-swift-package-foundation` 的決策「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」。

考慮過的替代方案：讓 OpenAI 與 Anthropic 共用一個帶設定的 client 型別。兩家的請求、事件與錯誤格式完全不同，共用型別只會多出分支，否決。

### 回應保存由 App 在建立 client 時選擇，預設不保存

OpenAI 的 `store` 預設為 true，會保存回應至少 30 天。LKAIKit 每次都送出完整對話，不需要伺服器端保存。

- `LKOpenAIClient` 新增 `shouldStoreResponses`，預設為 false。
  - false 時，每個請求都送 `"store": false`。
  - true 時送 `"store": true`。
  - 「預設 false、App 可以開啟」是使用者在 2026-11-22 的決定。
- **命名**：依 ios-dev-kit `coding-style.md`，Bool 以 `should` 開頭的肯定斷言命名。
- **為什麼用 Bool**：只有兩種狀態，不像 Anthropic 的拒答備援需要帶模型清單，所以不另設 enum。
- **描述**：`description` 與 `customMirror` 帶這個設定，比照 `LKAnthropicClient` 帶 `refusalFallback`，讓 App 記錄 client 時看得出設定。
- **public init 的預設值也要有測試**：送出請求的測試只能經 `package init` 注入替身，驗不到 `public init` 自己的 `= false`。所以另以 `public init` 建立 client，檢查 `Mirror` 的 `shouldStoreResponses` 為 false（規劃審查時 opus 指出）。

考慮過的替代方案：

- **固定送 `store: false`，App 不能改**：最保護使用者的對話內容，但使用者決定保留彈性，否決。
- **不送 `store`，沿用 API 預設**：對話內容會被保存 30 天，App 開發者未必知道，否決。

### 送出 Responses API 的請求內容

`LKOpenAIResponsesRequestBody` 是明寫 `CodingKeys` 的 `Encodable`：

- `model`、`max_output_tokens`、`stream: true`、`store`。
- `instructions`：只在請求有系統指示時才送，沒有時不放這個鍵。
- `input`：每則訊息一個 `{"role", "content"}`，角色對應 `user`、`assistant`，`content` 是純文字，依原順序。
- 不送 `temperature`、`top_p`、`reasoning`，見 Non-Goals。

考慮過的替代方案：

- **只送一個字串的 `input`**：無法表達多輪對話，否決。
- **以 `system` 或 `developer` 角色的訊息放系統指示**：`instructions` 是頂層欄位，三家對照表也以頂層欄位表達系統指示，否決。

### 輸出上限照原樣送出，由 API 檢查最小值

`max_output_tokens` 的文件最小值是 16，而 `LKAIChatRequest.validate()` 只要求至少 1。

- 本 change 照原樣送出請求的值。
- 小於 16 時，由 API 回 4xx，經錯誤對應成帶 OpenAI 錯誤訊息的 `invalidRequest`。

考慮過的替代方案：

- **送出前在 `makeURLRequest(for:)` 擋下小於 16 的值**：API 調整最小值時，LKAIKit 會擋住合法的請求，或放過不合法的請求，否決。
- **自動調成 16**：App 拿到的輸出比要求的多，而且沒有任何提示，否決。

### OpenAI 串流事件的對應規則

`LKOpenAIStreamState` 遵循 `LKAIServerSentEventMapping`，事件種類以 `data` 的 `type` 判斷，不看 `event:` 行，與 Anthropic 相同。

| 事件 | 處理 |
| --- | --- |
| `response.output_text.delta` | 交出 `.textDelta(delta)` |
| `response.refusal.delta` | 累積到 delta 的拒答文字，不交出事件 |
| `response.refusal.done` | 累積到 done 的拒答文字，不交出事件 |
| `response.completed` | 拒答文字不為空時丟 `.refused(detail: 拒答文字)`；否則交出完成的 `.finished` |
| `response.incomplete` | 拒答文字不為空時丟 `.refused(detail: 拒答文字)`；否則依 `incomplete_details.reason` 對應，見決策「Responses API 沒有 context window 的結束原因」 |
| `response.failed` | 依 `response.error.code` 丟錯，見決策「錯誤依 error.code 與 error.type 分類」 |
| `error` | 依 `code` 丟錯，規則同上 |
| 其他所有種類，包括不認得的 | 不交出事件 |

- **拒答文字**：有任何 `response.refusal.delta` 時，以 delta 依序串接；一則 delta 都沒有時，改用 `response.refusal.done` 的 `refusal` 依序串接。
  - 文件沒有寫兩者的順序，也沒有保證至少有一則 delta（規劃審查時 opus 指出），所以兩種來源都要讀。
  - 只讀 delta 時，若 API 只送 done，拒答會被當成文字為空的完成，App 收不到任何錯誤。
- **解碼**：`data` 不是合法的 JSON，或認得的種類欄位格式不符時，丟 `.invalidResponse`，與 Anthropic 的 `Malformed stream event` 相同。丟錯之後的事件都不交出。
- **未知欄位**：解碼型別只宣告用得到的欄位，`obfuscation`、`logprobs` 這類欄位自動略過。
- **共同流程**：交出 `.finished` 或丟錯後立即停止讀取，沒有結束事件就丟 `.invalidResponse`。這兩點由共同流程處理，mapper 不必處理。

考慮過的替代方案：

- **把拒答文字當成一般文字交出**：App 會把拒答當成回答顯示，而 chat-client 的 Refusal 需求要求以拒答錯誤回報，否決。
- **只讀 delta**：理由見上方，否決。
- **在結束事件時，從 `response.output[].content[]` 的 `refusal` 片段取得**（fable 提出）：也可行，但要多解兩層巢狀欄位；`response.refusal.done` 已帶完整文字，所以否決。

### 拒答文字作為 refused 的 detail，content_filter 以固定字串表示

- 模型自己拒答時，OpenAI 送出拒答的內容，回應狀態仍是 `completed`。共用的 `refused(detail:)` 放這段拒答文字，例如「I'm sorry, I can't help with that.」。
- `response.incomplete` 的 `content_filter` 是被內容過濾擋下、沒有說明文字，`detail` 放 `content_filter`。
- 政策性阻擋的錯誤代碼（見決策「錯誤依 error.code 與 error.type 分類」）同樣回報 `refused`，`detail` 放代碼。
- **detail 的用途依 `LKAIError` 的公開說明**：只適合記錄 log，不適合依內容判斷，App 不應比對 `detail == "content_filter"`。
  - App 真的需要分辨拒答的種類時，要另開修改 chat-client 的 change，加上有型別的欄位（規劃審查時 fable 指出）。
- **隱私**：OpenAI 的 detail 是模型寫的文字，可能引用使用者的內容。`LKOpenAIClient` 的 `///` 寫明這一點，提醒 App 記錄 log 時留意。
- `detail` 在 Anthropic 是拒答類別、在 OpenAI 是說明文字或代碼，語意不同；chat-client 的需求只要求「carries the detail the provider gives」，兩者都符合。

考慮過的替代方案：拒答一律不帶 `detail`。會丟掉記錄 log 時唯一的線索，否決。

### Responses API 沒有 context window 的結束原因

- **輸出途中達到上限**：只有 `incomplete_details.reason` 為 `max_output_tokens` 一種，它對應 `.maxOutputTokens`。
- **生成途中塞滿 context window**：推理指南寫明同樣回報 `max_output_tokens`（見 Context），所以也對應 `.maxOutputTokens`，`LKOpenAIClient` 永遠不會回報 `.contextWindowExceeded`。
  - chat-client 的需求「Context window limit」要求這種情況以 context window exceeded 結束，而且「SHALL be distinct from max output tokens」。OpenAI 的回應分不出兩者，所以 `LKOpenAIClient` 做不到這條需求；openai-provider spec 寫明這個限制。
  - 修改 chat-client 的需求（例如加上「供應商有回報時」的條件）依 `config.yaml` 要另開 change，記在 Open Questions。
  - `LKAIFinishReason` 的 `.maxOutputTokens` 與 `.contextWindowExceeded` 說明只改文字：寫明 OpenAI 以 `.maxOutputTokens` 回報 context window 塞滿，App 在 OpenAI 上看到 `.maxOutputTokens` 時，調高輸出上限不一定有用。這是共用型別的說明，不改型別本身，所以不違反 `config.yaml` 的規則。
- **輸入就超過 context window**：預設的截斷設定為 `disabled` 時，API 在生成前回 400。
- **其他原因**：`max_messages`、`steered`，或沒有 `incomplete_details` 時丟 `.invalidResponse`。前者在本 change 的用法不會出現，後者只出現在 WebSocket。

### 錯誤依 error.code 與 error.type 分類

兩組代碼由 `LKOpenAIErrorBody` 各以一個函式判斷，HTTP 與串流兩條路徑共用，不寫兩份：

- **政策性阻擋的代碼**：`cyber_policy`、`bio_policy`、`misalignment_policy_violation`。對應 `.refused(detail: code)`，不可重試。
  - 依據見 Context：`cyber_policy` 會在 HTTP 或串流中途出現，`misalignment_policy_violation` 在串流開始前以 HTTP 403 回。
  - 兩條路徑都對應 `refused`，與 chat-client 的 Refusal 需求一致，App 換供應商時都得到拒答（規劃審查時 fable 與 opus 都列為必修）。
  - 組織因 `cyber_policy` 被暫停存取的情況，也一樣回報 `refused`：重點是不可重試，而且兩條路徑一致。
- **額度與帳務的代碼**：`insufficient_quota`、`billing_hard_limit_reached`、`credit_balance_exhausted`、`organization_spend_limit_exceeded`、`project_spend_limit_exceeded`、`organization_usage_limit_exceeded`。對應 `.quotaExceeded`，不可重試。
  - 共用的判斷函式只看 `code`。
  - 「`error.type` 為 `insufficient_quota`」只在 HTTP 規則判斷，因為串流的 `error` 事件沒有 `type` 欄位。

**HTTP 錯誤**（`httpError(statusCode:headers:body:)`，純函式），依序套用第一條符合的規則：

1. `error.code` 是政策性阻擋的代碼時，回報 `.refused(detail: code)`，不論狀態碼。
2. `error.code` 是額度與帳務的代碼，或 `error.type` 為 `insufficient_quota` 時，回報 `.quotaExceeded`，不論狀態碼，也不讀 `Retry-After`。
3. 其餘可解碼的內容，狀態碼是 401、402、403、429 以外的 4xx 時，回報 `.invalidRequest(message: error.message)`，讓 App 看得到 OpenAI 的說明，例如模型不存在、輸入太長。
4. 其他情況回傳 nil，由共同流程套用 chat-client 的預設狀態碼分類：
   - 401 是 `.invalidAPIKey`，403 是 `.permissionDenied`。
   - 429 是 `.rateLimited`，帶 `Retry-After` 的秒數。
   - 5xx 是 `.serviceUnavailable`。
   - 內容無法解碼時也走預設分類。
- **可解碼的定義**：內容有 `error` 物件就算可解碼。`LKOpenAIErrorBody` 的 `message`、`type`、`code` 都宣告為 Optional，所以缺 `message` 的 429 額度錯誤仍能判斷成 `.quotaExceeded`，不會落到可重試的 `.rateLimited`（規劃審查時 opus 指出）。

**串流中的 `error` 事件與 `response.failed`**（mapper）：

| `code` | 對應 |
| --- | --- |
| 政策性阻擋的代碼 | `.refused(detail: code)` |
| `rate_limit_exceeded`、`slow_down` | `.rateLimited(retryAfter: nil)`；串流中沒有標頭可讀 |
| 額度與帳務的代碼 | `.quotaExceeded` |
| `server_is_overloaded` | `.serviceUnavailable(statusCode: 503)` |
| `server_error`、`vector_store_timeout` | `.serviceUnavailable(statusCode: 500)` |
| `invalid_prompt`、`data_residency_mismatch` | `.invalidRequest(message: message)` |
| 其他不是 null 的代碼 | `.invalidResponse(reason:)`，說明帶 `code` 與 `message` |
| null，或 `response.failed` 沒有 `response.error` | `.serviceUnavailable(statusCode: 500)` |

- **不認得的代碼為什麼不當成 500**（規劃審查時 fable 指出）：
  - `response.error.code` 文件列的 21 個值只有 3 個是可重試的伺服器端問題，政策性阻擋這類新代碼多半不可重試。當成可重試的 500，App 會一直重送被擋下的請求。
  - `.serviceUnavailable` 不帶說明，App 的 log 分不出是 OpenAI 故障還是新代碼；`.invalidResponse` 的說明帶 `code` 與 `message`，之後要補對應時有線索。
  - Anthropic 把不認得的 `error.type` 當成 500，是因為它文件列的串流錯誤都是伺服器端問題，OpenAI 不是這樣。
- **null 為什麼仍當成 500**：沒有代碼時沒有任何線索可判斷，沿用 Anthropic 的處理。`code : string or null` 只出現在 `error` 事件；`response.failed` 沒有 `response.error` 時同樣處理。
- **圖片相關的代碼不列**：本 change 不送圖片，`image_content_policy_violation` 等不會出現，出現時以「其他不是 null 的代碼」處理。

考慮過的替代方案：

- **只依狀態碼分類**：429 會把額度用完當成可重試的頻率限制，App 會一直重試，否決。
- **依 `error.message` 的文字辨識**：OpenAI 文件提供穩定的 `code`，不必依賴說明文字，否決。
- **組織被暫停存取時回報 `.permissionDenied`**：同一個 `cyber_policy` 代碼在串流中與 HTTP 會得到不同種類，否決。

### 實際回應的模型與用量取自結束事件的 response 物件

`response.completed` 與 `response.incomplete` 的 `response` 是完整的回應物件，mapper 只在這時組出結束資訊：

- **實際回應的模型**：`response.model`，沒有時為 nil。
- **用量**：
  - 輸入總數是 `input_tokens`，快取讀取是 `input_tokens_details.cached_tokens`。
  - 輸出總數是 `output_tokens`，推理是 `output_tokens_details.reasoning_tokens`。
  - OpenAI 的總數本來就包含快取與推理，所以不必相加，與 chat-client 的 Token usage 口徑一致。
  - 細項沒有回報時為 nil。
  - `usage` 為 null，或缺少 `input_tokens`、`output_tokens` 其中一個時，沒有用量。
- `response.created` 的 `usage` 為 null，所以不從它讀取。

### 共同流程的分支不在 OpenAI 的測試重寫一份

這回答 `01-extract-chat-stream-skeleton` 的 Open Question「共同流程分支的測試長期放哪裡」：

- **哪些行為由共同流程負責**：請求驗證、送出時連線失敗、讀取錯誤內容時中斷、逐行讀取時中斷、沒有結束事件、交出結束事件後停止讀取、取消與釋放串流。
  - 這些行為已由 `LKAIAnthropicTests` 與 `LKAICoreTests` 的測試把關。
  - `LKAIOpenAITests` 不重寫一份。
- **OpenAI 的測試只測 OpenAI 自己的部分**：送出的請求、回應保存設定、事件對應、結束原因與拒答、用量與模型、錯誤分類、金鑰保密。
  - 這些測試都經過 `LKOpenAIClient.stream(_:)` 或 `invoke(_:)`，所以也間接確認 client 確實接上共同流程。
- **現有的測試不搬**：Anthropic 測試中標記 `spectra-scenario: chat-client` 的那些，以後共同流程改動時再一起處理。

考慮過的替代方案：

- **照抄一份到 OpenAI**：改一次共同流程就要改兩家的測試，否決。
- **現在把 Anthropic 的共同流程測試全部搬進 `LKAICoreTests`**：要改寫 14 行 chat-client 標記所在的測試，與本 change 無關，否決。

### SSE 分框的測試 helper 搬進 LKAITestSupport

這處理 `01-extract-chat-stream-skeleton` 的 Open Question「SSE 分框的測試 helper」：

- `Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift` 新增沒有 case 的 `package enum LKAIServerSentEventTestSupport`，只有一個成員：
  - `package static func lines(of events: [LKAIServerSentEvent]) -> [String]`。
  - 每個事件轉成 `event:`、`data:` 與一個空行；`event` 為 nil 時不輸出 `event:` 那一行。
- **直接使用正式的 `LKAIServerSentEvent`**（規劃審查時 fable 提出）：
  - 它已有 `package init(event:data:)`，`event` 是 Optional，不另設重複的事件型別。
  - 之後若某家的 SSE 沒有 `event:` 行，不必再改共用 helper。Gemini 是否如此尚未查證。
- **Anthropic 改用它**：
  - `LKAnthropicClientTestSupport` 移除自己的 `SSEEvent` 與 `lines(of:)`。
  - Anthropic 的事件建構函式改寫成 `extension LKAIServerSentEvent` 的 static 方法，放在原檔案。
  - `makeClient(events:)` 與各測試的呼叫處跟著修改。
  - 測試名稱、期望值與 spectra-scenario 標記都不變。
- **OpenAI 也用它**：OpenAI 的事件建構函式寫在 `LKOpenAIClientTestSupport` 對 `LKAIServerSentEvent` 的 extension。兩個 test target 不互相 import，同名的建構函式不會衝突。
- **命名**：依 ios-dev-kit `file-templates.md` 的 TestSupport 規則，對應的型別是 `LKAIServerSentEvent`。
- **測試**：`event` 為 nil 時不輸出 `event:` 行是新的分支，兩家目前的事件都走不到，所以在 `LKAITestSupportTests` 新增 `LKAIServerSentEventTestSupportTests` 涵蓋它。它會影響每家供應商的測試結論，符合 `01-extract-chat-stream-skeleton` 的決策「替身第二次 fetch 記錄測試失敗，並新增 LKAITestSupportTests」寫的收錄範圍。

考慮過的替代方案：

- **OpenAI 自己寫一份分框 helper**：兩家各一份，分框規則改動時要改兩處，否決。
- **另設 `Event(name:data:)` 型別**：與正式型別重複，而且 `name` 不是 Optional，否決。

### 金鑰遮蔽由每家 client 各自實作三個遵循

這處理 `01-extract-chat-stream-skeleton` 的 Open Question「金鑰遮蔽」：

- **`LKOpenAIClient` 照 `LKAnthropicClient` 實作三個遵循**：
  - `description` 只有型別名與 `shouldStoreResponses`。
  - `debugDescription` 等於 `description`。
  - `customMirror` 只放 `shouldStoreResponses`，不放金鑰與 HTTP client。
- **為什麼不能共用**：這三個是 `public` protocol 的要求。`add-chat-abstraction-anthropic` 的 Context 實測過：`public` protocol 的要求不能由 `package` extension 滿足，而改成 `public` extension 會把預設實作公開給 App。
- **漏寫的風險由測試擋**：`LKOpenAIClientTests` 依 spec 的 API key secrecy 需求，檢查三種輸出與 401 錯誤的描述都不含金鑰。漏了 `CustomReflectable` 時，`dump(_:)` 的斷言會失敗。

### 輸入超過 context window 的錯誤不設專屬種類

這回答 `add-chat-abstraction-anthropic` 的 Open Question：

- OpenAI 文件只寫輸入超過 context window 時「the request will fail with a 400 error」，沒有寫專屬的 `code`。
- 依決策「錯誤依 error.code 與 error.type 分類」，它回報為帶 OpenAI 說明的 `.invalidRequest(message:)`。
- 新增專屬錯誤種類要改 `LKAIError` 與 chat-client spec，依 `config.yaml` 需另開 change，而且至少要兩家都有可辨識的代碼才有意義。這一點仍留在 Open Questions。

### 實際 API 測試以 gpt-6-luna 執行，由 owner 手動跑

`LKOpenAIClientLiveTests` 照 `LKAnthropicClientLiveTests` 的寫法：

- **何時執行**：只在環境變數 `LKAI_OPENAI_API_KEY` 存在時執行，否則顯示為略過。金鑰只從環境變數讀取，不寫進程式碼與輸出。
- **模型**：`gpt-6-luna`。這是使用者在 2026-11-22 的決定，也是文件列出的最便宜的文字模型。
- **請求**：要求只回一個詞，串流與非串流各一個測試，檢查以完成結束、文字去掉空白後不為空。
- **輸出上限**：4096。`gpt-6-luna` 是推理模型，推理 token 也算在 `max_output_tokens` 內。文件提醒達到上限時可能還沒有任何可見輸出，所以取和 Anthropic 實際 API 測試相同的值。
  - 這是估計值，沒有量測：一個詞的回答在預設 effort `medium` 下用不到這麼多。
  - 以 owner 實跑時 `usage` 的 `reasoning_tokens` 確認。
- **金鑰的存放**：owner 照 Anthropic 的做法，把金鑰放進 Keychain 的 service `lkai-openai-api-key`，執行時再以 `security find-generic-password` 讀進環境變數。

### 型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加

沿用 `add-chat-abstraction-anthropic` 的決策「型別依 ios-dev-kit 樣板建立」與「測試 target 依受測 target 增加 LKAIAnthropicTests」：

- 新增測試 target `LKAIOpenAITests`，依賴 `LKAIOpenAI`、`LKAICore`、`LKAITestSupport`。
- `LKAIKit` 依賴 `LKAIOpenAI`，`Sources/LKAIKit/Exports.swift` 加一行 `@_exported import LKAIOpenAI`。
- `LKAIKitTests` 加一個透過 `LKAIKit` 建立 `LKOpenAIClient` 的測試，比照 Anthropic 那一個。

### config.yaml 的指標加上本 change

`docs/spectra/config.yaml` 的 API 演進規則目前只指向前兩份 design。本 change 封存後，兩份的內容有幾處過時（規劃審查時 fable 指出）：

- 01 的 Open Questions 中，有三項本 change 已決定：共同流程分支的測試位置、SSE 分框的測試 helper、金鑰遮蔽。
- 三家對照表的 OpenAI 一欄，本 change 的 Context 有更新的查證。

所以比照 `01-extract-chat-stream-skeleton` 的決策「config.yaml 的指標改為同時指向本 change」，把那一條改為：

> 新增供應商的 change 開始前，先讀 add-chat-abstraction-anthropic、01-extract-chat-stream-skeleton 與 02-add-openai-provider 封存後的 design：逐列核對第一份 Context 的三家對照表（OpenAI 一欄以 02 的 Context 為準），並處理三者 Open Questions 留給下一家供應商的項目。以 SSE 串流回答的供應商一律遵循 `LKAIServerSentEventChatStreaming`，不自行建立 `Task`。第一份的「生產端 task 的擁有權」、「`LKAITestSupport` 不設測試 target」與 Open Questions 的抽出共同流程一項，以 01 為準；01 的 Open Questions 中共同流程分支的測試位置、SSE 分框的測試 helper、金鑰遮蔽三項，以 02 為準。

考慮過的替代方案：修改封存的 design。封存的內容記錄當時的決定，不回頭改，否決。

### 平行實作沿用兩個 git worktree

沿用 `01-extract-chat-stream-skeleton` 的決策「平行實作沿用兩個 git worktree」，worktree 放 `.worktrees/sonnet` 與 `.worktrees/haiku`，由主對話建置、測試與合併。

- **sonnet**：做 `LKAIOpenAI` 的原始碼與 `LKAIOpenAITests` 的對應測試（第 2 組），依序是：
  1. 模組、client、請求與回應保存設定、金鑰保密。
  2. 文字、完成、模型與用量。
  3. 未完成與拒答。
  4. 錯誤。
- **haiku**：
  - 先把 SSE 分框 helper 搬進 `LKAITestSupport`（第 1 組）。
  - 再寫實際 API 測試（第 3 組）。
- **為什麼這樣分**：OpenAI 的五個原始碼檔案彼此依賴，交給同一位實作者依序做，避免兩人改同一個檔案。
- **檔案不重疊**：haiku 的搬移只改 `Sources/LKAITestSupport`、`Tests/LKAIAnthropicTests` 與 `Tests/LKAITestSupportTests`，sonnet 都不碰。實際 API 測試是 `Tests/LKAIOpenAITests` 內單獨一個檔案。
- **主對話**：做 `config.yaml` 的指標（3.2）、驗收與 owner 的實際 API 測試紀錄（第 4 組）。

## Implementation Contract

**App 看得到的行為**：

- **建立**：`import LKAIKit` 之後可以建立 `LKOpenAIClient(apiKey:urlSession:shouldStoreResponses:)`，`shouldStoreResponses` 預設 false，存成 `any LKAIChatClientProtocol` 使用。
- **呼叫**：串流與非串流的事件、結束原因、拒答、用量、實際回應的模型與錯誤，依 `openai-provider` spec 與 chat-client spec。
- **不變的部分**：`LKAnthropicClient` 的行為與既有的公開 API 都不變。

**新檔案的建立方式**：

| 檔案 | 建立方式 |
| --- | --- |
| `LKOpenAIClient.swift` | 比照 `LKAnthropicClient.swift` 的結構與 MARK 分區 |
| `LKOpenAIResponsesRequestBody.swift`、`LKOpenAIStreamEvent.swift`、`LKOpenAIErrorBody.swift` | 比照 Anthropic 對應的檔案 |
| `LKOpenAIStreamState.swift` | 比照 `LKAnthropicStreamState.swift`：遵循 `LKAIServerSentEventMapping`，private 方法依呼叫者在前、深度優先排列 |
| `LKAIServerSentEventTestSupport.swift`、`LKOpenAIClientTestSupport.swift` | ios-dev-kit `tests/Tests.swift` 一節的 TestSupport 規則 |
| `LKOpenAIClient*Tests.swift` | `tests/Tests.swift` |

**完成後的狀態**（grep 與 `dump-package` 確認）：

- **`Task {`**：`Sources/LKAIOpenAI/` 內沒有，背景 task 仍只在 `LKAICore` 的兩處建立。
- **`JSONDecoder()`**：`Sources/LKAIOpenAI/` 內沒有，解碼一律經 `LKAISnakeCaseJSON`。
- **依賴方向**：`LKAIOpenAI` 只依賴 `LKAICore`；`LKAIKit` 依賴 `LKAICore`、`LKAIAnthropic`、`LKAIOpenAI`；products 仍只有 `LKAIKit` 與 `lkai`；`LKAITestSupport` 仍不在 product 內。
- **Anthropic 的測試**：`LKAnthropicClientTestSupport` 不再有 `SSEEvent` 與 `lines(of:)`。
- **`LKAIServerSentEventTestSupport`**：只有 `lines(of: [LKAIServerSentEvent])`，沒有另設的事件型別。
- **`LKAIFinishReason`**：`.maxOutputTokens` 與 `.contextWindowExceeded` 的說明寫明 OpenAI 以 `.maxOutputTokens` 回報 context window 塞滿；型別與 case 不變。
- **`docs/spectra/config.yaml`**：API 演進規則的指標等於決策「config.yaml 的指標加上本 change」引用的文字。

**驗收（主對話執行）**：

- **建置與測試**：`swift package clean` 後 `swift build` 與完整 `swift test` 零警告。
  - LKAIAnthropic 仍是 45 個，名稱與期望值不變。
  - LKAIKit 為 3 個，LKAITestSupportTests 為 3 個。
  - LKAIOpenAI 的測試數以實際為準，估計約 19 個，含 2 個沒有金鑰時略過的實際 API 測試。這是依 spec 的情境數估計的，以驗收時的 `swift test` 輸出確認。
- **spectra-scenario 標記**：
  - 修改前已有的 93 行（2026-11-22 於 `fcb2c47` 以 `git grep` 計數）仍逐行存在。
  - 新增的行都是 `spectra-scenario: openai-provider / ...`。
  - `spectra coverage` 顯示 `openai-provider` 的每個情境與範例都有測試。
- **`swift package dump-package`**：符合上一節的依賴方向。
- **XcodeBuildMCP（iOS 26 模擬器）**：
  - `LKAIKit` scheme 建置成功、零警告。
  - `LKAIKit-Package` 建置測試只有既有的 `LKAICommandTests.swift` 的 `Process` 錯誤。
- **反向檢查**：每項都暫時改壞、觀察到測試失敗後還原。

| 暫時改壞的地方 | 預期失敗的測試 |
| --- | --- |
| `shouldStoreResponses` 為 false 時送 `store: true` | 回應保存設定的測試 |
| 沒有系統指示時仍送 `instructions` | 省略 `instructions` 的測試 |
| `response.refusal.delta` 當成文字交出 | 結束事件範例表的拒答列、非串流拒答的測試 |
| `content_filter` 對應成完成 | 結束事件範例表的 `content_filter` 列 |
| 額度與帳務的代碼改走預設分類 | HTTP 錯誤範例表的額度列 |
| HTTP 規則拿掉「`error.type` 為 `insufficient_quota`」 | HTTP 錯誤範例表 `code` 為 null 的額度列 |
| 政策性阻擋的代碼改走狀態碼規則 | HTTP 錯誤範例表的 `misalignment_policy_violation` 與 `cyber_policy` 兩列 |
| 忽略 `error` 事件 | 串流 `error` 事件的測試 |
| 解碼失敗改成略過該則事件 | 格式錯誤的事件資料的測試 |
| 不認得的 `incomplete_details.reason` 改成略過 | 結束事件範例表的 `max_messages` 與沒有 `incomplete_details` 兩列 |
| 拒答文字只讀 delta | 結束事件範例表只有 `response.refusal.done` 的那一列 |
| `public init` 的 `shouldStoreResponses` 預設為 true | 以 URL session 建立、不帶保存設定的情境 |
| `description` 含金鑰 | 金鑰保密的測試 |

- 格式錯誤的事件資料的測試在 2.1 的骨架上就會通過：事件對應全部回傳空陣列時，共同流程讀完會丟 `.invalidResponse`，也沒有交出文字。所以它看不到 RED，改由上表的反向檢查把關。

- **實際 API**：owner 以自己的金鑰執行 `swift test --filter LKAIOpenAITests`，兩個實際 API 測試都要執行並通過，結果記在任務 4.2。

## Risks / Trade-offs

- [OpenAI 之後新增或改名錯誤代碼] → 不會無聲吞掉錯誤：HTTP 錯誤依狀態碼走預設分類；串流中不認得的代碼回報不可重試的 `.invalidResponse`，說明帶 `code` 與 `message`。代價是新的「可重試」代碼也會被當成不可重試，App 從說明裡的代碼可以看出原因，之後再補對應。
- [文件沒寫 401、403、404 與 context window 的 `code`] → 這些情況依狀態碼分類，或帶 OpenAI 的說明；spec 範例中這幾列的錯誤內容是依常見格式擬的測試資料，分類結果不依賴其中的 `code`。
- [拒答的 `detail` 是模型寫的文字，可能很長，也可能引用使用者的內容] → 依 `LKAIError` 的公開說明只供記錄 log；`LKOpenAIClient` 的 `///` 提醒記錄時留意隱私。
- [`max_output_tokens` 小於 16 時，App 要到 API 回錯才知道] → 錯誤帶 OpenAI 的說明；之後若有多家都有最小值，再考慮在共用的檢查加規則。
- [推理模型的推理 token 佔用 `max_output_tokens`] → App 需要設夠大的輸出上限；OpenAI 會以 `max_output_tokens` 的未完成原因回報，App 可以從 `maxOutputTokens` 的結束原因得知。
- [拒答文字來自 delta 或 done] → 兩種來源都讀，只送其中一種也能回報拒答。兩種都沒有、拒答只出現在 `response.output` 時，`response.completed` 會被當成完成；文件的事件說明顯示拒答會以這兩種事件送出，所以目前不讀 `response.output`。
- [SSE 分框 helper 搬移會改到 Anthropic 的四個測試檔] → 只改 helper 的型別與呼叫處，主對話以測試名稱、期望值與 spectra-scenario 標記不變把關。四個檔案是 `LKAnthropicClientTestSupport`、`LKAnthropicClientStreamTests`、`LKAnthropicClientErrorTests`、`LKAnthropicClientCancellationTests`（2026-11-22 grep）。

## Open Questions

- 輸入超過 context window 的 400 是否設專屬錯誤種類：
  - Anthropic 與 OpenAI 目前都沒有文件化的專屬代碼。
  - 等 Gemini 的 change 查證後，若至少兩家可辨識，再另開修改 chat-client 的 change。
- `max_output_tokens` 的最小值：若之後其他供應商也有最小值，再評估是否加進共用的請求檢查。
- `OpenAI-Organization`、`OpenAI-Project` 標頭：等使用端需要多個組織或專案時再加。
- chat-client 的「Context window limit」需求要不要加上「供應商有回報時」的條件：OpenAI 分不出 context window 塞滿與輸出上限，見決策「Responses API 沒有 context window 的結束原因」。要改 chat-client spec，依 `config.yaml` 另開 change，可以和 Gemini 的查證一起決定。
- 金鑰遮蔽的另一條路（fable 提出，未實測）：在 `LKAICore` 加一個 `package` 的金鑰包裝型別，它自己的 `description`、`debugDescription`、`customMirror` 都遮蔽，client 以它存金鑰，漏寫遵循也印不出金鑰。會動到 `LKAnthropicClient`，Gemini 的 change 時評估。
- `makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 在 Anthropic 與 OpenAI 各寫一份：兩家可以接受；Gemini 時若要統一加標頭或改編碼設定，再收進 `LKAICore`。
