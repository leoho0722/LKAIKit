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
  - 修改 `LKAIKitCLI`（`lkai`）的 change。
- **來源**：本清單由 `03-revise-chat-client-contract` 建立，取代 `docs/spectra/config.yaml` 原本一層層指向封存 design 的指標。

## 2. 開始前要做的事

1. **逐列核對第 4 章的供應商對照表**：
   - 新供應商的一欄，以官方文件查證；能送實際請求的項目，以實際請求確認。每一列寫上查證的日期與方式。
   - 文件和實際回應不同時，以實際回應為準，並記錄差異。Gemini 查證時，文件與實際回應有六處不同（見第 4 章 Gemini 一欄），只看文件會寫錯：
     - 文件寫思考步驟「MUST」照原樣送回，實測只送文字也成功。
     - 文件寫的 `interaction.in_progress`，實際是 `interaction.status_update`。
     - 文件寫的錯誤代碼 `model_not_found`，實際是 404 `not_found`。
     - 文件一處用量範例寫成 `prompt_tokens`、`completion_tokens`，實際是 `total_*` 欄位。
     - thinking 頁的範例把回答的第一段文字放在 `step.start` 的 `step.content`、思考摘要放在 `summary`，實測的 `step.start` 只有 `type`。
     - 同一個範例的 `interaction.completed` 沒有 `model`，實測 `interaction.created` 與 `interaction.completed` 都帶。
   - 另有一處文件自己前後不一致、還沒有實測：`failed` 的錯誤欄位是 `errors` 還是 `error`。
   - 實際請求用最便宜的模型、很短的輸出上限，費用記在 design 的 Context。
2. **處理第 6 章與第 7 章中屬於這家供應商的項目**，在 design 的 Context 寫明每一項怎麼處理。
3. **讀第 3 章的規則**，在 design 中凡是偏離其中一條的地方，都寫成決策並說明理由。

## 3. 必須遵守的規則

每一條後面的括號是出處：change 名稱與決策標題（`add-chat-abstraction-anthropic` 簡稱「第一份」）。這份清單中只寫編號的「01」到「04」，指 2026-11-22、23 的那一組 change（`01-extract-chat-stream-skeleton`、`02-add-openai-provider`、`03-revise-chat-client-contract`、`04-add-gemini-provider`）；之後的 change 編號會和這一組重複，所以一律寫完整名稱（例如 `01-add-ci`）。

**架構與命名**

- 供應商 target 只依賴 `LKAICore`，`LKAIKit` 總成重新匯出所有 library target，App 只要 `import LKAIKit`。（`add-swift-package-foundation`「採用多 target 分層：LKAICore、LKAIKit 總成與 LKAIKitCLI」）
- 供應商 target 的頂層型別以 `LK<供應商>` 開頭，例如 `LKOpenAIClient`；型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加，例如 `LKAIOpenAITests`。（`add-swift-package-foundation`「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」；`02-add-openai-provider`「型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加」）
- 非本 package 的型別遵循本 package 的 `public` protocol，只能寫在 `LKAICore`。（第一份「外部型別遵循本 package 的 public protocol 只能寫在 LKAICore」）
- 端點固定為供應商的官方網址；不提供思考深度、推理設定與取樣參數，一律用 API 的預設值。（第一份 Non-Goals）
- 新增供應商時照著 Gemini 的實作做。參考實作是 `Sources/LKAIGemini/` 與 `Tests/LKAIGeminiTests/`，新供應商的檔案，角色與它對應。（`04-add-gemini-provider` 的實作審查）
  - `Sources/LKAIGemini/` 每個檔案的角色：
    - `LKGeminiClient.swift`：client，包含兩個 `init`、三個描述遵循、`stream(_:)`、`makeURLRequest(for:)`、`httpError(statusCode:headers:body:)` 與 `makeEventMapper()`。
    - `LKGeminiInteractionsRequestBody.swift`：請求內容，以 `JSONEncoder()` 編碼。
    - `LKGeminiStreamEvent.swift`：串流事件的解碼，依事件種類欄位分派，經 `LKAISnakeCaseJSON` 解碼。
    - `LKGeminiStreamState.swift`：mapper，遵循 `LKAIServerSentEventMapping`，持有每條串流的狀態，把事件對應成對話事件、結束資訊或錯誤。
    - `LKGeminiErrorBody.swift`：Interactions 格式的錯誤內容；它的 `Detail` 是 HTTP 錯誤、串流的 `error` 事件與 `failed` 的 `errors` 共用的型別。
    - `LKGeminiGoogleErrorBody.swift`：Google 通用格式的錯誤內容。
  - 檔名與取捨的三點（比對 `Sources/LKAIAnthropic/`、`Sources/LKAIOpenAI/` 與 `Sources/LKAIGemini/` 的檔名）：
    - 請求內容的檔名是 `LK<供應商><API 名>RequestBody`，例如 `LKOpenAIResponsesRequestBody`、`LKAnthropicMessagesRequestBody`，Gemini 的 `LKGeminiInteractionsRequestBody` 同樣是這個格式。
    - 第二種錯誤格式的檔案（Gemini 的 `LKGeminiGoogleErrorBody`）只在供應商有不只一種錯誤格式時才需要，Anthropic 與 OpenAI 各只有一個錯誤格式的檔案。
    - 供應商專屬的公開設定另開檔案，例如 Anthropic 的 `LKAnthropicRefusalFallback`。
  - 錯誤分類只有兩個入口：串流中的錯誤用 `streamError`，HTTP 錯誤用 `httpError(statusCode:)`，都在 `LKGeminiErrorBody.Detail`；`LKOpenAIErrorBody.Detail` 是同樣的名稱與分工。
  - `Tests/LKAIGeminiTests/` 每個檔案的角色：
    - `LKGeminiClientTests.swift`：請求內容、回應保存設定、`Mirror` 與金鑰遮蔽。
    - `LKGeminiClientStreamTests.swift`：串流的文字、結束、實際回應的模型與用量。
    - `LKGeminiClientErrorTests.swift`：HTTP 錯誤與串流 `error` 事件的範例表。
    - `LKGeminiClientLiveTests.swift`：實際 API 測試。
    - `LKAIServerSentEvent+GeminiEvents.swift`：事件建構函式，組出替身要推送的 SSE 事件。
    - `LKGeminiClientTestSupport.swift`：測試共用的請求、建立 client 的 helper 與預期的結束事件。
  - 新增供應商要動的既有檔案：`Package.swift` 的三處（新 target、新測試 target、`LKAIKit` 的依賴）、`Sources/LKAIKit/Exports.swift`（重新匯出新 target）、`Tests/LKAIKitTests/ExportsTests.swift`（只 `import LKAIKit` 就能建立新 client 的測試）。
  - 新增供應商時 `lkai` 也要跟著加 `--provider` 的值，要動的既有檔案（`add-cli-chat-command`「新增供應商時 CLI 要跟著加 --provider 的值」）：
    - `Sources/LKAIKitCLI/LKAIChatProvider.swift`：新的 case、`apiKeyEnvironmentName` 的分支與 `makeClient(apiKey:urlSession:)` 的分支。
    - `Tests/LKAIKitCLITests/LKAIChatProviderTests.swift`：client 型別與 `description`、環境變數名稱、`rawValue` 與 `allCases` 的各列。
    - 其他逐家列出供應商的 CLI 測試（`Tests/LKAIKitCLITests/` 內）：
      - `LKAIChatInputTests` 的 `init_沒給apiKey_讀所選供應商的環境變數`：各家一列，測試內的 `environment` 也要加上新供應商的變數。
      - `LKAIChatInputTests` 的 `init_違反一條規則_丟出該規則的錯誤且訊息含指定的詞`：每家缺少金鑰各一列，訊息要寫出該家的環境變數。
      - `LKAICommandTests` 的 `execute_指定供應商_交給makeClient的輸入有對應的供應商與金鑰`：各家一列。
    - cli-chat spec 的「provider values」與「environment variables」兩張表。
    - `Tests/LKAIKitCLITests/LKAICommandLiveTests.swift`：加一個測試函式，只在新供應商的環境變數有設定時執行，模型與 library 的實際 API 測試相同。
    - String Catalog 不必修改：說明中的環境變數清單由 `LKAIChatProvider.allCases` 產生，字串裡沒有寫任何供應商或環境變數的名稱。

