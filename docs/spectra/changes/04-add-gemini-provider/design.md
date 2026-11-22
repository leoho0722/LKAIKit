## Context

LKAIKit 目前有 Anthropic（`LKAIAnthropic`）與 OpenAI（`LKAIOpenAI`）兩家供應商，都遵循 `LKAICore` 的 `LKAIServerSentEventChatStreaming` 共同流程。`03-revise-chat-client-contract` 先修改了共同規則，並建立 `docs/adding-a-provider.md`。依 `config.yaml` 的指標，這個 change 開始前已讀完該清單，下面依清單第 2 章「開始前要做的事」逐項記錄。

**查證方式**（2026-11-22，主對話）：

- 官方文件：Context7 收錄的 `ai.google.dev/gemini-api/docs`，包含 api-errors、safety-settings、streaming、thinking、long-decode、background-execution、text-generation。thinking 頁與 get-started 頁是規劃審查時查到的。
- 實際請求：以 owner 的金鑰（Keychain service `lkai-gemini-api-key`，`AQ.` 開頭的新格式，53 字元）送出：
  - 會產生 token 的請求 3 次：`gemini-3.5-flash-lite` 的完成與達到上限兩次串流，以及 Gemma 的一次短請求。
  - 免費的查詢：模型資訊、模型清單、countTokens。
  - 會被拒絕、不產生 token 的請求：429、400、404，以及錯誤金鑰與沒帶金鑰的請求。錯誤金鑰的請求帶的是隨機產生的假金鑰，沒有用到 owner 的金鑰。
- 費用估計不到 0.001 美元：會產生 token 的三次合計不到 100 個 token。這是依用量回報與價格表估的，沒有對帳單核對。

**對照表第 4 章 Gemini 一欄的重新核對**（標「實測」的是本次的實際請求，標「03」的是 `03-revise-chat-client-contract` Context 記錄的實測，標「文件」的只依官方文件）：

| 項目 | 結果 |
| --- | --- |
| 端點、標頭、請求內容 | 與 03 相同。本次再以 `system_instruction`、`generation_config.max_output_tokens`、`store: false`、`stream: true` 送出串流請求，都被接受（實測） |
| 串流事件 | 依序為：`interaction.created`（帶 `interaction.model`）、`interaction.status_update`（`status` 為 `in_progress`）、`thought` 步驟、`model_output` 步驟、`interaction.completed`，最後是 `event: done` 與 `data: [DONE]`（實測）。`thought` 步驟有 `step.start`、只帶 `signature` 的 `step.delta`（`delta.type` 為 `thought_signature`）與 `step.stop`。`model_output` 步驟的 `step.delta` 帶 `delta.type: "text"` 與 `delta.text`。每則事件的 SSE `event:` 名稱都和 `data` 的 `event_type` 相同。文件的兩個範例不一致：streaming 頁的 `step.start` 只有 `type`，和實測相同；thinking 頁的範例把 `model_output` 的第一段文字放在 `step.start` 的 `step.content`（`[{"text":"Based on the clues provided, here","type":"text"}]`），`thought` 的摘要放在 `step.start` 的 `summary`（文件）。streaming 頁另寫明「The step type determines which delta types to expect」，思考步驟的片段類型是 `thought_signature` 與 `thought_summary` |
| 結束 | `interaction.completed` 的 `interaction.status` 為 `completed` 或 `incomplete`（實測）。文件列的終止狀態還有 `failed`、`requires_action`、`cancelled`（文件，long-decode 與 background-execution）。`failed` 時錯誤放在 `interaction.errors`，但文件只在背景執行的說明提到這點；串流時，錯誤以 `error` 事件送出（文件，safety-settings）。欄位名稱的說法不一致：safety-settings 的文字與 Go 範例是 `errors`，get-started 的 Python 範例讀的是 `result.error`（文件） |
| 達到輸出上限 | `incomplete` 沒有附原因；`max_output_tokens` 為 20 時，`total_output_tokens` 回報 23，比上限多（實測）。Gemma 的輸出上限 16 全用在思考時，回 `incomplete`，`steps` 只有 `thought`，沒有文字（實測，非串流） |
| 用量 | 欄位與 03 相同，另外還有 `input_tokens_by_modality`、`total_tool_use_tokens`、`initial_input_tokens`（實測）。本 change 不使用這三個欄位 |
| 實際回應的模型 | `interaction.created` 與 `interaction.completed` 都帶 `interaction.model`（實測）；請求 `gemini-3.5-flash` 時回 `gemini-3.6-flash`（03）。thinking 頁的範例只有 `interaction.created` 帶 `model`，`interaction.completed` 沒有（文件），和實測不同 |
| 429 | Interactions 格式：`{"error":{"message":"Rate limit exceeded …","code":"too_many_requests"}}`，帶 `retry-after` 標頭，值是秒數（實測：27、72177）。串流請求被限流時，同樣在串流開始前回 HTTP 429（實測） |
| 參數錯誤 | 串流請求的 `max_output_tokens` 為 10000000 時回 HTTP 400 `invalid_request`；模型不存在時回 HTTP 404 `not_found`（實測），都在串流開始前回報 |
| 金鑰錯誤 | 錯誤的 `AIza` 格式金鑰（Google 舊格式）回 **400** Google 通用格式，`status` 為 `INVALID_ARGUMENT`，`details` 的 `ErrorInfo.reason` 為 `API_KEY_INVALID`（實測）。錯誤的 `AQ.` 格式金鑰回 401 `UNAUTHENTICATED`，`reason` 為 `ACCESS_TOKEN_TYPE_UNSUPPORTED`（實測，與 03 相同）。沒帶金鑰時回 403 `PERMISSION_DENIED`，`reason` 為 `ACCESS_DENIED`（實測）。三者都外包一層 JSON 陣列，串流與非串流請求的結果相同 |
| 生成被擋下 | HTTP 400，`code` 為 `safety`、`jailbreak`、`prohibited_content` 或 `blocklist`；串流時以 `error` 事件送出（文件，safety-settings）。api-errors 的「Generation blocked codes」另列 `recitation`、`language`、`spii`、`content_blocked` 與四個 `image_*` 代碼（文件）。沒有實測：要觸發安全過濾，得送出真的有害的內容，所以不測 |
| 串流中途的 `error` 事件 | 格式是 `{"error":{"message","code"},"event_type":"error"}`，例子是 `gateway_timeout`「Deadline expired before operation could complete.」（文件，streaming）。`gateway_timeout` 不在錯誤代碼表，是文件說的「沒列出的代碼改用 HTTP 狀態的 snake_case 名稱」。沒有實測：無法以正常請求觸發 |
| 輸入超過 context window | 沒有測成。`gemini-3.5-flash-lite` 的 `inputTokenLimit` 是 1048576（實測），Gemma 4 26B 是 262144；以 30 萬 token 測 Gemma 時，先撞到免費方案每分鐘 16000 個輸入 token 的限制，回 429（實測）。generateContent 的錯誤表把這種情況列在 500 `INTERNAL`（文件） |

