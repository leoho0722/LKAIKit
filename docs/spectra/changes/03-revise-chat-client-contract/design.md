## Context

依 `docs/spectra/config.yaml`，供應商的 change 不能為了自己的格式修改 chat-client 的共同規則。前兩個供應商的 change 在 Open Questions 留下五個要另開 change 處理的項目，本 change 一次處理：

- **503 的 `Retry-After`**（`02-add-openai-provider`）：OpenAI 的 503 `server_is_overloaded` 會帶 `Retry-After`，但 `serviceUnavailable(statusCode:)` 沒有欄位可放。02 建議在第一個 release tag 前處理，成本最低。
- **「Context window limit」需求的條件**（02 的 Non-Goals 與 Open Questions）：OpenAI 分不出 context window 塞滿與達到輸出上限，需求文字和實際行為不符。
- **`refused(detail:)` 的隱私說明**（02）：detail 可能是模型寫的文字，這則提醒目前只寫在 `LKOpenAIClient`。使用者決定等 Gemini 帶來第三種格式時一起改。
- **不認得的串流錯誤**（02）：Anthropic 當成可重試的 500，OpenAI 當成不可重試的 `.invalidResponse`。02 寫明要和 Gemini 的查證一起決定是否訂成共同規則。
- **`config.yaml` 的指標層數**（02）：每多一家供應商就多一層「以某份為準」。02 寫明要在 Gemini 時評估改成一份持續更新的清單。

使用者在 2026-11-22 的討論中決定：

- 先做本 change，再做 Gemini（暫定 `04-add-gemini-provider`）。
- 以上五項都依主對話的建議處理，見各決策。
- 不認得的串流錯誤照 OpenAI 的做法訂成共同規則，Anthropic 跟著改，見決策「不認得的串流錯誤以 unrecognizedStreamError 統一回報」。
- 規劃審查（fable、opus，2026-11-22）之後：`retryAfter` 改成不給預設值，見決策「服務不可用的錯誤帶上等待時間，不給預設值」；其餘審查意見都照修。
- 金鑰包裝型別、測試 helper 搬進 `LKAITestSupport` 放在 Gemini 的 change，不在本 change。

**Gemini 的查證**（2026-11-22）：本 change 要用三家的證據修改共同規則，Gemini 的事實也是新增供應商清單裡 Gemini 一欄的來源。

- 查證方式：
  - Context7 收錄的官方文件（`ai.google.dev/gemini-api/docs`：interactions、api-versions、api-errors、safety-settings、thinking、text-generation、long-decode、tokens、interactions-breaking-changes-may-2026）。
  - 以 owner 的金鑰（Keychain service `lkai-gemini-api-key`）對 `v1/interactions` 送出 9 次請求，費用估計不到 0.01 美元。這個估計是依各次的用量回報與第三方價格表算的，沒有對帳單核對。
- **API 的選擇**：
  - Gemini 有 Interactions API 與 generateContent 兩套。官方文件寫 Interactions「As of June 2026, it is Generally Available and the recommended interface for all new projects」，generateContent「remains fully supported」，沒有淘汰日期。
  - api-versions 頁寫 Interactions 的核心功能已在穩定版 `v1`。文件範例全用 `v1beta`，而 `v1beta` 在 2026 年 5 月改過一次結構（`outputs` 改成 `steps`、事件改名）。
  - 使用者選定 Interactions API 的 `v1`。
- **請求**（實測）：
  - `POST https://generativelanguage.googleapis.com/v1/interactions`，標頭 `x-goog-api-key`。
  - 請求內容是 `model`、`input`、純文字的 `system_instruction`、`generation_config.max_output_tokens`、`store: false`、`stream: true`，都被接受。
  - 多輪歷史以 `input` 陣列送出：`{"type":"user_input","content":[{"type":"text","text":...}]}` 與 `{"type":"model_output","content":[...]}`。
  - 文件寫明模型產生的 `thought` 步驟「MUST」照原樣送回，但實測只送純文字的 `model_output` 也成功，答案正確。
  - `max_output_tokens` 為 0 時回 400 `invalid_request`，訊息為「max_output_tokens must be positive」。
  - `store` 預設為 true，付費方案保存 55 天（文件）。
- **串流**（實測）：
  - 依序為：
    1. `interaction.created`，帶 `model`。
    2. `interaction.status_update`。
    3. `thought` 步驟：`step.start`、只帶 `thought_signature` 的 `step.delta`、`step.stop`。
    4. `model_output` 步驟：多則 `delta.type` 為 `text` 的 `step.delta`。
    5. `interaction.completed`。
    6. `event: done` 與 `data: [DONE]`。
  - 中間另有 SSE 註解行 `: keep-alive`。
  - 文件寫的 `interaction.in_progress` 實際沒有出現。
- **結束**（實測）：
  - 正常完成與達到輸出上限都以 `interaction.completed` 結束，差在 `interaction.status` 為 `completed` 或 `incomplete`。
  - `incomplete` 沒有附原因。文件的狀態表寫 `incomplete` 是「The model used all of `max_output_tokens`」，沒有 context window 的獨立原因。
- **實際回應的模型**（實測）：請求 `gemini-3.5-flash` 時，`interaction.created` 與 `interaction.completed` 的 `model` 都是 `gemini-3.6-flash`。
- **用量**（實測，`interaction.completed` 的 `interaction.usage`）：
  - 欄位是 `total_input_tokens`、`total_cached_tokens`、`total_output_tokens`、`total_thought_tokens`、`total_tokens`。文件一處範例寫成 `prompt_tokens`／`completion_tokens`，實際不是。
  - `total_output_tokens` 不含思考：41 + 3 + 528 = 572，等於 `total_tokens`。
  - `total_input_tokens` 含快取：同一段 5000 token 的請求送兩次，第二次 `total_input_tokens` 仍為 5000，`total_cached_tokens` 為 2033。