**串流的共同流程**

- 以 SSE 串流回答的供應商遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只寫 `makeStream(for: request)`，不自行建立 `Task`。（`01-extract-chat-stream-skeleton`「SSE 對話的共同流程以 LKAIServerSentEventChatStreaming 的 extension 提供」「串流的背景 task 只在 LKAIChatStream.init(producing:) 建立」）
- 每條串流的事件狀態與「何時結束」的判斷，由供應商的 mapper（遵循 `LKAIServerSentEventMapping` 的型別）持有。不認得的事件一律略過。（`01-extract-chat-stream-skeleton`「每條串流的事件狀態與結束判斷由供應商的 mapper 持有」）
- 解碼一律經 `LKAISnakeCaseJSON`，不自己建立 `JSONDecoder()`；經它解碼的型別，手寫的 `CodingKeys` 用 camelCase、不寫 raw value，因為它先把 JSON 的鍵轉成 camelCase 再比對，寫 raw value 會比對不到。以 `JSONEncoder()` 編碼的請求內容沒有這個策略，照舊寫 raw value，例如 `LKGeminiInteractionsRequestBody` 的 `max_output_tokens`。（`01-extract-chat-stream-skeleton`「snake_case JSON 的解碼設定收成 LKAISnakeCaseJSON」；`04-add-gemini-provider`「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」）
- 事件的巢狀欄位只在用得到時才解碼：依同一則事件的其他欄位（步驟類型、狀態、片段類型）決定要不要讀某個欄位，比照 `LKAnthropicStreamEvent` 的 `ContentBlock` 與 `Delta`，以及 `LKGeminiStreamEvent` 的 `Step`、`TextPart` 與 `Interaction`。Optional 只容許欄位不存在或為 null，欄位存在但型別不對時仍會失敗，所以只寫成 Optional 擋不住；供應商之後新增的步驟或事件，以及只依文件、還沒實測的欄位，都不該讓串流失敗。已知的例外：`LKOpenAIStreamEvent` 的 `Response` 不論事件種類都解碼全部欄位，見第 7 章。（`04-add-gemini-provider`「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」）
- 解碼端依判別欄位（步驟類型、狀態）做的判斷，只在解碼時做一次，結果帶在事件裡，mapper 不再比對同一個字串：兩邊各比對一次時，只改一邊會讓文字一邊交出、一邊略過，或讀不到 `errors`，而且沒有錯誤可以發現。比照 `LKGeminiStreamEvent` 的 `stepStart(index:isModelOutput:texts:)`（帶「是不是回答步驟」）與 `failed(firstError:)`（`failed` 解成獨立的事件）。（`04-add-gemini-provider`「解碼端的判斷結果帶在事件裡，mapper 不再比對字串」）

**共用型別與 API 演進**

- 不為自己的格式修改 `LKAICore` 的共用公開型別；需要修改時另開 change 修改 chat-client spec。只改說明文字可以。（`docs/spectra/config.yaml` 的 API 演進規則；`02-add-openai-provider` Non-Goals）
- 公開 enum 標 `@nonexhaustive`；公開 struct 新增欄位時 `init` 的新參數給預設值；公開 enum 的 case 增減 associated value，會破壞 App 建立與比對這個 case 的寫法（給新的 associated value 預設值只保住建立的寫法），第一個 release tag 之後要加資料時改用 struct。（`config.yaml` 的 API 演進規則；第一份「公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值」；`03-revise-chat-client-contract`「服務不可用的錯誤帶上等待時間，不給預設值」）
- token 用量依 `LKAIUsage` 的統一口徑：`inputTokens` 包含讀自快取的部分，`outputTokens` 包含思考或推理的部分。供應商的欄位口徑不同時，在 client 內換算。（第一份「token 用量以統一口徑放進共用型別」）
- 實際產生回應的模型取自供應商的回報，不用請求的模型代替；沒有回報時為 nil。（第一份「實際回應的模型放進共用結果」）
- `LKAICore` 的 `LKAIError`、`LKAIFinishReason` 與 `LKAIChatStreamEvent` 增減 case 時，`lkai` 會因為窮舉而編譯失敗：它對這三個 enum 的 `switch` 都列出每個 case、不寫 `@unknown default`（同一個 package，編譯器把它們當成可以窮舉），所以新增的 case 一定會被處理。其中 `LKAIError` 與 `LKAIFinishReason` 的 case 也列在 cli-chat spec 的「detail lines」與「finish reasons」兩張表，要一併更新。（`add-cli-chat-command`「同一個 package 的 @nonexhaustive enum 一律窮舉」）
  - 編譯器不會提醒、要手動更新的測試清單：
    - `LKAIError`：`LKAIErrorDetailsTests` 的範例表、`LKAIChatRunnerTests` 中 `run_invoke失敗_…` 的範例表、`LKAIOutputLanguageTests.errors`。
    - `LKAIFinishReason`：一則 `warning.cli.*`（`LKAICLIText` 的 case 與兩種語言的翻譯），以及 `LKAIChatRunnerTests.finishReasonCases`。