**清單第 6 章與第 7 章中屬於 Gemini 的項目**：

- 第 6 章已定好的事，除了下面這一項，都照做，見 Decisions：
  - 「Google 通用格式交給共同流程的預設狀態碼分類」因上表「金鑰錯誤」的實測而修改，使用者在 2026-11-22 同意，見決策「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」。
- 第 6 章「還沒實測」的四項：
  - 串流中途的 `error` 事件格式：依文件寫進 spec，見上表。
  - 被安全過濾擋下時的狀態碼與代碼：依文件寫進 spec，見上表。
  - 429 與 503 的等待時間：429 在 `retry-after` 標頭，由共同流程的預設分類讀取。503 沒有遇到；預設分類同樣讀標頭。
  - 輸入超過 context window 的狀態碼：沒有測成，使用者在 2026-11-22 決定記成風險、不特別處理，見決策「輸入超過 context window 不特別處理」。
- 第 7 章屬於 Gemini 的兩項，都在本 change 的第一組任務：
  - 「金鑰遮蔽改用 `LKAICore` 的 `package` 包裝型別」。
  - 「與供應商無關的測試 helper 兩家各一份」。

**目前的程式碼**（2026-11-22 讀取 `main` 的 `02002e3`）：

- `LKAnthropicClient` 與 `LKOpenAIClient` 都以 `private let apiKey: String` 保存金鑰，各自實作 `CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable`，`customMirror` 只放設定。
- 與供應商無關的測試 helper 各有兩份：
  - `jsonObject(from:)`（文字與 `Data` 兩個版本）與 `jsonFragment(from:)` 在 `LKAnthropicClientTests`、`LKOpenAIClientTests` 的 private extension。
  - `optionalField(_:_:)` 在兩家 `LKAIServerSentEvent+…Events.swift` 的 private extension。
  - `Expectation` 與 `matches(_:_:)` 在 `LKAnthropicClientErrorTests`、`LKOpenAIClientErrorTests`，兩份程式碼相同，只有說明不同：Anthropic 的 `containing` 多寫了「傳空陣列表示不比對說明文字」。
  - `isInvalidResponse(_:)` 在 `LKAnthropicClientStreamTests`、`LKOpenAIClientStreamTests`。
  - 確認請求內容的 JSON 布林：`LKOpenAIClientTests` 的 `BooleanFlagsBody` 與 `decodeBooleanFlags(of:)`（`stream`、`store`），`LKAnthropicClientTests` 的 `StreamFlagBody` 與 `decodeStreamFlag(of:)`（`stream`）。它們存在的原因是 `NSDictionary` 比對會把 `1` 當成 `true`（第一份 design 的實測）。
  - `LKOpenAIClientStreamTests` 另有 `ErrorExpectation`（`.error` 與不帶值的 `.invalidResponse`）。
  - `LKAICoreTests` 的 `LKAIErrorTests.UnrecognizedStreamCase.Expectation` 是第三份同形狀的型別；`LKAICoreTests` 不依賴 `LKAITestSupport`（01 的決策「Anthropic 的測試走不到的共同行為在 LKAICoreTests 直接測試」）。
- `LKAITestSupport` 已 `import Testing`，`LKAIMockHTTPClient` 以 `Issue.record` 記錄測試問題。
- 共同流程的 `relayEvents(from:yield:)` 交出 `.finished` 後立即停止讀取，所以 `interaction.completed` 之後的 `event: done` 與 `data: [DONE]` 不會交給 mapper。`LKAIServerSentEventParser` 略過 `:` 開頭的註解行，`: keep-alive` 不會變成事件。
- `LKAIChatRequest.validate()` 已擋下 `maxOutputTokens` 小於 1 的請求；Gemini 只要求大於 0（03 實測），不必另外檢查。

## Goals / Non-Goals

**Goals:**

- 新增 `LKAIGemini` 與 `LKGeminiClient`，以 Gemini Interactions API `v1` 履行 chat-client 的約定，App 只要 `import LKAIKit` 就能使用。
- 金鑰遮蔽改由 `LKAICore` 的 `package` 包裝型別保證，三家 client 都改用它；三家原本的三個遵循保留。
- 與供應商無關的測試 helper 收進 `LKAITestSupport`，Anthropic、OpenAI 與 Gemini 三個供應商的測試 target 共用同一份。
- `docs/adding-a-provider.md` 更新成 Gemini 實作後的狀態。

**Non-Goals:**

- 思考深度、取樣參數與工具呼叫：依清單第 3 章，一律用 API 的預設值；`requires_action` 只當成不認得的結束狀態。
- 以 `previous_interaction_id` 接續對話、背景執行與取消：本套件每次都送出完整的對話歷史，與另外兩家相同。
- 輸入超過 context window 的專屬錯誤種類：沒有實測到 Gemini 的狀態碼，見決策「輸入超過 context window 不特別處理」；`03-revise-chat-client-contract` 的 Non-Goals 也已寫明不新增 case。
- 解析 Google 通用格式 `details` 裡除了 `ErrorInfo.reason` 為 `API_KEY_INVALID` 以外的內容，例如 `RetryInfo`：本次實測的 429 都是 Interactions 格式，等待時間在標頭。
- 修改 chat-client、anthropic-provider、openai-provider spec：金鑰包裝型別與 helper 的搬移都不改變可觀察的行為。
- 把三家的 `makeURLRequest(for:)` 網址檢查與 `encodeBody(for:)` 收進 `LKAICore`：沿用 02 設的條件「要統一加標頭或改編碼設定時再收」，Gemini 兩者都不需要（清單第 6 章）。本 change 之後是三份，條件成立時再收。

## Decisions

### 以 Interactions API v1 實作，串流與非串流都送 stream: true