- **錯誤**：
  - **文件**：
    - 格式是 `{"error":{"code","message"}}`，`code` 是 snake_case。
    - 429 分成 `rate_limit_exceeded`、`quota_exceeded`、`too_many_requests`；402 是 `payment_required`；503 是 `service_unavailable`。
    - 文件寫「Any error code not listed above falls back to the `snake_case` version of the HTTP status」。
    - 被安全過濾擋下時回 HTTP 400，`code` 為 `safety`、`jailbreak`、`prohibited_content` 或 `blocklist`；串流中則以 `error` 事件送出，格式是 `{"event_type":"error","error":{"code","message"}}`。
  - **實測**：
    - 模型忙碌：503 `{"error":{"message":"…high demand…","code":"service_unavailable"}}`。
    - 模型不存在：404 `not_found`，文件寫的是 `model_not_found`。
    - 不認得的參數、`max_output_tokens` 為 0：400 `invalid_request`。
    - 金鑰錯誤：401，但格式是 Google 通用的 `{"error":{"code":401,"status":"UNAUTHENTICATED","details":[…]}}`，外面再包一層 JSON 陣列；沒帶金鑰時是同一種格式的 403 `PERMISSION_DENIED`。文件寫的 `authentication` 代碼實際沒有出現。
  - **沒有實測到**：串流中途的 `error` 事件、被安全過濾擋下、503 是否帶 `Retry-After`（503 那次沒有記錄標頭）、輸入超過 context window 時 `v1` 回的狀態碼。
- **輸入超過 context window**：Interactions 的錯誤表沒有專屬代碼；generateContent 的錯誤表把「Your input context is too long」列在 500 `INTERNAL` 底下。如果 Interactions 也回 500，預設分類會把它當成可重試，要由 `04-add-gemini-provider` 實測。

**目前的程式碼**（2026-11-22 讀取 `main` 的 `f365f6f`；`git diff 504550e f365f6f -- Sources Tests Package.swift` 為空，所以程式碼與 02 驗收時相同）：

- `LKAIError.serviceUnavailable(statusCode:)` 只有一個 associated value。
  - `Sources/` 與 `Tests/` 共有 35 處以 `.serviceUnavailable(statusCode:` 建立它：`Sources/` 9 處、`Tests/` 26 處（`grep` 計數，不含 `LKAIError.swift` 的 case 宣告）。
  - 比對它的寫法只有不綁值的 `case .serviceUnavailable:`（`isRetryable` 與 `localizationKey`）。
- `LKAIError.init(httpStatusCode:retryAfter:)` 只在 429 讀 `retryAfter`，5xx 一律不帶等待時間。
- **Anthropic**：
  - `LKAnthropicErrorBody.Detail.type` 是非 Optional 的 `String`，所以缺少 `error.type` 的 `error` 物件無法解碼：HTTP 改用預設分類，串流丟出 `invalidResponse`。
  - 串流的 `error` 事件以 `LKAnthropicErrorBody(from:)` 解碼，外層的 `error` 物件是必要欄位，沒有時同樣無法解碼。
  - 測試的 `Expectation` 只有 `.error` 與不比對說明的 `.invalidResponse`。
  - `LKAnthropicStreamState.handle(_:)` 在 `lkaiError(statusCode:retryAfter:)` 回傳 nil 時丟 `.serviceUnavailable(statusCode: 500)`。
  - HTTP 的 `api_error`、`overloaded_error`、`timeout_error` 不讀 `retry-after`。
- **OpenAI**：
  - `LKOpenAIErrorBody.Detail.streamError` 對不認得的代碼丟 `.invalidResponse(reason: "Unexpected error code <code>: <message>")`，沒有代碼時丟 500。
  - `LKOpenAIStreamState` 在 `response.failed` 沒有 `response.error` 時丟 500。
  - HTTP 的 5xx 除了政策性阻擋與額度的代碼之外都回傳 nil，交給預設分類，503 `server_is_overloaded` 也是。
  - 串流的 `error` 事件整個解成全是 Optional 的 `LKOpenAIErrorBody.Detail`，用 Swift 自動產生的解碼：欄位沒有出現或為 null 都解得出來，欄位型別不對（例如 `code` 是數字）時解碼失敗。
  - `LKOpenAIClient.httpError(statusCode:headers:body:)` 的說明寫「只有走預設分類的 429 限流才由共同流程讀它」。
  - 測試的 `Expectation` 已有 `.invalidResponse(containing:)`，比對說明含全部片段。
- **測試數**（02 任務 5.4 於 `504550e` 量測）：共 147 個，LKAICore 66、LKAIAnthropic 45、LKAIOpenAI 23、LKAIKitCLI 7、LKAIKit 3、LKAITestSupportTests 3。
- **`spectra-scenario` 標記**：`Tests/` 內共 119 行（`git grep` 計數）。

**以 Swift 6.4.2 實測**（2026-11-22，scratchpad）：enum case 從一個 associated value 改成兩個之後的行為。沒有預設值的 `serviceUnavailable(statusCode: Int, retryAfter: Duration?)` 與給了預設值 `= nil` 的版本，以下每一種寫法都測過（規劃第二輪審查後補齊了沒有預設值的版本）。比對的結果兩者相同，只有建立的寫法不同：

- `.serviceUnavailable(statusCode: 503)`：給了預設值時照常編譯，等於 `retryAfter` 為 nil；沒有預設值時編譯失敗：missing argument for parameter 'retryAfter' in call。
- `case .serviceUnavailable:` 照常編譯。
- `case .serviceUnavailable(statusCode: let code)` 沒有任何警告，但 `code` 變成整個 tuple `(statusCode: 503, retryAfter: nil)`。拿它當 `Int` 用時編譯失敗；只放進字串插值時，輸出會悄悄改變。
- `case .serviceUnavailable(statusCode: 503)` 編譯失敗：expression pattern of type 'Int' cannot match values of type '(Int, Duration?)'。
- `case .serviceUnavailable(let code)` 有 deprecation 警告：matching them as a tuple is deprecated。
- `case .serviceUnavailable(let code, _)`、`case .serviceUnavailable(statusCode: let code, retryAfter: _)` 可以取出狀態碼。

## Goals / Non-Goals

**Goals:**