**錯誤**

- HTTP 錯誤由 `httpError(statusCode:headers:body:)` 依供應商的錯誤格式分類，分類不了就回傳 nil，交給共同流程的預設狀態碼分類。（第一份「HTTP 狀態碼的預設分類放在 LKAICore，供應商依自己的錯誤格式覆寫」）
- 供應商的錯誤格式不只一種時，每種都在 `httpError(statusCode:headers:body:)` 中處理，依序嘗試，都不符合才回傳 nil。狀態碼之外的金鑰錯誤要辨識出來：Gemini 收到錯誤的 `AIza` 格式金鑰時回 400，預設分類會把它當成沒有訊息的 `.invalidRequest`，App 看不出是金鑰錯誤，所以 `LKGeminiClient` 在 Google 通用格式的 `error.details` 有 `reason` 為 `API_KEY_INVALID` 的項目時回報 `.invalidAPIKey`（Google 通用格式見 `LKGeminiGoogleErrorBody`，Interactions 格式見 `LKGeminiErrorBody`）。（`04-add-gemini-provider`「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」）
- 自己分類 HTTP 5xx 時讀 `retry-after`，以 `LKAIError.retryDelay(from:)` 換算；能回傳 nil 交給預設分類時就回傳 nil。建立 `.serviceUnavailable` 時一律明寫 `retryAfter:`，串流中途的錯誤傳 nil。（`03-revise-chat-client-contract`「5xx 的預設分類與 Anthropic 的 HTTP 錯誤讀 retry-after」）
- 串流中對應不到任何錯誤種類的錯誤，一律呼叫 `LKAIError.unrecognizedStreamError(code:message:)`：有代碼回報不可重試的 `.invalidResponse`，沒有代碼回報可重試的 500。（`03-revise-chat-client-contract`「不認得的串流錯誤以 unrecognizedStreamError 統一回報」）
  - 供應商的 spec 要寫明：哪個欄位算錯誤代碼、錯誤資料缺到什麼程度算無法解碼。
  - 供應商 spec 的串流錯誤範例表，要有「不認得的代碼」與「沒有代碼」兩列。
- 政策性阻擋回報 `.refused`，而且 HTTP 與串流兩條路徑得到同一種錯誤。（`02-add-openai-provider`「錯誤依 error.code 與 error.type 分類」）
- 分不開「生成途中塞滿 context window」與「達到輸出上限」的供應商，回報 `.maxOutputTokens`，並寫進 `LKAIFinishReason` 的說明與該供應商的 spec。（`03-revise-chat-client-contract`「Context window limit 只適用於分開回報的供應商」）

**金鑰與隱私**

- API 金鑰不出現在 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡；client 實作三個遵循（`CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable`，只放設定、不放金鑰），由測試逐一檢查。（第一份「LKAnthropicClient 以 API 金鑰與 URLSession 建立，金鑰不出現在診斷輸出」；`02-add-openai-provider`「金鑰遮蔽由每家 client 各自實作三個遵循」）
- 金鑰以 `LKAICore` 的 `LKAIAPIKey` 保存，不用 `String`：它的 `description`、`debugDescription` 都是 `LKAIAPIKey(redacted)`，`customMirror` 沒有子項目，client 漏寫某個遵循或之後加上金鑰欄位時，金鑰仍只會顯示成遮蔽文字。原始值 `unredactedValue` 只在三個地方讀取：`LKAIAPIKey.swift`、各家的 `makeURLRequest(for:)`，以及 `LKAIKitCLI` 的兩處（`LKAICommand.run()` 把金鑰交給 client、`LKAIChatRunner` 遮蔽細節）；公開的 `init(apiKey: String, …)` 在 init 內包裝。（`04-add-gemini-provider`「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」；`add-cli-chat-command`「API 金鑰：--apiKey 優先，其次是供應商的環境變數」）
  - 新增供應商的 change 完成前要做兩個 grep 檢查：`grep -rn 'unredactedValue' Sources | grep -v '///'` 的結果只出現在 `LKAIAPIKey.swift`、各家 client 的 `makeURLRequest(for:)`，以及 `Sources/LKAIKitCLI` 的兩處（`LKAICommand.swift` 的 `run()` 與 `LKAIChatRunner.swift` 的 `redactAPIKey(in:)`，各一行），其他檔案出現就是多讀了一處；`grep -rn 'let apiKey: String' Sources` 沒有結果。沒用 `LKAIAPIKey` 保存金鑰的供應商，金鑰遮蔽的測試照樣通過，因為三個遵循本身就遮得住，只有這兩個檢查抓得到。（`04-add-gemini-provider`「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」；`add-cli-chat-command`「API 金鑰：--apiKey 優先，其次是供應商的環境變數」）
- 有伺服器端保存的供應商預設不保存，由 App 在建立 client 時選擇開啟，參數名一律是 `shouldStoreResponses`，讓 App 換供應商時寫法一致。（`02-add-openai-provider`「回應保存由 App 在建立 client 時選擇，預設不保存」；`04-add-gemini-provider`「回應保存預設關閉，由 App 建立 client 時開啟」）

**測試**

- 共同流程的分支（請求驗證、連線失敗、沒有結束事件、取消與釋放串流）不在供應商的測試重寫一份。（`02-add-openai-provider`「共同流程的分支不在 OpenAI 的測試重寫一份」）
- SSE 分框用 `LKAITestSupport` 的 `LKAIServerSentEventTestSupport.lines(of:)`；與供應商無關的測試 helper 放 `LKAITestSupport`，它不屬於任何 product。（`02-add-openai-provider`「SSE 分框的測試 helper 搬進 LKAITestSupport」；第一份「測試替身放在不屬於任何 product 的 LKAITestSupport target」）
- 錯誤的期望值用 `LKAIErrorTestSupport.Expectation`（`.error(_:)` 與 `.invalidResponse(containing:)`，`matches(_:)` 對 nil 一律不符合）與 `isInvalidResponse(_:)`；JSON 的解析與組裝用 `LKAITestJSON`（`jsonObject(from:)`、`jsonFragment(from:)`、`optionalField(_:_:)`），確認請求內容的欄位是 JSON 布林用 `booleanField(_:in:)`，因為 `NSDictionary` 比對會把 `1` 當成 `true`。`LKAICoreTests` 不依賴 `LKAITestSupport`，所以 `LKAIErrorTests` 保留自己的 `Expectation`，這是已知的例外。（`04-add-gemini-provider`「與供應商無關的測試 helper 收進 LKAITestSupport」；`01-extract-chat-stream-skeleton`「Anthropic 的測試走不到的共同行為在 LKAICoreTests 直接測試」）
- 每個測試上方，依 spec 加 `spectra-scenario: <capability> / <情境>` 標記，有範例時再加 ` / <範例>`。
- 實際 API 測試只在設定環境變數 `LKAI_<供應商>_API_KEY` 時執行，由 owner 手動跑；金鑰存在 Keychain 的 service `lkai-<供應商>-api-key`。超過 128 字元的金鑰要用 `security add-generic-password -s <service> -a "$USER" -w "$(pbpaste)"` 存，`-w` 不帶值時的密碼提示會把超過 128 字元的部分丟掉。（`02-add-openai-provider`「實際 API 測試以 gpt-6-luna 執行，由 owner 手動跑」與任務 4.2 的執行紀錄）