- 使用者已選定 Interactions API 的 `v1`（清單第 6 章）。文件範例全用 `v1beta`，而 `v1beta` 在 2026 年 5 月改過一次結構；`v1` 的請求與串流都已實測。
- 非串流呼叫由 `LKAIChatClientProtocol` 的預設實作彙整串流，與另外兩家相同，所以只有一條請求路徑。
- 請求內容：
  - `input` 是步驟陣列：使用者的訊息是 `user_input`，助理的訊息是 `model_output`，`content` 是 `[{"type":"text","text":…}]`。
  - `system_instruction` 是純文字，只在有系統指示時送。
  - `generation_config` 只放 `max_output_tokens`，照原樣送出。
- 不送 `temperature`、`top_p`、`top_k`：清單第 3 章規定一律用 API 的預設值；文件也寫 Gemini 4 與 3.6 以上的模型會忽略這些參數。

### 回應保存預設關閉，由 App 建立 client 時開啟

- 依清單第 3 章「有伺服器端保存的供應商預設不保存」，以及 02 的決策「回應保存由 App 在建立 client 時選擇，預設不保存」：`store` 預設為 true，付費方案保存 55 天（文件），所以本套件預設送 `store: false`。
- 參數名稱與 OpenAI 相同，都是 `shouldStoreResponses`，App 換供應商時寫法一致。

### 文字只取 model_output 步驟的 text 片段，步驟類型依 step.start 的 index 記錄

- `step.delta` 本身不帶步驟類型，只帶 `index`；要知道它屬於 `thought` 還是 `model_output`，得記住 `step.start` 的 `index` 與 `step.type`。這個狀態由 mapper 持有，符合 01 的決策「每條串流的事件狀態與結束判斷由供應商的 mapper 持有」。
- 只把 `model_output` 步驟中 `delta.type` 為 `text` 的片段交出：思考步驟的 `thought_signature` 與 `thought_summary` 不是給使用者看的文字。
- `model_output` 的 `step.start` 帶 `step.content` 時，依序交出其中 `type` 為 `text` 的文字：thinking 頁的範例把回答的第一段放在這裡，實測沒有看到，但不處理的話回答開頭會被無聲丟掉。API 沒送時沒有任何作用；`thought` 的 `step.start` 帶的 `summary` 不交出。
- 沒有 `step.start` 記錄過的 `index`，片段不交出，因為不知道它是什麼步驟。
- 事件種類以 `data` 的 `event_type` 為準，不看 SSE 的 `event:` 名稱，與 OpenAI 讀 `type` 相同。
- 其餘事件一律略過：已經看到文件沒寫的事件名稱（03 Context：文件寫的 `interaction.in_progress` 實際是 `interaction.status_update`）。
- **否決：依 `delta.type` 判斷，不記錄步驟**：文件寫思考步驟的片段類型是 `thought_signature` 與 `thought_summary`，但思考摘要之後若也以 `text` 類型、帶著文字送出，只看 `delta.type` 會把思考內容無聲地當成回答交出。記錄步驟類型時，這種片段會被略過；它沒有字串 `text` 時，依決策「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」的簡化規則會讓串流失敗，見 Risks。

### interaction.completed 依狀態對應結束原因，incomplete 回報 maxOutputTokens

- `completed` 回報完成；`incomplete` 回報 `.maxOutputTokens`。`incomplete` 沒有附原因，文件只寫它是用完 `max_output_tokens`，所以 Gemini 屬於清單第 3 章「分不開生成途中塞滿 context window 與達到輸出上限」的供應商，不回報 `.contextWindowExceeded`。`LKAIFinishReason` 的說明跟著加上 Gemini。
- `failed`：文件寫錯誤在 `interaction.errors`，所以取第一筆，套用 `error` 事件中 `error` 物件的代碼規則。
  - 每一筆是平的 `{code, message}`，沒有外層的 `error` 物件；可解碼的條件是 `errors` 為陣列，每一筆是 `code` 與 `message` 出現時為字串或 null 的物件。
  - `errors` 沒有、為 null 或空陣列時，依 chat-client「Unrecognized stream errors」以沒有代碼處理，回報可重試的 500；文件建議 `failed` 時重試。
  - `errors` 是其他形狀時回報 `.invalidResponse`。
  - get-started 的 Python 範例讀的是 `error`（單數），見 Context；採用 safety-settings 文字與 Go 範例的 `errors`，實際是 `error` 時會成為可重試的 500，列在 Risks。
- `requires_action`、`cancelled`、其他狀態或沒有狀態：回報 `.invalidResponse`。本套件不送工具、不取消伺服器端的 interaction，正常情況不會出現，出現時代表 API 的行為和本套件的假設不同。
- 只有思考、沒有文字就達到上限時，照樣回報 `.maxOutputTokens`，文字為空字串（實測 Gemma 會這樣）。

### 用量的輸出 token 加上思考 token

- 依清單第 3 章的統一口徑，`outputTokens` 要包含思考的部分。Gemini 的 `total_output_tokens` 不含 `total_thought_tokens`（03 實測：41 + 3 + 528 = 572，等於 `total_tokens`），所以相加。
- `inputTokens` 直接用 `total_input_tokens`，因為它已包含快取（03 實測）。
- `cachedInputTokens` 是 `total_cached_tokens`，`reasoningOutputTokens` 是 `total_thought_tokens`；沒有回報時各自為 nil，`total_thought_tokens` 沒有時以 0 相加。
- 缺 `total_input_tokens` 或 `total_output_tokens` 時不帶用量，與 OpenAI 缺 `input_tokens`、`output_tokens` 時相同。

### 實際回應的模型取自 interaction.completed

- 依清單第 3 章，模型取自供應商的回報。`interaction.created` 與 `interaction.completed` 都帶 `model`；取結束事件的值，與 OpenAI 取結束事件的 `response.model` 相同，mapper 不必多記一個狀態。

### HTTP 錯誤處理 Interactions 與 Google 通用兩種格式

**與先前計畫的關係**：`03-revise-chat-client-contract` 的決策「新增供應商的清單取代 config.yaml 的層層指標」所寫的清單第 6 章，說 Google 通用格式「交給預設分類」。本次實測發現錯誤的 `AIza` 格式金鑰回 400，預設分類會把它當成 `.invalidRequest(message: nil)`，App 看不出是金鑰錯誤。使用者在 2026-11-22 同意改成下面的做法。這只修改那一項，其餘第 6 章的內容照舊，所以不寫 `Supersedes`。