- App 從 `serviceUnavailable` 讀得到供應商要求的等待時間，處理方式和 `rateLimited` 一樣。
- 帶有錯誤代碼但供應商不認得的串流錯誤，三家都回報同一種錯誤、同樣的可否重試；錯誤代碼是哪個欄位、資料缺到什麼程度算無法解碼，由各家的 spec 寫明。
- 「Context window limit」需求與三家的實際行為一致。
- `refused(detail:)` 的隱私提醒寫在共用型別上，App 以 `any LKAIChatClientProtocol` 處理錯誤時也讀得到。
- 新增供應商的必讀內容只有一份持續更新的清單，不再一層層指向封存的 design。

**Non-Goals:**

- Gemini 的實作、金鑰包裝型別、測試 helper 搬進 `LKAITestSupport`：都在 `04-add-gemini-provider`。
- 新增 `LKAIError` 或 `LKAIFinishReason` 的 case，包含輸入超過 context window 的專屬錯誤：Anthropic 與 OpenAI 都沒有可辨識的代碼（見 02 的決策「輸入超過 context window 的錯誤不設專屬種類」），02 設的條件「至少兩家可辨識」已不成立。Gemini 的文件沒有列專屬代碼，實際回應待 `04-add-gemini-provider` 實測（見 Context）。
- 串流中途錯誤的等待時間：串流沒有標頭可讀。
- OpenAI 串流 `error` 事件欄位全是 Optional 的問題：使用者在 02 決定有實例時再改 spec。
- `LKAIError` 的 `errorDescription` 與 String Catalog 的字串：說明是每種錯誤一則通用訊息，不含等待時間，不改。
- 公開的 `LKAIError.retryAfter` 計算屬性（規劃審查時 fable 提議）：純新增，之後有需要再加不會破壞 App。
- 自動重試、版本號與 release tag。

## Decisions

### 服務不可用的錯誤帶上等待時間，不給預設值

- `LKAIError` 的 case 改成 `serviceUnavailable(statusCode: Int, retryAfter: Duration?)`，不給預設值。
  - 型別與 `rateLimited(retryAfter: Duration?)` 相同，它也沒有預設值，App 可以用同一段程式處理兩種等待時間。
  - `///` 寫明：供應商沒有提供或無法解讀時為 nil；串流中途的錯誤一律為 nil；取狀態碼的寫法是 `case .serviceUnavailable(let statusCode, let retryAfter)`。
- **為什麼不給預設值**（規劃審查時 fable 指出，使用者同意）：
  - **可逆性**：現在不給，之後要給是純新增；現在給了，之後要拿掉才是破壞性變更。第一個 release tag 之前，選之後還能改的那一邊。
  - **給預設值的理由不成立**：`config.yaml` 的 API 演進規則要新欄位給預設值，是為了讓 App 建立這些值的程式碼（例如測試替身）不必修改。目前沒有 App 使用 LKAIKit，實際只省下 package 內 35 處的機械式修改。
  - **每一處都明寫**：串流傳 nil、HTTP 讀標頭，兩種在程式碼上看得出差別；漏讀標頭的地方不會藏在預設值後面。
- **破壞性變更**：
  - App 建立這個 case 的程式碼要補上 `retryAfter:`。
  - App 以 `case .serviceUnavailable(statusCode: let code)` 取狀態碼時，`code` 會變成 tuple，沒有警告（實測，見 Context）。
  - 目前沒有 App 使用 LKAIKit：BuyLedger 改用 LKAIKit 列在 `add-chat-abstraction-anthropic` 的 Non-Goals。
- 考慮過的替代方案：
  - **給預設值 nil**：規劃初稿的做法。App 的測試替身不必改，但之後拿掉就是破壞性變更，否決。
  - **另加一個 case**，例如 `serviceOverloaded(retryAfter:)`：不會破壞 App 的比對，但「服務暫時不能用」分成兩個 case，App 兩個都要處理，否決。
  - **改用 struct 帶資料**：`add-chat-abstraction-anthropic` 的決策「實際回應的模型放進共用結果」用 struct，理由是增減 enum 的 associated value 會讓 App 的程式碼編譯失敗。這次只有兩個欄位，又要和 `rateLimited` 對稱，維持 associated value。之後若要再加第三個欄位（例如供應商訊息），改成 struct。
- **`config.yaml` 的 API 演進規則補一條**（規劃第二輪審查時 fable 建議），由 3.2 寫入，讓這條原則不必只靠封存的 design：

  > 公開 enum 的 case 增減 associated value，會破壞 App 建立與比對這個 case 的寫法（給新的 associated value 預設值只保住建立的寫法，保不住比對的寫法）；第一個 release tag 之後要加資料時，改用 struct 帶資料。

### 5xx 的預設分類與 Anthropic 的 HTTP 錯誤讀 retry-after

- **預設分類**：`LKAIError.init(httpStatusCode:retryAfter:)` 的 5xx 改成 `.serviceUnavailable(statusCode: httpStatusCode, retryAfter: Self.retryDelay(from: retryAfter))`。
  - 等待時間的規則與 429 相同：只接受純 ASCII 數字的秒數，帶正負號、空白或 HTTP 日期都是 nil。
  - OpenAI 的 HTTP 5xx 本來就交給預設分類，所以 503 `server_is_overloaded` 帶上等待時間，不必修改 `LKOpenAIErrorBody`。
- **Anthropic**：`LKAnthropicErrorBody.Detail.lkaiError(statusCode:retryAfter:)` 的 `api_error`、`overloaded_error`、`timeout_error` 帶上 `LKAIError.retryDelay(from: retryAfter)`。
  - 串流中 `retryAfter` 傳 nil，結果仍是 nil。
  - 三個分支各自建立錯誤，所以三種類型各有一列帶 `retry-after` 的範例與一項反向檢查，漏改其中一支時測試會失敗（規劃審查時 opus 指出初稿只有 529 一列）。
  - Anthropic 的文件只寫 429 帶 `retry-after`，529 是否帶沒有查證；有帶時讀取沒有壞處。