## 4. 供應商對照表

「本套件的處理」是 LKAIKit 對應成共用型別的方式；其餘是供應商 API 的事實。Gemini 一欄標「實測」的項目以實際請求確認，標「文件」的只依官方文件。

| 項目 | Anthropic Messages API | OpenAI Responses API | Gemini Interactions API `v1` |
| --- | --- | --- | --- |
| 查證日期與方式 | 2026-11-21，官方文件與 Claude Code 內建的 Claude API 參考資料（快取日期 2026-11-03）；實際 API 測試以 `claude-opus-5-5` 於 2026-11-22 通過 | 2026-11-22，Context7 收錄的官方文件；實際 API 測試以 `gpt-6-luna` 於 2026-11-22 通過 | 2026-11-22，Context7 收錄的官方文件，以及對 `v1/interactions` 的實際請求：`03-revise-chat-client-contract` 的 9 次，加上 `04-add-gemini-provider` 規劃時再送的（會產生 token 的 3 次、免費的查詢與會被拒絕的請求，主要用 `gemini-3.5-flash-lite`）；實際 API 測試以 `gemini-3.5-flash-lite` 於 2026-11-22 通過 |
| 端點與驗證 | `POST https://api.anthropic.com/v1/messages`；`x-api-key`、`anthropic-version: 2026-10-21` | `POST https://api.openai.com/v1/responses`；`Authorization: Bearer` | `POST https://generativelanguage.googleapis.com/v1/interactions`；`x-goog-api-key`（實測）。文件範例全用 `v1beta`，`v1beta` 在 2026 年 5 月改過一次結構。以 `system_instruction`、`generation_config.max_output_tokens`、`store: false`、`stream: true` 送出串流請求，都被接受（實測）；本套件另帶 `content-type: application/json` |
| 系統指示 | 頂層 `system` | 頂層 `instructions` | 頂層 `system_instruction`，純文字（實測）；本套件只在有系統指示時送 |
| 訊息角色與多輪歷史 | `user`、`assistant` | `input` 訊息陣列，`user`、`assistant` | `input` 步驟陣列：`user_input` 與 `model_output`，`content` 為 `[{"type":"text","text":…}]`（實測）。文件寫思考步驟「MUST」照原樣送回，實測只送文字也成功；本套件每次送完整的對話歷史，只送文字 |
| 輸出上限 | `max_tokens`，必填 | `max_output_tokens`，選填，文件寫最小值 16 | `generation_config.max_output_tokens`，必須大於 0，0 回 400 `invalid_request`（實測）；本套件照原樣送出，小於 1 的值由共同的請求檢查擋下（`LKAIChatRequest.validate()`） |
| 取樣參數 | API 版本 `2026-10-21` 傳 `temperature`、`top_p`、`top_k` 回 400 | 推理模型在 effort 不是 `none` 時，文件要求不要送 `temperature`、`top_p` | 文件寫 Gemini 4 與 3.6 以上的模型忽略自訂的 `temperature`、`top_p`、`top_k`；本套件不送 |
| 伺服器端保存 | 沒有回應保存的參數 | `store` 預設 true，保存至少 30 天；本套件預設送 `store: false` | `store` 預設 true，付費方案保存 55 天（文件）；`store: false` 被接受（實測）。本套件預設送 `store: false`，App 建立 client 時用 `shouldStoreResponses` 開啟（`LKGeminiClient`，與 OpenAI 同名） |
| 串流格式 | SSE，`event:` 與 `data:`；文字在 `content_block_delta` 的 `text_delta` | SSE，`event:` 與 `data:`，`data` 帶 `type`；文字在 `response.output_text.delta` | SSE，`event:` 與 `data:`，`data` 帶 `event_type`，每則事件的 `event:` 名稱都和 `event_type` 相同；另有 `: keep-alive` 註解行（實測）。事件依序為 `interaction.created`、`interaction.status_update`、`thought` 步驟、`model_output` 步驟、`interaction.completed`；每個步驟有 `step.start`、`step.delta`、`step.stop`，都帶 `index`（實測）。文字在 `model_output` 步驟的 `step.delta`，`delta.type` 為 `text`（實測）；thinking 頁的範例把 `model_output` 的第一段文字放在 `step.start` 的 `step.content`，`thought` 的摘要放在 `summary`（文件，實測沒有看到）。本套件以 `event_type` 為準，不看 `event:`；`step.start` 記錄 `index` 與 `step.type`，只交出 `model_output` 步驟中 `delta.type` 為 `text` 的片段，以及 `model_output` 的 `step.start` 帶 `content` 時其中 `type` 為 `text` 的文字，其餘事件略過；`step.content` 只在 `step.type` 為 `model_output` 時讀，`delta.text` 只在 `delta.type` 為 `text` 時讀，而且必須是字串 |
| 串流的結束方式 | `message_delta` 帶 `stop_reason`，`message_stop` 時結束 | `response.completed`、`response.incomplete`、`response.failed` 或 `error`；沒有 `[DONE]` | `interaction.completed`，結果看 `interaction.status`；之後還有 `event: done` 與 `data: [DONE]`（實測）。文件寫的 `interaction.in_progress` 實際是 `interaction.status_update`。文件列的終止狀態還有 `failed`、`requires_action`、`cancelled`；`failed` 時錯誤放在 `interaction.errors`，但文件只在背景執行的說明提到，串流時錯誤以 `error` 事件送出；欄位名稱 safety-settings 的文字與 Go 範例是 `errors`，get-started 的 Python 範例讀的是 `result.error`（以上文件，未實測）。本套件在第一個 `interaction.completed` 或 `error` 事件結束，`[DONE]` 不會交給 mapper；`failed` 取 `errors` 的第一筆，依 `error` 事件的代碼規則回報，`errors` 沒有、為 null 或空陣列時回報可重試的 500，其他形狀回報 `.invalidResponse`；`requires_action`、`cancelled`、其他狀態、沒有狀態與沒有 `interaction` 物件，都回報 `.invalidResponse` |
| 思考內容 | `thinking` 區塊 | reasoning 項目 | `thought` 步驟，串流中只帶 `thought_signature`（實測）；文件寫思考步驟的片段類型是 `thought_signature` 與 `thought_summary`。本套件不交出思考內容 |
| 正常完成 | `stop_reason` 為 `end_turn` 或 `stop_sequence` | `response.completed` | `status` 為 `completed`（實測）；本套件回報完成 |
| 達到輸出上限 | `stop_reason` 為 `max_tokens` | `incomplete_details.reason` 為 `max_output_tokens` | `status` 為 `incomplete`，沒有附原因；`max_output_tokens` 為 20 時，`total_output_tokens` 回報 23，比上限多；Gemma 的輸出上限 16 全用在思考時，回 `incomplete`，`steps` 只有 `thought`，沒有文字（以上實測，後者為非串流）。本套件回報 `.maxOutputTokens`，只有思考時文字為空字串 |
| 生成途中塞滿 context window | `stop_reason` 為 `model_context_window_exceeded`；本套件回報 `.contextWindowExceeded` | 也回報 `max_output_tokens`；本套件回報 `.maxOutputTokens` | 文件的狀態表只寫 `incomplete` 是用完 `max_output_tokens`，沒有獨立的原因；本套件回報 `.maxOutputTokens`，不回報 `.contextWindowExceeded` |
| 輸入在生成前就超過 context window | 沒有專屬代碼 | 沒有專屬代碼 | Interactions 的錯誤表沒有專屬代碼；generateContent 的錯誤表把它列在 500 `INTERNAL` 底下（文件）。沒有測成：`gemini-3.5-flash-lite` 的 `inputTokenLimit` 是 1048576，Gemma 4 26B 是 262144；以 30 萬 token 測 Gemma 時，先撞到免費方案每分鐘 16000 個輸入 token 的限制，回 429（實測）。`v1` 的實際狀態碼未實測，本套件不特別處理：400 `invalid_request` 成為帶訊息的 `.invalidRequest`，500 `api_error` 成為可重試的 `.serviceUnavailable`，見第 7 章 |
| 拒答或被擋 | HTTP 200，`stop_reason` 為 `refusal`，`stop_details` 帶類別；本套件回報 `.refused(detail: 類別)` | 拒答內容（`status` 仍是 `completed`）、`content_filter`、政策性阻擋的代碼（`cyber_policy` 等）；本套件都回報 `.refused` | HTTP 400 或串流中的 `error` 事件，`code` 為 `safety`、`jailbreak`、`prohibited_content` 或 `blocklist`；api-errors 另列 `recitation`、`language`、`spii`、`content_blocked` 與四個 `image_*` 代碼（以上文件，未實測：要觸發安全過濾得送出真的有害的內容）。本套件把這 12 個代碼回報 `.refused(detail: 代碼)`，HTTP 與串流相同；detail 是代碼，不是 `message`，因為 `message` 以「Input blocked:」開頭，可能描述使用者的輸入 |
| 金鑰無效 | 401 `authentication_error` | 401 | 401，Google 通用格式 `"status": "UNAUTHENTICATED"`，外面包一層 JSON 陣列（實測）：錯誤的 `AQ.` 格式金鑰回 401，`ErrorInfo.reason` 為 `ACCESS_TOKEN_TYPE_UNSUPPORTED`；錯誤的 `AIza` 格式（Google 舊格式）金鑰回 400，`status` 為 `INVALID_ARGUMENT`，`reason` 為 `API_KEY_INVALID`；沒帶金鑰時是同一種格式的 403 `PERMISSION_DENIED`，`reason` 為 `ACCESS_DENIED`（以上實測，串流與非串流相同）。本套件在 `error.details` 有 `reason` 為 `API_KEY_INVALID` 的項目時回報 `.invalidAPIKey`，外層是陣列或物件都接受；401 與 403 由預設分類得到 `.invalidAPIKey` 與 `.permissionDenied` |
| 頻率限制與額度 | 429 `rate_limit_error`；`error.details.error_code` 為 `enforced_spend_limit_reached` 時是額度；402 `billing_error`；400 訊息以「You have reached your specified」開頭時是自設的花費上限 | 429，以 `error.code` 分出額度代碼（`insufficient_quota`、`credit_balance_exhausted` 等）與頻率限制（`rate_limit_exceeded`、`slow_down`） | 429 `rate_limit_exceeded`、`quota_exceeded`、`too_many_requests`；402 `payment_required`（文件）。實測的 429 是 Interactions 格式，`code` 為 `too_many_requests`，帶 `retry-after` 標頭，值是秒數（27、72177）；串流請求被限流時，同樣在串流開始前回 HTTP 429。本套件把 `quota_exceeded`、`payment_required` 回報 `.quotaExceeded`，不讀 `retry-after`；其餘 429 由預設分類回報帶 `retry-after` 的 `.rateLimited`，所以每日上限為 0 的 429（實測用的是 `too_many_requests`）會是可重試的限流，App 看等待時間判斷 |
| 服務過載 | 529 `overloaded_error`、500 `api_error`、504 `timeout_error` | 503 `server_is_overloaded`、500 `server_error` | 503 `service_unavailable`（實測，訊息為模型忙碌）；500 `api_error`（文件）。本套件不自己分類 5xx，交給預設分類，回報帶 `retry-after` 的 `.serviceUnavailable` |
| 5xx 的 `Retry-After` | 文件只寫 429 帶；5xx 未查證，有帶就讀 | 文件寫暫時性的頻率限制與 503 過載會帶 | 未實測，503 沒有遇到；預設分類有帶就讀 |
| 錯誤格式 | `{"type":"error","error":{"type","message"}}`，串流中的 `error` 事件相同 | HTTP 為 `{"error":{"code","message","param","type"}}`；串流的 `error` 事件是平的 `{"type":"error","code","message",…}` | Interactions 格式 `{"error":{"code","message"}}`，`code` 是 snake_case（實測：404 `not_found`、400 `invalid_request`、503 `service_unavailable`，文件寫的 `model_not_found` 實際沒出現；`max_output_tokens` 為 10000000 的 400 與模型不存在的 404，都在串流開始前以 HTTP 回報）；Google 通用格式見「金鑰無效」；串流的 `error` 事件為 `{"event_type":"error","error":{"code","message"}}`，例子是 `gateway_timeout`，它不在錯誤代碼表，是文件說的「沒列出的代碼改用 HTTP 狀態的 snake_case 名稱」（文件，未實測：無法以正常請求觸發）。本套件的 `httpError` 先試 Interactions 格式，再試 Google 通用格式：Interactions 格式依序套用被擋下的代碼為拒答、額度代碼為額度用完、401、402、403、429 以外的 4xx 為帶 `error.message` 的 `.invalidRequest`；兩種格式都不符合的回應走預設分類 |
| 不認得的串流錯誤（本套件的處理） | `error.type` 為錯誤代碼；不認得時 `.invalidResponse`，沒有 `type` 時 500，沒有 `error` 物件或不是 JSON 時無法解碼 | `code` 為錯誤代碼；不認得時 `.invalidResponse`，null 或沒有時 500；`code`、`message` 型別不對時無法解碼 | `error.code` 為錯誤代碼；不認得的代碼回報 `.invalidResponse`（說明含代碼與 `message`），null 或沒有時 500；沒有 `error` 物件、不是 JSON，或 `code`、`message` 型別不對（例如 `code` 是數字）時無法解碼，回報 `.invalidResponse`；`failed` 的 `errors` 第一筆套用同一組規則 |
| 實際回應的模型 | `message_start` 的 `message.model`；拒答備援切換時以 `fallback` 區塊的 `to.model` 為準 | 結束事件的 `response.model` | `interaction.created` 與 `interaction.completed` 都帶 `interaction.model`；請求 `gemini-3.5-flash` 時回的是 `gemini-3.6-flash`（以上實測）。thinking 頁的範例只有 `interaction.created` 帶 `model`（文件，和實測不同）。本套件取結束事件 `interaction.completed` 的 `interaction.model`，沒有時為 nil，不取 `interaction.created` 的值 |
| token 用量 | `input_tokens` 不含快取，另有 `cache_creation_input_tokens`、`cache_read_input_tokens`；`output_tokens` 含思考 | `input_tokens` 含 `cached_tokens`；`output_tokens` 含 `reasoning_tokens` | `interaction.completed` 的 `interaction.usage`：`total_input_tokens` 含 `total_cached_tokens`（實測：同一段 5000 token 的請求，第二次快取 2033）；`total_output_tokens` **不含** `total_thought_tokens`（實測：41 + 3 + 528 = 572 = `total_tokens`）。文件一處範例寫成 `prompt_tokens`／`completion_tokens`，實際不是。另有 `input_tokens_by_modality`、`total_tool_use_tokens`、`initial_input_tokens`（實測），本套件不使用。本套件的換算：`inputTokens` 為 `total_input_tokens`，`outputTokens` 為 `total_output_tokens` 加 `total_thought_tokens`（沒有時以 0 相加），`cachedInputTokens` 為 `total_cached_tokens`，`reasoningOutputTokens` 為 `total_thought_tokens`，沒有回報時各自為 nil；缺 `total_input_tokens` 或 `total_output_tokens`，或 `usage` 為 null 時不帶用量 |

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
| 01 的決策「每條串流的事件狀態與結束判斷由供應商的 mapper 持有」中，`error` 事件「不認得的類型丟出 `.serviceUnavailable(statusCode: 500)`」 | `03-revise-chat-client-contract`「不認得的串流錯誤以 unrecognizedStreamError 統一回報」：改成 `.invalidResponse` |
| 第一份的決策「錯誤以 LKAIError 統一分類並標示可否重試」列的 `serviceUnavailable(statusCode: Int)` | `03-revise-chat-client-contract`「服務不可用的錯誤帶上等待時間，不給預設值」：`serviceUnavailable(statusCode:retryAfter:)` |
| 02 的決策「錯誤依 error.code 與 error.type 分類」中「Anthropic 把不認得的 `error.type` 當成 500，是因為它文件列的串流錯誤都是伺服器端問題」 | `03-revise-chat-client-contract`「不認得的串流錯誤以 unrecognizedStreamError 統一回報」：Anthropic 也改成 `.invalidResponse` |
| 02 的決策「錯誤依 error.code 與 error.type 分類」中「null 為什麼仍當成 500：……沿用 Anthropic 的處理」 | `03-revise-chat-client-contract`：改以 chat-client「Unrecognized stream errors」的共同規則為依據 |
| 02 的決策「Responses API 沒有 context window 的結束原因」中「`LKOpenAIClient` 做不到這條需求」 | `03-revise-chat-client-contract`：修改後的「Context window limit」需求只要求分開回報的供應商回報 `.contextWindowExceeded`，OpenAI 符合 |
| 01 的決策「config.yaml 的指標改為同時指向本 change」、02 的決策「config.yaml 的指標加上本 change」 | `03-revise-chat-client-contract`「新增供應商的清單取代 config.yaml 的層層指標」：`config.yaml` 只指向本清單 |
| 02 的決策「金鑰遮蔽由每家 client 各自實作三個遵循」 | `04-add-gemini-provider`「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」：加上 `LKAICore` 的 `package` 金鑰包裝型別，三家 client 以它保存金鑰，三個遵循保留 |
| `03-revise-chat-client-contract` 的決策「新增供應商的清單取代 config.yaml 的層層指標」所列「下一家供應商已定好的事」中，Gemini 的錯誤「要處理 Interactions 與 Google 通用兩種格式；後者交給預設分類」 | `04-add-gemini-provider`「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」：Google 通用格式的 `error.details` 有 `reason` 為 `API_KEY_INVALID` 的項目時回報 `.invalidAPIKey`，其餘才交給預設分類（實測錯誤的 `AIza` 格式金鑰回 400，預設分類會當成 `.invalidRequest`） |
| `04-add-gemini-provider` 的決策「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」中「只有 `makeURLRequest(for:)` 讀 `unredactedValue`」，以及它「完成後的狀態」中 `unredactedValue` 的 grep | `add-cli-chat-command`「API 金鑰：--apiKey 優先，其次是供應商的環境變數」：`LKAIKitCLI` 也讀原始值，共兩處：`LKAICommand.run()` 把金鑰交給 client、`LKAIChatRunner` 遮蔽細節；grep 的結果多出這兩處 |
| `add-swift-package-foundation` 的 Implementation Contract 中 `CommandConfiguration(commandName: "lkai", …, version: LKAIKitInfo.version)` | `add-cli-chat-command`「自訂 -v/--version 旗標取代內建的版本旗標」：`configuration` 不再傳 `version:`，改宣告 `version` 旗標，由 `validate()` 印出版本，才能加上 `-v` |
| `add-swift-package-foundation` 的決策「以行程層級測試驗證 lkai 的輸出分流」中「stdout 有一行剛好是 `USAGE: lkai`」 | `add-cli-chat-command`「說明輸出改以開頭比對用法那一行」：改成「有一行以 `USAGE: lkai `（含結尾空格）開頭」，因為用法改成自訂的兩行 |
| `add-swift-package-foundation` 驗收方式中「`LKAICommandTests` 的行程層級測試」 | `add-cli-chat-command` 的決策「process 測試清掉 LKAI_*_API_KEY」：行程測試改在 `LKAICommandProcessTests`，`LKAICommandTests` 是 in-process 的測試 |