- **Interactions 格式**（JSON 物件，`error.code` 是字串）依序套用：
  1. 生成被擋下的代碼回報 `.refused(detail: 代碼)`，見下一個決策。
  2. `quota_exceeded`、`payment_required` 回報 `.quotaExceeded`。
  3. 401、402、403、429 以外的 4xx，回報帶 `error.message` 的 `.invalidRequest`。
  4. 其餘回傳 nil，交給預設分類：429 的限流成為帶 `retry-after` 的 `.rateLimited`，5xx 成為帶 `retry-after` 的 `.serviceUnavailable`。
- **Google 通用格式**（`error.code` 是數字；實測都外包一層 JSON 陣列，generateContent 的文件則是沒有陣列的物件，所以兩種都接受，陣列取第一個元素）：`error.details` 中有 `reason` 為 `API_KEY_INVALID` 的項目時回報 `.invalidAPIKey`，其餘回傳 nil。401 與 403 本來就由預設分類得到 `.invalidAPIKey` 與 `.permissionDenied`。
- 規則 2 讓 `quota_exceeded` 不可重試：文件寫它是「exceeded your daily quota」，要等額度重置，自動重試沒有用。代價是實測看到每日上限為 0 的 429 用的是 `too_many_requests`，會被當成可重試的限流；它帶 72177 秒的 `retry-after`，App 看等待時間就知道不必立刻重試。
- 規則 3 與 OpenAI 相同：401、402、403、429 由預設分類得到更精確的種類，其他 4xx 帶 Gemini 的訊息，方便開發者除錯。
- 不自己分類 5xx，所以不必讀 `retry-after`（清單第 3 章：能交給預設分類時就回傳 nil）。
- **否決：只看狀態碼，兩種格式都交給預設分類**：就是原本的計畫，錯誤的 `AIza` 金鑰會變成 `.invalidRequest`。
- **否決：比對 `error.message` 的文字判斷金鑰錯誤**：文字可能隨語系與 API 版本改變；`ErrorInfo.reason` 是給程式判斷用的欄位。

### 生成被擋下的代碼回報 refused，HTTP 與串流相同

- 依清單第 3 章「政策性阻擋回報 `.refused`，而且 HTTP 與串流兩條路徑得到同一種錯誤」。
- 代碼採用 api-errors「Generation blocked codes」的全部 11 個，加上 safety-settings 提到的 `jailbreak`，共 12 個。四個 `image_*` 代碼在純文字對話不會出現，一起列入，讓「被擋下」的判斷與文件的表一致。
- `language`（不支援的語言）也列入：文件把它歸在被擋下的代碼，建議修改輸入後再試，和其他代碼相同，不可重試。
- `refused` 的 detail 是代碼，不是 Gemini 的 `message`：文件寫 `message` 以「Input blocked:」開頭，可能描述使用者的輸入。

### 串流的 error 事件依 error.code 分類

清單第 3 章要求供應商的 spec 寫明哪個欄位算錯誤代碼、資料缺到什麼程度算無法解碼：

- **錯誤代碼是 `error.code`**；可解碼的條件是 JSON 物件帶 `error` 物件，而且 `code` 與 `message` 出現時是字串或 null。沒有 `error` 物件、不是 JSON、`code` 是數字，都回報 `.invalidResponse`，和 Anthropic 沒有 `error` 物件時相同。
- **對應**：
  - 被擋下的代碼回報 `.refused`。
  - `rate_limit_exceeded`、`too_many_requests` 回報不帶等待時間的 `.rateLimited`。
  - 兩個額度代碼回報 `.quotaExceeded`。
  - `api_error` 500、`bad_gateway` 502、`service_unavailable` 503、`deadline_exceeded` 與 `gateway_timeout` 504，回報不帶等待時間的 `.serviceUnavailable`，因為串流中沒有標頭可讀（清單第 3 章）。`bad_gateway` 與 `gateway_timeout` 是文件說的「沒列出的代碼改用 HTTP 狀態的 snake_case 名稱」，`gateway_timeout` 是文件串流範例的代碼。
  - `authentication` 回報 `.invalidAPIKey`，`permission_denied` 回報 `.permissionDenied`，`invalid_request` 回報帶 `message` 的 `.invalidRequest`。
  - 其餘代碼與沒有代碼，呼叫 `LKAIError.unrecognizedStreamError(code:message:)`。
- 錯誤表的其他代碼（例如 `not_found`、`failed_precondition`）不另外對應：它們在串流開始前就會以 HTTP 錯誤回報（實測 404 `not_found` 是這樣），串流中出現時走共同規則，回報不可重試的 `.invalidResponse`。

### 金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留

**與先前決策的關係**：修改 `02-add-openai-provider` 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」中「每家各自保證」的部分；三個遵循仍由每家實作，所以不寫 `Supersedes`。使用者在 2026-11-22 同意這個做法（清單第 6 章）。

- 新增 `package struct LKAIAPIKey`，放在 `Sources/LKAICore/Networking/`：金鑰是組 HTTP 請求用的憑證，不屬於對話的約定；之後有對話以外的 client 時也從這裡取用。
  - 原始值放在 `unredactedValue`，名稱讓讀取的地方一看就知道是在取原始金鑰。
  - `description`、`debugDescription` 都是 `LKAIAPIKey(redacted)`，`customMirror` 沒有子項目。
- 三家 client 的 `apiKey` 改成 `LKAIAPIKey`，只有 `makeURLRequest(for:)` 讀 `unredactedValue`。公開的 `init(apiKey: String, …)` 不變。
- 三個遵循保留：它們決定 client 本身的描述內容（型別名與設定），而且第一份（`add-chat-abstraction-anthropic`）的 Context 實測過，`public` protocol 的要求不能由 `package` extension 滿足，02 的決策也引用它，無法收成共用的實作。
- 多一層保護的理由：之後有人在 `customMirror` 或 `description` 加上金鑰欄位，或忘了寫某個遵循時，金鑰仍然只會顯示成 `LKAIAPIKey(redacted)`。討論時以 Swift 6.4.2 實測過，client 完全不寫三個遵循時，包裝型別也能讓三種描述與 `dump(_:)` 都不含金鑰；這項實測只記在清單第 6 章，沒有寫進任何 design，由任務 1.1 的測試（不寫任何描述遵循、只有 `LKAIAPIKey` 欄位的 struct）固定下來。
- **否決：只在 Gemini 使用包裝型別**：三家的保證方式會不一致，下一家又要選一次。

### 與供應商無關的測試 helper 收進 LKAITestSupport