- **OpenAI 的說明**：`LKOpenAIClient.httpError(statusCode:headers:body:)` 的 Note 改成 429 與 5xx 都由共同流程讀 `retry-after`。
- **Anthropic 的說明**：`LKAnthropicClient.httpError(statusCode:headers:body:)` 的 `headers` 參數說明與 Note，改成三種服務不可用的錯誤也讀 `retry-after`。
- **Gemini**：`04-add-gemini-provider` 自己分類 5xx 時，也要讀 `retry-after`，寫進新增供應商清單的規則。
- 考慮過的替代方案：只讀 503。各家過載的狀態碼不同（Anthropic 529、OpenAI 與 Gemini 503），以 5xx 為範圍比較一致，否決。

### 不認得的串流錯誤以 unrecognizedStreamError 統一回報

**與先前決策的關係**：本決策改寫 `add-chat-abstraction-anthropic` 的決策「Anthropic 串流事件的對應規則」中 `error` 事件的兩項，使用者在 2026-11-22 同意：

- 「不認得的 `error.type` 視為伺服器端錯誤，對應 `.serviceUnavailable(statusCode: 500)`」改成 `.invalidResponse`。原決策的理由是「官方文件寫明之後可能出現新類型，而串流中途的錯誤都發生在伺服器端」。
- 「事件內容無法解碼時丟出 `.invalidResponse`」不再包含「有 `error` 物件但沒有 `error.type`」，這種情況改成 500。
- 該決策其餘內容仍然有效。`Supersedes` 是整個決策一個旗標，標了會讓整個決策顯示為不再有效，所以比照 `01-extract-chat-stream-skeleton` 的做法不標；規劃初稿標了，`spectra decisions` 因此把整個決策顯示成失效（規劃審查時 fable 指出）。改寫的位置記在新增供應商清單的「封存 design 中已被改寫的段落」。
- 02 的決策「錯誤依 error.code 與 error.type 分類」中「null 為什麼仍當成 500：……沿用 Anthropic 的處理」，改以本決策的共同規則為依據。

- **共同規則**（chat-client 的「Unrecognized stream errors」）：
  - 有錯誤代碼但供應商不認得：回報 `.invalidResponse`，說明帶代碼與訊息，不可重試。
  - 完全沒有代碼：回報 `.serviceUnavailable(statusCode: 500, retryAfter: nil)`，可重試。
- **規則集中在一個函式**：`LKAICore` 新增 `package static func unrecognizedStreamError(code: String?, message: String?) -> LKAIError`，放在 `LKAIError` 的 Internal Method 區。
  - `code` 不為 nil：`.invalidResponse(reason: "Unrecognized stream error code \(code): \(message ?? "no message")")`。
  - `code` 為 nil：`.serviceUnavailable(statusCode: 500, retryAfter: nil)`，不看 `message`。
  - 兩家供應商串流的「都對應不到」分支都改呼叫它，Gemini 也一樣。說明文字只在這裡組出，第三家不會寫出不同的格式。
- **錯誤代碼與「無法解碼」的分界由各家 spec 寫明**（規劃審查時 fable 指出）：
  - Anthropic 以 `error.type` 為錯誤代碼；資料不是 JSON 或沒有 `error` 物件時無法解碼。
  - OpenAI 以 `code` 為錯誤代碼；`error` 事件的資料是 JSON 物件、而且 `code` 與 `message` 出現時是字串或 null，就解得出來，沒有 `code` 視同 null；`code` 是數字這類型別不對的資料無法解碼。spec 加兩列寫明（規劃第二輪審查時 opus 與 fable 指出）。
  - 所以同一種殘缺的錯誤事件，兩家可能一邊是 `.invalidResponse`、一邊是 500。這和使用者延後的「OpenAI 串流 `error` 事件的欄位全是 Optional」是同一件事，chat-client 不宣稱分界一致，只要求各家寫明。Gemini 有兩種錯誤格式，分界由 `04-add-gemini-provider` 決定，列進清單。
- **HTTP 不受這條規則管**：HTTP 錯誤回應有狀態碼可以判斷，供應商分類不了時交給預設的狀態碼分類。所以同一個不認得的代碼，在 HTTP 500 是可重試，在串流是不可重試。這是刻意的差別，寫進 chat-client 的需求，避免之後被當成不一致去修。
- **為什麼照 OpenAI 的做法**：
  - 02 的決策「錯誤依 error.code 與 error.type 分類」：新代碼多半是政策性阻擋這類不可重試的錯誤；當成可重試的 500，App 會一直重送被擋下的請求。OpenAI 的 `cyber_policy` 被重送太多次，整個組織的存取會被暫停。
  - `.invalidResponse` 的說明帶代碼，之後要補對應時有線索；`.serviceUnavailable` 不帶說明。
  - Gemini 的錯誤代碼也混合了伺服器問題與 `safety`、`quota_exceeded` 這類不可重試的錯誤（見 Context），和 OpenAI 同型。
  - `isRetryable` 在三家的意思一致，符合 `add-chat-abstraction-anthropic` 的目標「讓 App 換供應商時不必改錯誤處理」。
- **Anthropic 的兩處行為改變**：
  - 不認得的 `error.type`：從可重試的 500 改成 `.invalidResponse`。
  - 有 `error` 物件但沒有 `error.type`：`Detail.type` 改成 `String?`。串流中從「無法解碼」的 `.invalidResponse` 改成 500，與 OpenAI 的 null 代碼一致；HTTP 照舊回傳 nil，交給預設分類。
  - 外層不是 JSON，或沒有 `error` 物件時，仍然無法解碼，不受影響。spec 加一列 `{"type":"error"}` 寫明這一點。
  - 說明跟著改寫：`LKAnthropicErrorBody` 與 `Detail.lkaiError(statusCode:retryAfter:)` 的「類型不認得時回傳 nil」改成「沒有類型或類型不認得時」，`Detail.type` 加上「沒有時為 nil」，`LKAnthropicClient.httpError(statusCode:headers:body:)` 的 Returns 同樣補上，`LKAnthropicStreamState.handle(_:)` 拿掉「依規格以 500 處理」。