## 6. 下一家供應商

目前沒有已定好的事。

**這一章的生命週期**：之後使用者為下一家供應商決定的事項寫在這一章；那家供應商的 change 封存時，同樣把這一章的內容移進第 3 章的規則、第 4 章的對照表與第 7 章的對帳後清空。

## 7. Open Questions 的對帳

三份封存 design 的 Open Questions，逐項標成「已解決」（附依據）、「屬於下一家」（見第 6 章）或「留給之後」。新的 change 留下 Open Questions 時，也加進這張表。

| 出處 | 項目 | 狀態 | 依據或之後的處理 |
| --- | --- | --- | --- |
| 第一份 | 輸入本身超過 context window 的 HTTP 400 要不要設專屬 case | 已解決：不設 | Anthropic 與 OpenAI 都沒有可辨識的代碼，02 設的條件「至少兩家可辨識」不成立（02「輸入超過 context window 的錯誤不設專屬種類」、03 Non-Goals）；Gemini 沒有測成，`04-add-gemini-provider`「輸入超過 context window 不特別處理」記成風險，不特別處理，之後有實例時再實測（見本表 `04` 的第一項） |
| 第一份 | Gemini 用 generateContent 還是 Interactions API；`candidatesTokenCount` 是否不含思考 | 已解決 | 使用者選定 Interactions API 的 `v1`；用量改看 `total_*` 欄位，`total_output_tokens` 不含思考（03 Context 實測） |
| 第一份 | 調整 `LKAIKitInfo.version` 並打第一個 release tag | 留給之後 | 屬於版本與 release 流程，另行決定 |
| 第一份 | 抽出 `stream(_:)` 的共同骨架，並處理實作審查留下的四項 | 已解決 | `01-extract-chat-stream-skeleton` |
| 第一份 | 只 `import LKAIKit` 的使用端檢查 package | 留給之後 | 使用者決定延後到 BuyLedger 整合（02 Context） |
| 01 | `LKAIHTTPClient.makeLines(from:)` 的 task 寫法是否收進共用的建構方式 | 留給之後 | 等出現第二個建立逐行內容的地方 |
| 01 | 共同流程分支的測試長期放哪裡 | 已解決 | 02「共同流程的分支不在 OpenAI 的測試重寫一份」 |
| 01 | Gemini 沒有獨立的結束事件，用量可能漏掉 | 已解決 | Interactions API 有 `interaction.completed`，用量在裡面（03 Context 實測）；不必修改 `LKAIServerSentEventMapping` |
| 01 | `LKAITestWaiting.waitUntil(_:)` 之後要對同一個條件斷言；Anthropic 非串流取消測試少了這個斷言 | 留給之後 | 02 沒有寫取消測試；之後寫取消測試的 change，等待之後一律對同一個條件斷言，順手補上 Anthropic 那一處 |
| 01 | SSE 分框的測試 helper | 已解決 | 02「SSE 分框的測試 helper 搬進 LKAITestSupport」 |
| 01 | 金鑰遮蔽的三個遵循要每家各寫一次 | 已解決，04 已加強 | 02「金鑰遮蔽由每家 client 各自實作三個遵循」；`04-add-gemini-provider`「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」加上包裝型別 |
| 01 | Ollama 原生串流若為 NDJSON，要重用 `makeStream(for:)` 的步驟、只換分框方式 | 留給之後 | Ollama 的 change 查證並處理 |
| 02 | 輸入超過 context window 的 400 是否設專屬錯誤種類 | 已解決：不設 | 同第一份的同一項（`04-add-gemini-provider`「輸入超過 context window 不特別處理」） |
| 02 | `max_output_tokens` 的最小值要不要加進共用的請求檢查 | 已解決：不加 | Gemini 只要求大於 0，和共用檢查相同（03 Context 實測）；只有 OpenAI 有最小值 16，由 API 檢查 |
| 02 | `OpenAI-Organization`、`OpenAI-Project` 標頭 | 留給之後 | 等使用端需要多個組織或專案時再加 |
| 02 | chat-client「Context window limit」要不要加上「供應商有回報時」的條件 | 已解決 | 03 修改 chat-client 的「Context window limit」 |
| 02 | 金鑰遮蔽改用 `LKAICore` 的 `package` 包裝型別 | 已解決 | `04-add-gemini-provider`「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」 |
| 02 | `makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 各寫一份 | 已解決：不收 | 02 設的條件「要統一加標頭或改編碼設定時再收」沒有成立：Gemini 兩者都不需要，所以 `makeURLRequest(for:)` 與 `encodeBody(for:)` 不收進 `LKAICore`，現在三家各一份（`04-add-gemini-provider` Non-Goals）。實作審查另外指出（fable）：三家的 `StreamState.decode(_:)` 完全相同，`encodeBody(for:)` 只差請求內容的型別。重新評估的時機：要統一加標頭或改編碼設定時，以及下一家供應商的第一組任務；候選方案是在 `LKAISnakeCaseJSON` 加上以 `.convertToSnakeCase` 編碼的入口，請求內容的 raw value 可以一起拿掉，這也是 02 設的條件「改編碼設定」。三家的請求內容沒有以資料當鍵的 dictionary；Anthropic 的 `Fallbacks.encode(to:)` 會編碼鍵固定為 `model` 的 dictionary（第二輪實作審查時 fable 更正第一輪的說法，主對話讀碼確認），評估 `.convertToSnakeCase` 時，以 anthropic-provider 的 fallbacks 測試確認這個鍵沒有被改 |
| 02 | 與供應商無關的測試 helper 兩家各一份，Gemini 會是第三份 | 已解決 | `04-add-gemini-provider`「與供應商無關的測試 helper 收進 LKAITestSupport」：`LKAITestJSON` 與 `LKAIErrorTestSupport` |
| 02 | 503 的 `Retry-After` 沒有欄位可放 | 已解決 | 03「服務不可用的錯誤帶上等待時間，不給預設值」 |
| 02 | `LKAIError.refused(detail:)` 的說明沒有提到 detail 可能是模型寫的文字 | 已解決 | 03「refused 的 detail 說明補上隱私提醒」 |
| 02 | 串流 `error` 事件的欄位都是 Optional，沒有 `code` 也沒有 `message` 時當成可重試的 500 | 留給之後 | 使用者決定有實例時再改 spec；03 已在 openai-provider spec 寫明怎樣算可解碼 |
| 02 | 不認得的串流錯誤兩家結果不同，要不要訂共同規則 | 已解決 | 03「不認得的串流錯誤以 unrecognizedStreamError 統一回報」 |
| 02 | `config.yaml` 的新增供應商指標每多一家就多一層 | 已解決 | 03 建立本清單 |
| 04 | 輸入超過 context window 時，`v1` 回的狀態碼與代碼 | 留給之後 | 有實例，或有不受免費方案每分鐘 token 上限限制的金鑰時實測，再決定要不要在 Gemini 的錯誤對應中處理；現在 500 會成為可重試的 `.serviceUnavailable`，App 依 `isRetryable` 自動重試時會白白重送 |
| 04 | 串流中途的 `error` 事件與 `failed` 的 `errors`（或 `error`），實際格式是否和文件相同 | 留給之後 | 遇到實例時核對 |
| 04 | 「401、402、403、429 以外的 4xx 帶訊息」的規則在 `LKOpenAIErrorBody` 與 Gemini 的 `LKGeminiErrorBody` 各有一份 | 留給之後 | 它其實是「預設分類對哪些狀態碼有更精確的結果」：預設的 4xx 分類要改（例如讓 408 可重試），或第三家也寫這條時，收成 `LKAICore` 的一個 `package` 函式，並同時修改兩家的 spec |
| 04 | `LKOpenAIStreamEvent` 的 `Response` 不論事件種類，都會解碼 `error` 與 `incomplete_details` | 留給之後 | `response.completed` 帶形狀不同的 `error` 時，已完成的回答會以 `.invalidResponse` 結束，和 Gemini 以條件式解碼避開的情況同類；OpenAI 的文件寫明成功時 `error` 是 null，證據比 Gemini 強，所以不在 `04-add-gemini-provider` 的範圍；出現實例時，比照 Gemini 改成只在用得到時才解碼（第 3 章） |
| 04 | 多輪對話沒有把思考步驟送回（fable 指出） | 留給之後 | 文件寫思考步驟「MUST」照原樣送回，實測只送文字也成功，而 `LKAIMessage` 只有角色與文字，帶不了思考簽章。多輪對話出現 400，或開始支援工具呼叫時再處理；那時要擴充 `LKAIMessage`，屬於修改 chat-client spec 的 change |
| 04 | 三家測試的 `makeClient(events:)` 只差 client 型別（fable 指出） | 留給之後 | 可在 `LKAITestSupport` 加一個「推送事件後結束」的替身工廠，由下一家供應商的 change 處理 |
| 04 | 供應商在 4xx 的 `message`，或不認得的串流代碼的 `message` 中回顯金鑰時，`.invalidRequest` 與 `.invalidResponse` 的描述會含金鑰（`/spectra-verify` 與 `/spectra-review` 指出） | 留給之後 | spec「API key secrecy」的「any error it reports」嚴格來說涵蓋這種情況。實測的金鑰錯誤都是 401 或 Google 通用格式，不保留 `message`；OpenAI 是同樣的寫法。`lkai` 先在 CLI 這一側處理：印出 `Details:` 行時，把使用中的金鑰換成 `[REDACTED]`（`add-cli-chat-command`「錯誤印通用說明加上 Details 行，細節中的金鑰換成 [REDACTED]」）；library 的處理仍留給之後。要處理時，一起修改三家的 spec 寫法或錯誤描述 |
| 04 | `failed` 時仍解碼 `usage` 與 `model`（`/spectra-review` 指出） | 留給之後 | 見 `04-add-gemini-provider`「解碼端的判斷結果帶在事件裡，mapper 不再比對字串」。之後動到 `Interaction` 的解碼時，評估改成只在用得到時才解碼，並在 spec 寫明 `failed` 帶著格式不符的 `usage` 時的結果 |
| add-cli-chat-command | `lkai` 要和 `LKAIKit_LKAICore.bundle`、`LKAIKit_LKAIKitCLI.bundle` 放在同一個資料夾 | 已解決 | 少帶 `LKAIKit_LKAIKitCLI.bundle` 時，每次執行都中止，包括 `-v`（8.2 實測退出碼 133）。少帶 `LKAIKit_LKAICore.bundle` 時，`-v`、`-h` 與輸入錯誤都正常，只在服務回報錯誤時中止：2026-11-23 實測退出碼 133，`Error:` 印不出來。`01-add-ci`「lkai 留在 release 建置資料夾執行，不複製」：setup action 不複製 `lkai`，直接從 `swift build -c release --show-bin-path` 的資料夾執行，兩個 bundle 就在旁邊。驗收方式：從 action 加入的 `PATH`，在 package 以外的資料夾執行 `-v` 與一個服務錯誤（金鑰被拒絕）的情境，兩者都正常（lkai-setup-action「Report a service failure when run from PATH」，`01-add-ci` 任務 2.1）。之後要複製 `lkai`（例如附在 release 上）時，仍要連同兩個 bundle 一起複製，並以「把 `lkai` 複製到空資料夾後，`-v` 與一個服務錯誤的情境都正常」驗收 |
| add-cli-chat-command | `"Stream ended before a finish event"` 寫在 `LKAIChatClientProtocol`、`LKAIServerSentEventChatStreaming` 與 `LKAIChatRunner` 三處 | 留給之後 | 下次動到這句時，在 `LKAICore` 加一個 `package` 的工廠讓三處共用，做法比照 `LKAIError.unrecognizedStreamError(code:message:)`（實作審查 fable 指出） |
| add-cli-chat-command | 有思考的模型在思考期間會不會送資料，沒有查證 | 留給之後 | `--timeout` 是「多久沒有收到任何資料就放棄」的閒置逾時；遇到思考期間逾時的實例時，記錄在這份文件 |
| add-cli-chat-command | 替身 client 在 `LKAICoreTests` 與 CLI 測試各有一份 | 留給之後 | 出現第三份時，收進 `LKAITestSupport` |
| add-cli-chat-command | 中文說明在一般寬度的終端機上超出畫面 | 留給之後 | swift-argument-parser 以字元數計算寬度、只在半形空格處折行，而中文字佔兩欄。2026-11-23 以 `COLUMNS=80` 實測，37 行中有 11 行超過 80 欄，最寬 120 欄。CI 只看退出碼與 stdout，不受影響（`/spectra-review` 指出） |