- 依清單第 3 章「與供應商無關的測試 helper 放 `LKAITestSupport`」，加上第 6 章列的名單與形狀：
  - **`LKAITestJSON`**（`package enum`）：`jsonObject(from:)` 的文字與 `Data` 兩個版本、`jsonFragment(from:)`、`optionalField(_:_:)`，以及 `booleanField(_:in:)`，都是 `static` 方法。`booleanField(_:in:)` 以 `JSONDecoder` 取出指定欄位，只接受 JSON 布林，取代兩家的 `decodeBooleanFlags(of:)` 與 `decodeStreamFlag(of:)`；Gemini 的請求測試也用它，不再多一份。它不在清單第 6 章原本的名單上，是規劃審查時提出的，使用者在 2026-11-22 同意一併搬。
  - **`LKAIErrorTestSupport`**（`package enum`）：巢狀的 `Expectation`，有 `.error(LKAIError)` 與 `.invalidResponse(containing: [String])` 兩個 case，以及 `matches(_ error: LKAIError?) -> Bool` 方法；另有 `static func isInvalidResponse(_ error: LKAIError?) -> Bool`，以 `Expectation.invalidResponse(containing: []).matches(error)` 實作。
- 命名：`config.yaml` 不允許 `package` 層級的頂層函式，所以 helper 放進以 `LKAI` 開頭的命名空間。`LKAITestSupport` 有兩種命名：對應受測型別的 `<受測型別>TestSupport`，以及沒有受測型別的主題命名空間 `LKAITestWaiting`。`LKAIErrorTestSupport` 對應 `LKAIError`；JSON helper 沒有受測型別，以主題命名為 `LKAITestJSON`，避免被讀成 `LKAISnakeCaseJSON` 的測試支援。`Expectation` 只能是巢狀型別，因為 `Testing` 模組有公開的 `Expectation`（Xcode 27.2 的 `Testing.swiftinterface`）。
- `matches` 改成接受 nil，讓串流測試可以直接傳 `outcome.error`；nil 一律不符合，預期沒有錯誤時仍寫 `outcome.error == nil`。
- 兩份 `Expectation` 合併時，採用 Anthropic 那份的說明（`containing` 寫明傳空陣列表示不比對說明文字）。
- `LKOpenAIClientStreamTests.ErrorExpectation` 改用 `LKAIErrorTestSupport.Expectation`，不帶值的 `.invalidResponse` 改成 `.invalidResponse(containing: [])`。「是無效回應」從此只有一種寫法。
- 搬移是行為不變的修改：兩家測試的名稱、期望值與測試數不變。`LKAITestSupportTests` 為 `matches`、`optionalField` 與 `booleanField` 加上測試，因為它們從此由三家共用，而且 `booleanField` 的結果會影響測試的結論（`1` 與 `true` 要分得出來）；`jsonObject` 與 `jsonFragment` 只轉呼叫 `JSONSerialization`，不另外寫測試，每個請求內容的測試都會用到它們。
- `LKAIErrorTests.UnrecognizedStreamCase.Expectation` 不動：`LKAICoreTests` 不依賴 `LKAITestSupport` 是 01 的決策「Anthropic 的測試走不到的共同行為在 LKAICoreTests 直接測試」的一部分，為了一個型別加上依賴，會讓 `LKAICore` 的測試依賴建立在 `LKAICore` 之上的 target。

### 事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase

- 規劃時 Gemini 的初稿照 `LKOpenAIStreamEvent` 的結構寫巢狀型別，審查了兩輪才改成條件式解碼；這兩條規則之後每一家以 SSE 串流回答的供應商都會遇到，所以寫成決策，由 3.1 帶進清單第 3 章「串流的共同流程」。
- **事件的巢狀欄位只在用得到時才解碼**：依同一則事件的其他欄位（步驟類型、狀態、片段類型）決定要不要讀某個欄位，比照 `LKAnthropicStreamEvent` 的 `ContentBlock` 與 `Delta`。理由：
  - 欄位存在但型別不對時，Optional 的解碼照樣失敗（見 Implementation Contract 的實測），只寫成 Optional 擋不住。
  - 供應商之後新增的步驟或事件，帶什麼欄位都不該讓串流失敗，這是清單第 3 章「不認得的事件一律略過」的延伸。
  - 只依文件、還沒實測的欄位（例如 Gemini 的 `interaction.errors`），不能讓正常完成的回答失敗。
- **手寫的 `CodingKeys` 用 camelCase、不寫 raw value**：經 `LKAISnakeCaseJSON` 解碼時，鍵會先轉成 camelCase 再比對，寫 raw value 會比對不到；以 `JSONEncoder()` 編碼的請求內容則照舊寫 raw value。
- 細節與實測見 Implementation Contract「只在用得到時才解碼欄位」。
- **否決：比照 `LKOpenAIStreamEvent` 以自動合成的解碼處理巢狀型別**：它不論事件種類都解碼全部欄位，見 Open Questions 的第四項。

### 實際 API 測試以 gemini-3.5-flash-lite 執行，由 owner 手動跑

- 依清單第 3 章與第 6 章：只在設定 `LKAI_GEMINI_API_KEY` 時執行；串流與非串流各一個，只檢查以完成結束、文字不為空、回應的模型不是 nil 也不是空字串。不比對模型名稱，因為實測看到請求的模型會換成別的模型。
- `gemini-3.5-flash-lite` 是目前最便宜的文字模型；輸出上限設 64，讓思考與文字都有空間又不會花太多錢。

### 輸入超過 context window 不特別處理

- 使用者在 2026-11-22 決定：記成風險，不特別處理。
- 依 Interactions 的錯誤代碼分類：400 `invalid_request` 成為帶訊息的 `.invalidRequest`；500 `api_error` 成為可重試的 `.serviceUnavailable`。
- 如果 `v1` 和 generateContent 一樣回 500，App 依 `isRetryable` 自動重試時會白白重送。之後有實例，或有不受免費方案限制的金鑰時再實測，列在 Open Questions。
- **否決：比對 `error.message` 的文字找出這種情況**：沒有實測過訊息，猜的文字可能永遠比對不到，也可能誤判其他 500。

### 實作由 sonnet 在單一 worktree 依序進行

- 沿用 03 的做法：sonnet 在 `.worktrees/sonnet`（分支 `wt/04-sonnet`）依任務順序實作，主對話逐項驗證、執行 build 與 test、commit。
- 合併回功能分支兩次：
  - 第一次在第 1、2 組完成後，之後 owner 在功能分支上執行 4.1。
  - 4.1 通過後，sonnet 回到 worktree 做 3.1，完成後第二次合併；主對話再做 3.2 與 4.2。
  - 4.1 沒有通過時，主對話查出原因，由 sonnet 在 worktree 修正並補上能重現問題的測試，合併後 owner 重跑 4.1。要改的是 spec 寫明的行為時，先以 `/spectra-ingest` 更新 spec 與 design，再由 sonnet 修正。