- **`invalidResponse(reason:)` 的公開說明**：目前寫「供應商回傳的內容不符預期，無法解讀」。改寫成也包含「串流中供應商回報、但本套件不認得的錯誤代碼」，`reason` 帶供應商的代碼與訊息，App 才不會只當成套件或協定出錯（規劃第二輪審查時 fable 指出）。只改文字，在 3.1 處理。
- **OpenAI 的行為不變**：`streamError` 的「其他不是 null 的代碼」與 null 代碼兩個分支、`response.failed` 沒有 `response.error` 的分支改呼叫新函式。說明文字從「Unexpected error code」改成「Unrecognized stream error code」；spec 只要求說明含代碼與訊息，測試不受影響。
- **代價**：Anthropic 之後若出現新的暫時性伺服器錯誤，App 不會自動重試，要使用者自己再送一次。最壞的情況是少重試一次，比自動重送被擋下的請求安全。
- 考慮過的替代方案：
  - **照 Anthropic 的做法**：政策性阻擋類的新代碼會被自動重送，否決。
  - **不訂共同規則，各家各自決定**：App 依 `isRetryable` 重試時，三家的行為不一致，否決。
  - **標 `Supersedes`**：會讓整個 Anthropic 對應的決策顯示為失效，否決，理由見上。

### Context window limit 只適用於分開回報的供應商

- chat-client 的「Context window limit」改成：只有把「context window 塞滿」和「達到輸出上限」分開回報的供應商，才回報 `.contextWindowExceeded`；分不開的供應商回報 `.maxOutputTokens`，由該供應商的 spec 寫明。
  - 依據：OpenAI 兩種情況都回 `max_output_tokens`（02 的決策「Responses API 沒有 context window 的結束原因」）；Gemini 達到上限時只有 `status: incomplete`，沒有附原因（見 Context）。
  - `add-chat-abstraction-anthropic` 的決策「生成途中塞滿 context window 以獨立的結束原因回報」不受影響：Anthropic 分得開，仍然以獨立的原因回報。
- 新增情境「Provider reports a full context window as the output token limit」，以 OpenAI 既有的結束事件測試佐證，不另寫測試：該測試的 `max_output_tokens` 列就是這個情境。情境的文字用該測試交出的 `"Hel"`。
- **`LKAIFinishReason` 只改 `///` 說明**：
  - `.maxOutputTokens`：寫成「有些供應商在生成途中塞滿 context window 時也回報這個原因，例如 OpenAI；在這些供應商上調高輸出上限不一定有用」。
  - `.contextWindowExceeded`：寫成「只有把兩種原因分開回報的供應商才會回報，目前只有 Anthropic；其他供應商在生成途中塞滿時以 `.maxOutputTokens` 出現」。
  - 保留原本說明的提示：輸入在生成前就超過上限時，供應商以錯誤拒絕請求，通常是 `.invalidRequest`，不是這個結束原因。
  - 拿掉「其他供應商由各自的 change 查證」這句。
  - Gemini 由 `04-add-gemini-provider` 加進說明，本 change 不提還沒實作的供應商。

### refused 的 detail 說明補上隱私提醒

- `LKAIError.refused(detail:)` 的 `///` 改寫：detail 是供應商給的拒答原因，各家格式不同，可能是類別代碼、錯誤代碼，或模型寫的說明文字；模型寫的文字可能引用使用者的內容，記錄 log 時要比照使用者的內容處理。保留「只適合記錄 log，不適合依內容判斷」。
- 只改說明文字，不改型別與 spec。
- `LKOpenAIClient` 原有的提醒保留，因為它說明的是 OpenAI 的 detail 是哪一段文字。
- 這處理 02 的決策「拒答文字作為 refused 的 detail，content_filter 以固定字串表示」留下的隱私說明。

### 新增供應商的清單取代 config.yaml 的層層指標

**Supersedes**: 02-add-openai-provider / config.yaml 的指標加上本 change