- 第一組任務會修改三家都用到的測試 helper，Gemini 的任務又依賴它們，平行進行容易衝突，所以依序進行。

## Implementation Contract

**新增與修改的型別**：

| 型別 | 位置 | 形狀 |
| --- | --- | --- |
| `LKAIAPIKey` | `Sources/LKAICore/Networking/LKAIAPIKey.swift`（新檔） | `package struct LKAIAPIKey: Sendable`，`package init(_ unredactedValue: String)`、`package let unredactedValue: String`；遵循 `CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable`，描述是 `LKAIAPIKey(redacted)`，`customMirror` 沒有子項目 |
| `LKAITestJSON` | `Sources/LKAITestSupport/LKAITestJSON.swift`（新檔） | `package enum`，`static func jsonObject(from text: String) throws -> NSDictionary`、`static func jsonObject(from data: Data) throws -> NSDictionary`、`static func jsonFragment(from text: String) throws -> NSObject`、`static func optionalField(_ name: String, _ json: String?) -> String`、`static func booleanField(_ name: String, in data: Data) throws -> Bool`（欄位不存在或不是 JSON 布林時丟出）。前四個方法的行為與兩家現在的 private 版本相同；`booleanField(_:in:)` 是新的形狀（收 `Data`、依欄位名稱取值），取代兩家的 `decodeBooleanFlags(of:)` 與 `decodeStreamFlag(of:)`，判斷的嚴格程度相同 |
| `LKAIErrorTestSupport` | `Sources/LKAITestSupport/LKAIErrorTestSupport.swift`（新檔） | `package enum`，巢狀 `enum Expectation: Sendable { case error(LKAIError); case invalidResponse(containing: [String]) }` 與 `func matches(_ error: LKAIError?) -> Bool`；`static func isInvalidResponse(_ error: LKAIError?) -> Bool` |
| `LKGeminiClient` | `Sources/LKAIGemini/` | `public struct LKGeminiClient: Sendable`：`public init(apiKey: String, urlSession: URLSession, shouldStoreResponses: Bool = false)`、`package init(apiKey: String, httpClient: any LKAIHTTPClientProtocol, shouldStoreResponses: Bool = false)`；遵循 `LKAIChatClientProtocol`、`LKAIServerSentEventChatStreaming` 與三個描述 protocol。`description` 為 `LKGeminiClient(shouldStoreResponses: <值>)` |
| 請求內容、串流事件、mapper、錯誤格式 | `Sources/LKAIGemini/` | `LKGeminiInteractionsRequestBody`（`Encodable`）、`LKGeminiStreamEvent`（依 `event_type` 解碼）、`LKGeminiStreamState`（遵循 `LKAIServerSentEventMapping`，持有 `index` 到步驟類型的對照）、`LKGeminiErrorBody`（Interactions 格式）、`LKGeminiGoogleErrorBody`（Google 通用格式）。名稱依 ios-dev-kit 樣板與 `LK<供應商>` 前綴，實作時可調整，但要在任務回報中寫明 |

**請求**：照 spec「Interactions API request」。`max_output_tokens` 照原樣送出。

**串流事件的對應**：

| `event_type` | 處理 |
| --- | --- |
| `step.start` | 記錄 `index` → `step.type`；`model_output` 帶 `step.content` 時，依序交出其中 `type` 為 `text` 的 `.textDelta(text)`，否則不交出事件 |
| `step.delta` | 該 `index` 是 `model_output` 且 `delta.type` 為 `text` 時，交出 `.textDelta(delta.text)`；其餘不交出 |
| `interaction.completed` | 依 spec「Finish mapping」結束：交出 `.finished(LKAIChatCompletion)`，或丟出錯誤 |
| `error` | 依 spec「Error mapping」丟出錯誤 |
| 其他，包含 `interaction.created`、`interaction.status_update`、`step.stop` 與不認得的種類 | 不交出事件 |

- `data` 不是 JSON、沒有字串 `event_type`、認得的種類缺少必要欄位時，丟 `.invalidResponse`。
- **只在用得到時才解碼欄位**：Swift 解成 Optional 只容許欄位不存在或為 null，欄位存在但型別不對時仍會失敗，所以「解成 Optional」不夠，要依同一則事件的其他欄位決定要不要解：
  - `step.start` 的 `step.content` 只在 `step.type` 為 `model_output` 時解碼。步驟類型就在同一則事件裡，解碼時就能判斷；其他步驟類型（例如文件列的 `function_call` 與伺服器端工具，欄位「Varies by tool」）帶什麼 `content` 都不影響串流。
  - `interaction.completed` 的 `interaction.errors` 只在 `status` 為 `failed` 時解碼；它是整份設計中證據最弱的欄位，不能讓 `completed` 因它失敗。
  - `step.delta` 的 `delta.text` 只在 `delta.type` 為 `text` 時解碼，而且必須是字串：沒有、null 或型別不對都失敗，不論步驟類型，也不論 `index` 有沒有記錄過。寫法和 `LKAnthropicStreamEvent.Delta` 讀 `text_delta` 的 `text` 相同（`decode(String.self, forKey: .text)`），解碼時就能判斷，mapper 不必再依步驟類型檢查。依文件，思考步驟的片段類型是 `thought_signature` 與 `thought_summary`，`text` 類型只出現在 `model_output`，所以這不會讓正常的串流失敗。這是第四輪規劃審查後簡化的規則，使用者在 2026-11-22 同意；原本的規則是「`model_output` 步驟才要求有 `text`」，要在解碼後由 mapper 判斷，照抄 Anthropic 的 `decode` 時會在 null 與思考步驟上出錯，而且沒有測試抓得到。
  - null 一律視為不存在；`delta.text` 的 null 因此和沒有這個欄位一樣，依上一點算失敗。
  - **比照對象**：最外層依 `event_type` 分派的結構比照 `LKOpenAIStreamEvent`；巢狀的 `step`、`delta`、`interaction` 不能用自動合成的解碼，要比照 `LKAnthropicStreamEvent` 的 `ContentBlock`（只有 `fallback` 類型才讀目標模型）與 `Delta`（只有 `text_delta` 才讀文字），手寫條件式的 `init(from:)`。`LKOpenAIStreamEvent` 的 `Response` 與 `Usage` 是自動合成，不論事件種類都解碼全部欄位，照它寫會讓上面這幾種情況使串流失敗。
  - **鍵的寫法**：手寫的 `CodingKeys` 用 camelCase、不寫 raw value，例如 `case eventType`，比照 `LKAnthropicStreamEvent`。`LKAISnakeCaseJSON` 以 `.convertFromSnakeCase` 先把 JSON 的鍵轉成 camelCase 再比對，寫成 `case eventType = "event_type"` 會比對不到：規劃審查時以 Swift 6.4.2 實測（2026-11-22，scratchpad），寫成 raw value 時解碼丟 `keyNotFound`，camelCase 才解得出來；同一次實測也確認 Optional 欄位遇到 null 與不存在都解成 nil，遇到數字仍然失敗。Gemini 的 `event_type` 是這個 repo 第一個多字的事件種類鍵（另外兩家都是 `type`）。
  - **鍵的寫法的適用範圍**：只適用經 `LKAISnakeCaseJSON` 解碼的型別。請求內容 `LKGeminiInteractionsRequestBody` 以 `JSONEncoder()` 編碼，沒有 snake_case 策略，仍比照 `LKOpenAIResponsesRequestBody` 寫 raw value，例如 `case maxOutputTokens = "max_output_tokens"`，否則會送出 `maxOutputTokens`。