- `01-extract-chat-stream-skeleton` 的決策「config.yaml 的指標改為同時指向本 change」在 02 時已被取代，但當時沒有標；本決策也取代它。`Supersedes` 只寫得下一個，所以在這裡點名。
- **新增 `docs/adding-a-provider.md`**，正體中文，是新增供應商時唯一要讀的清單。
- **清單的章節**：
  1. **怎麼使用這份清單**：
     - **權威順序**：系統的行為以 spec 為準；清單是流程、跨供應商的事實與索引，和 spec 不同時修正清單。封存的 design 只記錄當時的決定，和清單不同時以清單為準。
     - **更新時機**：新增供應商的 change，以及修改 chat-client spec、任一供應商 spec 或共同流程的 change，封存前都要檢查並更新清單。
  2. **開始前要做的事**：
     - 逐列核對供應商對照表。新供應商的一欄以官方文件查證；能送實際請求的項目以實際請求確認，寫上日期與方式。文件與實際回應不同時，以實際回應為準並記錄差異。這是 Gemini 查證時的教訓，見 Context。
     - 處理第 6 章與第 7 章中屬於該供應商的項目。
  3. **必須遵守的規則**：來源是三份封存 design 與本 change 中仍然有效的決策，每一條註明出處的 change 與決策。至少包含：
     - 遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只寫 `makeStream(for: request)`，不自行建立 `Task`。
     - 每條串流的狀態與結束判斷由供應商的 mapper 持有。
     - 解碼一律經 `LKAISnakeCaseJSON`。
     - 不為自己的格式修改 `LKAICore` 的共用公開型別，只改說明文字可以。
     - 不認得的串流錯誤用 `LKAIError.unrecognizedStreamError(code:message:)`；供應商的 spec 寫明哪個欄位算錯誤代碼、資料缺到什麼程度算無法解碼，串流錯誤的範例表要有「不認得的代碼」與「沒有代碼」兩列。
     - 自己分類 HTTP 5xx 時讀 `retry-after`；能回傳 nil 交給預設分類時就回傳 nil。
     - 分不開 context window 塞滿與輸出上限時回報 `.maxOutputTokens`，並寫進 `LKAIFinishReason` 的說明與該供應商的 spec。
     - 金鑰不出現在三種描述與錯誤裡，由測試檢查。
     - 共同流程的分支不在供應商的測試重寫一份；SSE 分框用 `LKAITestSupport` 的 helper。
     - 有伺服器端保存的供應商預設不保存，由 App 在建立 client 時選擇。
     - 實際 API 測試只在設定 `LKAI_<供應商>_API_KEY` 時執行，由 owner 手動跑；金鑰存在 Keychain 的 `lkai-<供應商>-api-key`，超過 128 字元的金鑰要用 `-w "$(pbpaste)"` 存。
     - 型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加。
     - 端點固定為官方網址；不提供思考深度與取樣參數。
  4. **供應商對照表**：三欄依序為 Anthropic、OpenAI、Gemini，每欄寫上查證日期與方式。
     - 列沿用 `add-chat-abstraction-anthropic` 的 Context 表，再加上錯誤格式、串流的結束方式、伺服器端保存、5xx 的 `Retry-After`、不認得的串流錯誤五列。
     - Anthropic 一欄依第一份 design 的表與 `anthropic-provider` spec；OpenAI 一欄依 02 的 Context 與 `openai-provider` spec；Gemini 一欄依本 design 的 Context。
  5. **封存 design 中已被改寫的段落**：一張「原位置 → 現行依據」的表，讓讀封存 design 的人知道哪一段已經失效（規劃審查時 fable 指出）。
     - **收錄標準**：封存 design 中被之後的 change 改寫的決策、決策理由、流程與結構。行為本身以 spec 為準，不另列行為；但封存 design 裡描述該行為、而且已經不成立的句子要列。
     - 至少包含：
       - 被取代的 `config.yaml` 指標點名的八項：第一份 design 的「生產端 task 的擁有權」、「`LKAITestSupport` 不設測試 target」、Open Questions 的抽出共同流程三項以 01 為準；第一份 Open Questions 的輸入超過 context window 的錯誤、只 `import LKAIKit` 的使用端檢查，以及 01 Open Questions 的共同流程分支的測試位置、SSE 分框的測試 helper、金鑰遮蔽五項以 02 為準。
       - 第一份 design 的決策「Anthropic 串流事件的對應規則」中 `error` 事件的兩項，以 03 為準。
       - 第一份 design 的決策「錯誤以 LKAIError 統一分類並標示可否重試」列的 `serviceUnavailable(statusCode: Int)`，以 03 為準。
       - 02 的決策「錯誤依 error.code 與 error.type 分類」中 null 沿用 Anthropic 的理由，以 03 為準。
       - 02 的決策「Responses API 沒有 context window 的結束原因」中「`LKOpenAIClient` 做不到這條需求」的敘述，以 03 修改後的「Context window limit」需求為準。
       - 01 與 02 的 `config.yaml` 指標決策，以 03 為準。
       - 02 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」，預定由 04 改寫。
  6. **下一家供應商（`04-add-gemini-provider`）已定好的事**：使用者在 2026-11-22 為 Gemini 決定的事項。
     - **生命週期**：04 封存時，把這一章的內容移進對照表與規則，清空這一章，章名改成再下一家供應商。
     - 使用 Interactions API 的 `v1`，預設送 `store: false`，App 可以改成保存。
     - 文字只取 `model_output` 步驟的 `step.delta`；結束看 `interaction.completed` 的 `status`，`completed` 為完成，`incomplete` 為 `.maxOutputTokens`，其他狀態為錯誤；其餘事件一律略過。
     - 實際模型取自 `interaction.completed` 的 `model`。
     - `outputTokens` 等於 `total_output_tokens` 加 `total_thought_tokens`。
     - 錯誤要處理 Interactions 與 Google 通用兩種格式；後者交給預設分類。
     - 串流錯誤的錯誤代碼是哪個欄位、資料缺到什麼程度算無法解碼，由 04 依兩種格式決定，寫進 04 的 spec。Google 通用格式的 `code` 是數字。
     - 實際 API 測試用 `gemini-3.5-flash-lite`，只檢查模型不是空字串。
     - 第一組任務：測試 helper 搬進 `LKAITestSupport`，以及 `LKAICore` 的 `package` 金鑰包裝型別。
       - 要搬的 helper：`optionalField(_:_:)`、`jsonObject(from:)`、`jsonFragment(from:)`、`isInvalidResponse(_:)`，以及本 change 之後兩家測試都有的 `Expectation.invalidResponse(containing:)` 與 `matches(_:_:)`。
       - 三家原本的三個遵循保留。這會修改 02 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」，使用者已同意，由 04 的 design 記錄。
     - `makeURLRequest(for:)` 與 `encodeBody(for:)` 不收進 `LKAICore`：02 設的條件「Gemini 要統一加標頭或改編碼時」沒有成立。
     - 還沒實測的項目：串流中途的 `error` 事件、被安全過濾擋下、503 是否帶 `Retry-After`、輸入超過 context window 時 `v1` 回的狀態碼。
  7. **Open Questions 的對帳**：三份封存 design 的 Open Questions 逐項列出，每項標成「已解決」（附出處）、「屬於下一家」或「留給之後」。
     - 已解決的例子：Gemini 的 API 選擇與 `candidatesTokenCount`、01 的「Gemini 沒有獨立的結束事件」（Interactions 有 `interaction.completed`）、輸入超過 context window 的專屬錯誤（Anthropic 與 OpenAI 都沒有，02 的條件不成立；Gemini 的實際回應列在第 6 章待實測）、02 的 `max_output_tokens` 最小值（Gemini 只要求大於 0，和共用檢查相同）。
     - 留給之後的例子：`makeLines(from:)` 的寫法、`LKAITestWaiting.waitUntil(_:)` 之後要對同一個條件斷言、Ollama 的 NDJSON、`OpenAI-Organization`／`OpenAI-Project` 標頭、OpenAI 串流 `error` 事件全是 Optional 的欄位、只 `import LKAIKit` 的使用端檢查、版本號與 release tag。