- **新檔案比照 `Sources/LKAIOpenAI/` 的對應檔案**，結構與 MARK 分區相同：client 比照 `LKOpenAIClient`，請求內容比照 `LKOpenAIResponsesRequestBody`，串流事件比照 `LKOpenAIStreamEvent`，mapper 比照 `LKOpenAIStreamState`，兩種錯誤格式比照 `LKOpenAIErrorBody`。
- `[DONE]` 不會交給 mapper，因為共同流程在 `.finished` 之後就停止讀取；如果在 `interaction.completed` 之前出現，它不是 JSON，回報 `.invalidResponse`。

**結束資訊**：`LKAIChatCompletion(finishReason:usage:respondingModel:)`，用量與模型照 spec「Usage mapping」「Responding model」。

**錯誤**：照 spec「Error mapping」。

- `httpError(statusCode:headers:body:)` 先試 Interactions 格式，再試 Google 通用格式，都解不出來或規則都不符合時回傳 nil。
- 串流中對應不到的錯誤一律呼叫 `LKAIError.unrecognizedStreamError(code:message:)`，不自己組說明文字。
- 建立 `.serviceUnavailable` 時一律寫明 `retryAfter: nil`。

**其他修改**：

- `Package.swift`：新增 `LKAIGemini`（依賴 `LKAICore`）與 `LKAIGeminiTests`（依賴 `LKAIGemini`、`LKAICore`、`LKAITestSupport`）；`LKAIKit` 加上 `LKAIGemini`。
- `Sources/LKAIKit/Exports.swift` 加上 `@_exported import LKAIGemini`；`ExportsTests` 加上 Gemini 的測試。
- `LKAIFinishReason` 只改 `///`：
  - `.maxOutputTokens` 的例子加上 Gemini。
  - `.contextWindowExceeded` 的「目前只有 Anthropic」不變。

**完成後的狀態**：

- `Sources/` 內不含 `///` 的行中，只有 `LKAIAPIKey.swift` 與三家的 `makeURLRequest(for:)` 出現 `unredactedValue`。
- 三家 client 都沒有 `private let apiKey: String`。
- `Tests/` 內沒有 `func jsonObject(`、`func jsonFragment(`、`func optionalField(`、`func matches(`、`func isInvalidResponse(`、`func decodeBooleanFlags(`、`func decodeStreamFlag(`、`struct BooleanFlagsBody`、`struct StreamFlagBody`、`enum ErrorExpectation`，以及錯誤測試的 `enum Expectation`；`LKAIErrorTests.UnrecognizedStreamCase.Expectation` 除外。
- `Sources/LKAIGemini/` 內沒有「Unrecognized stream error code」這段文字。
- `Sources/LKAIGemini/` 內沒有 `Task {`：背景 task 仍只在 `LKAICore` 建立（清單第 3 章）。
- `Sources/LKAIGemini/` 內沒有 `JSONDecoder()`：解碼一律經 `LKAISnakeCaseJSON`（清單第 3 章）。
- `LKAIAnthropicTests` 仍是 45 個測試、`LKAIOpenAITests` 仍是 23 個，名稱與期望值不變。

**驗收**：

- `swift package clean` 後 `swift build`、`swift build --build-tests` 與完整 `swift test` 零警告。
- 測試數是估計值，驗收時記錄實際數字與差異的原因：
  - `LKAICore` 67 → 68，多 `LKAIAPIKey` 的測試。
  - `LKAITestSupportTests` 3 → 6，多 `matches`、`optionalField` 與 `booleanField`。
  - `LKAIKit` 3 → 4。
  - 新增 `LKAIGemini` 約 19 個，含 2 個實際 API 測試。
- `spectra coverage 04-add-gemini-provider` 顯示 `gemini-provider` 的每個情境與範例都有測試，範例表的每一列都有測試案例。
- XcodeBuildMCP 對 iOS 模擬器建置 `LKAIKit` scheme 零警告。
- 反向檢查：故意改壞下列十八項行為，對應的測試必須失敗，做完後還原：
  1. 思考步驟的片段也交出：範例「stream with lifecycle events and a thought step」。
  2. 不記錄步驟類型，只看 `delta.type`：串流範例中 `thought` 步驟的 `text` 片段 "Thinking"。
  3. `incomplete` 回報完成：結束事件範例表的 `incomplete` 列。
  4. 輸出 token 不加思考 token：用量範例表的第一列。
  5. 不讀 `API_KEY_INVALID`：HTTP 錯誤範例表中帶 `API_KEY_INVALID` 的兩列 400 Google 通用格式（陣列與物件外層各一列）。
  6. 串流的 `safety` 不回報 `.refused`：`error` 事件範例表的 `safety` 列。
  7. `store` 預設送 true：保存設定範例表的「not set」列。
  8. 不認得的代碼回報 500：`error` 事件範例表的 `new_unknown_code` 列。
  9. `LKAIAPIKey.description` 回傳原始值：`LKAIAPIKey` 的測試。
  10. `failed` 不看 `errors`：結束事件範例表的 `failed` 帶 `safety` 列。
  11. Interactions 規則 3 不排除 429：HTTP 錯誤範例表的 429 `too_many_requests` 列。
  12. `step.start` 的 `step.content` 不交出：範例「text in the start of a model output step」。
  13. 把無法解碼的 `error` 事件略過：`error` 事件範例表的 `{"event_type":"error"}` 列。
  14. Google 通用格式只接受陣列外層：HTTP 錯誤範例表中物件外層、帶 `API_KEY_INVALID` 的那一列。
  15. 不論步驟類型都解碼 `step.content`：範例「stream with lifecycle events and a thought step」中 `google_search_call` 的 `step.start`。
  16. 不論狀態都解碼 `interaction.errors`：結束事件範例表的「status `completed`、`errors` 是 `"none"`」列。
  17. 不論 `delta.type` 都解碼 `delta.text`：同一個範例中 `google_search_result` 的 `step.delta`。
  18. 照簡化前的規則實作（`delta.text` 解成 Optional，只有 `model_output` 步驟缺 `text` 才失敗）：缺欄位範例表中 `index` 3、`delta.text` 為 null 的那一列。