- **`config.yaml` 的指標**改成下面這段，取代 02 的文字：

  > 新增供應商的 change 開始前，先讀 `docs/adding-a-provider.md`：逐列核對其中的供應商對照表，遵守其中的規則，並處理其中屬於該供應商的待辦。新增供應商的 change，以及修改 chat-client spec、任一供應商 spec 或共同流程的 change，封存前都要把新的查證結果與決定更新回這份清單。系統的行為以 spec 為準；封存的 design 只記錄當時的決定，與清單不同時以清單為準。以 SSE 串流回答的供應商一律遵循 `LKAIServerSentEventChatStreaming`，不自行建立 `Task`。

  最後一句保留在 `config.yaml`：`spectra instructions` 會把 `config.yaml` 的內容帶進每份 artifact 的說明，最重要的規則留在那裡比較不會漏看。
- **放 `docs/` 而不是 `docs/spectra/`**：`docs/spectra/` 由 Spectra 管理 changes 與 specs，這份清單不是 Spectra 的 artifact。
- **由主對話在第 1、2 組與 3.1 之後撰寫**：Gemini 一欄與已定好的事項來自本 change 的討論與實測，主對話手上有完整的脈絡；清單描述的是實作完成後的狀態，所以等程式碼與說明定案再寫（規劃審查時 fable 指出）。
- 考慮過的替代方案：
  - **照舊在 `config.yaml` 多加一層「以 03 為準」**：每多一家就更難讀，02 已經指出這個問題，否決。
  - **做成 spec**：spec 描述系統的行為，這份清單是開發流程與查證紀錄，否決。

### 測試在既有的參數化測試加列

- 本 change 的行為大多落在既有參數化測試的範例表，所以在原本的 `@Test(arguments:)` 加列或修改期望值，不另寫測試函式。唯一新增的測試函式是 `unrecognizedStreamError(code:message:)` 的範例表測試，放在 `LKAIErrorTests`。
- 新增的 `spectra-scenario` 標記：
  - `LKAIErrorTests` 的新測試：`chat-client / Report a stream error the provider does not recognize` 與 `chat-client / Report a stream error the provider does not recognize / unrecognized stream errors`。
  - `LKOpenAIClientStreamTests` 中標記 `openai-provider / Map terminal events` 的測試：再加一行 `chat-client / Provider reports a full context window as the output token limit`。
- 既有的 119 行標記不刪、不改：chat-client 與兩家 spec 修改的需求，情境名稱都沒有變。
- 先寫測試再實作：每項新行為由主對話先觀察到新的列在實作前失敗。新的期望值要用到兩個 associated value，所以先以行為不變的修改改好 case，再加列（規劃審查時 opus 指出初稿的順序看不到執行時的失敗）。
- Anthropic 測試的 `Expectation` 改成和 OpenAI 相同的形狀：不帶值的 `.invalidResponse` 換成 `.invalidResponse(containing:)`，不比對說明的列用 `.invalidResponse(containing: [])`，並加上 `matches(_:_:)`（規劃第二輪審查時 opus 指出）。兩家各一份的重複，列進清單第 6 章，由 04 搬進 `LKAITestSupport`。

### 實作由 sonnet 在單一 worktree 依序進行

- 01 與 02 的決策「平行實作沿用兩個 git worktree」，是因為兩條工作線的檔案不重疊。本 change 的任務幾乎都改 `LKAIError.swift` 或錯誤測試，而且彼此依賴，分兩條線只會增加合併的工作。
- sonnet 在 `.worktrees/sonnet` 依序做第 1、2 組與 3.1；主對話在它們之後做 3.2 的清單與 `config.yaml`，以及第 4 組的驗收。

## Implementation Contract

**App 看得到的行為**：

- `LKAIError.serviceUnavailable` 多了 `retryAfter: Duration?`，沒有預設值。
  - HTTP 5xx 帶有純數字的 `retry-after` 時，等待時間是該秒數。這包括走預設分類的回應（含 OpenAI 的 5xx），以及 Anthropic 的 `api_error`、`overloaded_error`、`timeout_error`。
  - 串流中途的錯誤一律為 nil。
- **不認得的串流錯誤**：
  - 有代碼時，兩家都回報 `.invalidResponse`，說明含代碼與訊息，`isRetryable` 為 false。
  - 沒有代碼時，回報 `.serviceUnavailable(statusCode: 500, retryAfter: nil)`。
- **Anthropic 串流的兩處改變**：
  - 不認得的 `error.type` 改成 `.invalidResponse`。
  - 有 `error` 物件但沒有 `error.type` 的 `error` 事件改成 500。
- 結束原因、拒答、用量、模型與其他錯誤對應都不變。`errorDescription` 的字串不變。

**介面**：

| 項目 | 形式 |
| --- | --- |
| 公開 case | `case serviceUnavailable(statusCode: Int, retryAfter: Duration?)` |
| package 函式 | `extension LKAIError { package static func unrecognizedStreamError(code: String?, message: String?) -> LKAIError }` |
| 說明文字的格式 | `Unrecognized stream error code <code>: <message>`；沒有訊息時 `<message>` 為 `no message` |
| Anthropic 的錯誤內容 | `LKAnthropicErrorBody.Detail.type` 改成 `String?`；`lkaiError(statusCode:retryAfter:)` 在 `type` 為 nil 時回傳 nil |

**完成後的狀態**（以 `grep` 確認）：

- 每一處建立 `.serviceUnavailable` 都帶 `retryAfter:`：不給預設值，所以由編譯器保證。值的正確性由反向檢查表的第 1、3、4、5 項把關。改完後超過行寬 100 的建立寫法會斷行，所以這一項不用 grep 檢查（規劃第二輪審查時 opus 指出）；1.1 的 grep 在斷行之前執行，仍然有效。
- `Sources/` 與 `Tests/` 內沒有 `case .serviceUnavailable(statusCode: let`。
- `Sources/` 內沒有 `Unexpected error code`、「依規格以 500 處理」與「這和 Anthropic 把不認得的類型當成 500 不同」。
- `Sources/` 內「Unrecognized stream error code」只出現在 `LKAIError.swift`；`Sources/LKAIAnthropic/LKAnthropicStreamState.swift` 與 `Sources/LKAIOpenAI/` 的串流錯誤分支在對應不到時都呼叫 `unrecognizedStreamError(code:message:)`。
- `LKOpenAIClient.httpError(statusCode:headers:body:)` 的說明不再寫「只有走預設分類的 429 限流才由共同流程讀它」。
- `LKAIFinishReason` 的 `git diff` 只有 `///` 說明。
- `docs/adding-a-provider.md` 有決策「新增供應商的清單取代 config.yaml 的層層指標」列的七個章節，內容與最終的程式碼與 spec 一致。
- `docs/spectra/config.yaml` 的指標等於該決策引用的文字；API 演進規則多了決策「服務不可用的錯誤帶上等待時間，不給預設值」引用的那一條。

**驗收**（主對話執行）：

- **建置與測試**：`swift package clean` 後 `swift build` 與完整 `swift test` 零警告。
  - LKAICore 估計為 67 個，比 66 多 1 個 `unrecognizedStreamError` 的測試。其餘 target 的測試數不變：LKAIAnthropic 45、LKAIOpenAI 23、LKAIKitCLI 7、LKAIKit 3、LKAITestSupportTests 3。
  - 這是依「只新增一個測試函式」估計的，以驗收時的 `swift test` 輸出確認。
- **spectra-scenario 標記**：
  - 修改前的 119 行逐行都在。
  - 新增的 3 行是決策「測試在既有的參數化測試加列」列的那 3 行。
  - `spectra coverage` 顯示 `chat-client`、`anthropic-provider`、`openai-provider` 的每個情境與範例都有測試。
- **XcodeBuildMCP（iOS 26 模擬器）**：
  - `LKAIKit` scheme 建置成功、零警告。
  - `LKAIKit-Package` 建置測試只有既有的 `LKAICommandTests.swift` 的 `Process` 錯誤。
- **清單的核對**：清單第 3 到第 7 章與最終的程式碼、spec 逐項比對；第 7 章涵蓋三份封存 design 的每一項 Open Questions。
- **反向檢查**：每項都暫時改壞、觀察到測試失敗後還原。

| 暫時改壞的地方 | 預期失敗的測試 |
| --- | --- |
| 預設分類的 5xx 不讀 `retry-after` | chat-client 狀態碼範例表的 503 `5` 列、OpenAI HTTP 錯誤範例表的 503 列 |
| 預設分類的 5xx 以 `Int(_:)` 解析 `retry-after` | chat-client 狀態碼範例表的 503 `-1` 列 |
| Anthropic 的 `overloaded_error` 不帶等待時間 | Anthropic HTTP 錯誤範例表的 529 `retry-after: 10` 列 |
| Anthropic 的 `api_error` 不帶等待時間 | Anthropic HTTP 錯誤範例表的 500 `retry-after: 3` 列 |
| Anthropic 的 `timeout_error` 不帶等待時間 | Anthropic HTTP 錯誤範例表的 504 `retry-after: 7` 列 |
| `unrecognizedStreamError` 對有代碼的錯誤回 500 | `unrecognizedStreamError` 範例表有代碼的兩列、OpenAI `new_unknown_code` 的兩列（`error` 事件與 `response.failed`）、Anthropic `new_unknown_error` 列 |
| `unrecognizedStreamError` 的說明不帶訊息 | `unrecognizedStreamError` 範例表的第一列、OpenAI `new_unknown_code` 的兩列、Anthropic `new_unknown_error` 列 |
| `unrecognizedStreamError` 對沒有代碼的錯誤回 `.invalidResponse` | `unrecognizedStreamError` 範例表沒有代碼的兩列、OpenAI null 代碼列與 `response.failed` 沒有 `response.error` 的列、Anthropic 沒有 `type` 的串流列 |
| Anthropic 串流對應不到時改回 `.serviceUnavailable(statusCode: 500, retryAfter: nil)` | Anthropic `new_unknown_error` 列 |
| `Detail.type` 改回非 Optional | Anthropic 沒有 `type` 的串流列 |
| `lkaiError` 在 `type` 為 nil 時當成 `invalid_request_error` | Anthropic HTTP 錯誤範例表的 400 沒有 `type` 列、Anthropic 沒有 `type` 的串流列（`lkaiError` 由 HTTP 與串流共用） |

**範圍**：

- 在範圍內：`LKAICore` 的 `LKAIError` 與 `LKAIFinishReason`、兩家的錯誤對應與說明、它們的測試、三份 spec、`docs/adding-a-provider.md`、`config.yaml`。
- 不在範圍內：見 Non-Goals。Gemini 的任何程式碼都不在本 change。

## Risks / Trade-offs

- [App 以 `case .serviceUnavailable(statusCode: let code)` 取狀態碼時，`code` 悄悄變成 tuple，沒有警告（實測）] → 目前沒有 App 使用；`///` 寫明正確的比對寫法。BuyLedger 整合時照 `///` 寫。
- [35 處要補 `retryAfter: nil`，機械式修改可能改錯值] → 漏改的地方會編譯失敗；1.1 是行為不變的修改，以既有測試的名稱、期望值與測試數不變把關。會讀標頭的四個地方都有範例列與反向檢查。
- [Anthropic 之後出現新的暫時性伺服器錯誤時不會自動重試] → 說明帶 `error.type`，看到 log 後再補對應；見決策「不認得的串流錯誤以 unrecognizedStreamError 統一回報」的代價。
- [同一種殘缺的錯誤事件，Anthropic 與 OpenAI 一邊是 `.invalidResponse`、一邊是 500] → 各家 spec 寫明分界；和延後的「OpenAI 串流 `error` 事件全是 Optional」一起處理，列在清單第 7 章。
- [Gemini 的查證只有一天、9 次請求，文件與實際回應有四處不同] → 寫進清單時標明日期與方式；`04-add-gemini-provider` 開始時依清單的「開始前要做的事」重新核對。
- [Anthropic 的 529 是否帶 `retry-after` 沒有查證] → 有帶就讀，沒帶就是 nil，兩種都正確。
- [清單是手寫的文件，沒有測試檢查它和程式碼一致] → `config.yaml` 的指標寫明更新時機；本 change 的 4.1 核對一次，之後的 change 審查時一併檢查。