**範圍**：

- 範圍內：上面列的型別與檔案、兩家測試改用搬過去的 helper、`LKAIFinishReason` 的說明、`docs/adding-a-provider.md`。
- 範圍外：Non-Goals 列的項目；chat-client、anthropic-provider、openai-provider 的 spec；`LKAIKitCLI`。

## Risks / Trade-offs

- [輸入超過 context window 時如果回 500，App 會白白重試] → 記在 Open Questions 與清單第 7 章，有實例或合適的金鑰時再實測。
- [`failed` 的 `errors` 與串流中途的 `error` 事件都只依文件] → spec 寫明分類規則，實際格式不同時，回報的是 `.invalidResponse` 或 500，不會無聲吞掉錯誤；owner 的實際 API 測試只涵蓋正常完成。
- [每日上限為 0 的 429 以 `too_many_requests` 回報，被當成可重試] → 它帶 `retry-after`，App 看等待時間就知道不必立刻重試；這和文件的代碼表一致，不另外猜測。
- [Gemini 新增被擋下的代碼時，串流中會變成不可重試的 `.invalidResponse`，HTTP 會依規則 3 變成帶 Gemini `message` 的 `.invalidRequest`] → 都不可重試，不會讓 App 重送；串流的說明帶代碼，之後補對應。HTTP 的 `message` 可能以「Input blocked:」開頭並描述使用者的輸入，這正是被擋下的代碼不拿 `message` 當 detail 的理由；`.invalidRequest` 的訊息是給開發者看的，記錄 log 時比照使用者的內容處理。
- [`interaction.completed` 實際上沒有 `model` 時（thinking 頁的範例是這樣），回報的模型是 nil] → 依實測，兩則事件都帶 `model`；不改用 `interaction.created` 的值，因為規則是取結束事件的回報。owner 的實際 API 測試要求模型不是 nil，但它只用 `gemini-3.5-flash-lite`；thinking 頁的範例用的是 `gemini-3.8-flash`，其他模型的回應和文件一樣時，這個測試發現不了。
- [`failed` 的錯誤欄位實際是 `error`（單數）時，會被當成沒有錯誤，回報可重試的 500] → 文件三處中兩處寫 `errors`，採用它；遇到實例時核對，列在 Open Questions。
- [之後思考步驟或其他步驟送出 `delta.type` 為 `text`、卻沒有字串 `text` 的片段時，整條串流會以不可重試的 `.invalidResponse` 失敗] → 這是簡化 `delta.text` 規則的代價，見決策「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」；失敗會回報出來，不會無聲漏掉內容。依文件目前不會發生，出現實例時再調整規則。
- [步驟追蹤失效（API 不再送 `step.start`，或 `model_output` 改名）時，每次呼叫都回報完成、文字為空，沒有錯誤] → 被否決的「只看 `delta.type`」失效時會把思考內容當成回答交出，現在的失效方向比較安全；owner 的實際 API 測試檢查文字不為空，會發現。有實例時再評估把「沒有記錄的 `index` 的 `text` 片段」改成 `.invalidResponse`。
- [新的供應商沒有用 `LKAIAPIKey` 保存金鑰時，各家的金鑰遮蔽測試照樣通過，因為三個遵循本身就能遮住金鑰] → 3.1 把「完成後的狀態」中 `unredactedValue` 與 `let apiKey: String` 的 grep 寫進清單第 3 章，成為每個新增供應商的 change 都要做的檢查。
- [搬移 helper 時改錯兩家的測試] → 搬移任務以兩家的測試名稱、期望值與測試數不變把關，並做三種反向檢查：`matches` 不檢查片段、`.invalidResponse` 的比對一律回傳 false、`booleanField` 接受數字 `1`。
- [`LKAIAPIKey` 的 `unredactedValue` 是 `package`，同 package 的程式仍可能把它寫進 log] → 名稱讓這個動作在 code review 時一眼可見；完成後的狀態以 grep 確認只有三家的 `makeURLRequest(for:)` 讀取。

## Migration Plan

App 端不需要遷移：公開 API 只新增 `LKGeminiClient`，既有的型別與建立方式不變。

## Open Questions

- 輸入超過 context window 時，`v1` 回的狀態碼與代碼：有實例，或有不受免費方案每分鐘 token 上限限制的金鑰時實測，再決定要不要在 Gemini 的錯誤對應中處理。
- 串流中途的 `error` 事件與 `failed` 的 `errors`（或 `error`），實際格式是否和文件相同：遇到實例時核對。
- 「401、402、403、429 以外的 4xx 帶訊息」的規則在 `LKOpenAIErrorBody` 與 Gemini 各有一份，它其實是「預設分類對哪些狀態碼有更精確的結果」：預設的 4xx 分類要改（例如讓 408 可重試），或第三家也寫這條時，收成 `LKAICore` 的一個 `package` 函式，並同時修改兩家的 spec。
- `LKOpenAIStreamEvent` 的 `Response` 不論事件種類，都會解碼 `error` 與 `incomplete_details`：`response.completed` 帶形狀不同的 `error` 時，已完成的回答會以 `.invalidResponse` 結束，和這次替 Gemini 避開的情況同類。OpenAI 的文件寫明成功時 `error` 是 null，證據比 Gemini 強，而且不在本 change 的範圍；出現實例時，比照 Gemini 改成只在用得到時才解碼。
