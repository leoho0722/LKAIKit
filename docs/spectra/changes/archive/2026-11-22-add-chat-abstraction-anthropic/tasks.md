派工方式：依 design 決策「平行實作時兩位實作者各用一個 git worktree」，主對話先完成 5.2，再於 repo 根目錄的 `.worktrees/<名稱>/` 建立 worktree。平行進行的任務各在自己的 worktree 修改；主對話在各 worktree 執行建置與測試，驗證完成後合併回這個 change 的工作分支，下一個任務從合併後的狀態開始。

## 1. 錯誤與請求型別（LKAICore）

- [x] 1.1 [after: 5.2] 交付 chat-client 的「Error classification and retryability」「Default HTTP status classification」與「Localized error descriptions」。
  - 依「錯誤以 LKAIError 統一分類並標示可否重試」，以 ios-dev-kit `domain/Error.swift` 樣板建立 `Sources/LKAICore/Chat/LKAIError.swift`：宣告 design 列出的十個 case（`transport(underlying: URLError)`）與公開的 `isRetryable`，遵循 `Equatable`，並依「公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值」標上 `@nonexhaustive`。
  - 依「錯誤說明以 String Catalog 提供英文與正體中文」，保留樣板的 `LocalizedError` extension：`errorDescription` 以不含 `default` 的窮舉 `switch` 決定 key，以 `String(localized:bundle: .module)` 讀取 `error.lkai.<case>`；在 `Sources/LKAICore/Resources/Localizable.xcstrings` 提供 `en` 與 `zh-Hant` 字串；`Package.swift` 宣告 `defaultLocalization: "en"`，`LKAICore` 加上 `resources: [.process("Resources")]`。
  - 依「HTTP 狀態碼的預設分類放在 LKAICore，供應商依自己的錯誤格式覆寫」，提供 `package` 層級的預設分類，依狀態碼與 `retry-after` 標頭產生錯誤；`retry-after` 只有完全由 ASCII 數字組成時才當成秒數，不直接用 `Int(_:)` 判斷。

  先以 `tests/Tests.swift` 樣板建立 `Tests/LKAICoreTests/LKAIErrorTests.swift`，確認測試在實作前因缺少型別而無法通過，再實作。測試內容：
  - 把 spec 的「retryability by error kind」與「status codes」兩張範例表逐列寫成參數化測試，包含 `retry-after` 為 `-1` 與 HTTP 日期的兩列；
  - 「Localized error descriptions」的三個 scenario：手動列出每個 case 的一個值，在 `en` 與 `zh-Hant` 的語言資料夾都查得到非空、且不是 key 本身的字串；`LKAICore` 資源的開發語言為 `en`；供應商訊息與拒答原因不出現在說明中。

  驗證：`swift test --filter LKAICoreTests` 通過，且這次編譯沒有警告；建置後 `Bundle.module` 內有 `en` 與 `zh-Hant` 的語言資料夾。
- [x] 1.2 [after: 1.1] 交付 chat-client 的「Chat request content」的資料形狀與驗證規則：依「共用型別依三家 API 的實際格式設計」，以 `domain/Enum.swift` 樣板建立 `LKAIMessageRole`（`user`、`assistant`，不設 raw type），以 `domain/Model.swift` 樣板建立 `LKAIMessage` 與 `LKAIChatRequest`（依該檔規則拿掉 `Identifiable`、`Codable`），並提供 `package` 層級的驗證方法：模型為空字串、訊息為空、`maxOutputTokens` 小於 1 時丟出 `.invalidRequest`，訊息指出違反哪一條規則。先建立 `Tests/LKAICoreTests/LKAIChatRequestTests.swift`，以 spec 的「invalid requests」範例表逐列驗證會被拒絕，並驗證合法請求通過，確認測試在實作前無法通過，再實作。驗證：`swift test --filter LKAICoreTests` 通過且無警告。

## 2. 串流型別與共用對話介面（LKAICore）

- [x] 2.1 [after: 1.1] 交付 chat-client 的「Stream construction for test doubles」與「Token usage」的資料形狀。依「以自訂 AsyncSequence 提供 typed throws 的串流」（做法已在規劃階段實測可行，見 design Context）、「token 用量以統一口徑放進共用型別」「實際回應的模型放進共用結果」「公開 enum 標為 @nonexhaustive，公開 struct 新增欄位時 init 參數給預設值」與「型別依 ios-dev-kit 樣板建立」，建立以下型別：
  - `LKAIFinishReason`：依「生成途中塞滿 context window 以獨立的結束原因回報」，有 `completed`、`maxOutputTokens`、`contextWindowExceeded` 三個 case，標 `@nonexhaustive`；`contextWindowExceeded` 的 `///` 依 Implementation Contract 說明。
  - `LKAIUsage`
  - `LKAIChatStreamEvent`：依 `domain/EnumWithAssociatedValue.swift` 樣板刪掉整組 `Codable`，標 `@nonexhaustive`；結束事件為 `.finished(LKAIChatCompletion)`。
  - `LKAIChatCompletion`：帶 `finishReason`、`usage`、`respondingModel`。
  - `LKAIChatResponse`：只帶 `text` 與 `completion: LKAIChatCompletion`。
  - `LKAIChatStream`：手寫，提供公開的 `init(_ source:)`。迭代的 task 已被取消時，不論來源丟出什麼錯誤都正常結束；來源丟出 `CancellationError` 或 `.cancelled` 時正常結束；其他 `LKAIError` 原樣交出；其他錯誤轉成 `.invalidResponse`。`///` 寫明只支援單一消費者，以及釋放串流才會取消請求。

  先建立 `Tests/LKAICoreTests/LKAIChatStreamTests.swift`，把 spec 的「source behaviors」範例表逐列寫成測試，再實作。「先取消迭代的 task、來源才丟出錯誤」那一列以測試控制順序：取消後才讓來源丟出錯誤。驗證：`swift test --filter LKAICoreTests` 通過且無警告。
- [x] 2.2 [after: 1.2, 2.1] 交付 chat-client 的「Non-streaming call」，以及「Output token limit」「Context window limit」「Refusal」「Cancellation」「Invalid responses」中屬於非串流彙整的行為：依「共用對話介面以 LKAIChatClientProtocol 定義，供應商各自實作」，以 `data/Service.swift` 樣板的 Protocol 區建立 `Sources/LKAICore/Chat/LKAIChatClientProtocol.swift`；依「同時提供串流與非串流呼叫，非串流預設由串流彙整」，以 `public` 的 protocol extension 提供 `invoke(_:)` 的預設實作。預設實作的行為：
  - 串接文字片段，遇到結束事件時回傳 `LKAIChatResponse(text:completion:)`，`completion` 原樣帶入結束事件的資料；
  - 串流丟出的錯誤原樣丟出，但等待呼叫的 task 已被取消時一律丟出 `.cancelled`；
  - 串流沒有結束事件就結束時，若 task 已取消則丟出 `.cancelled`，否則丟出 `.invalidResponse`。

  `stream(_:)` 的 `///` 寫明請求在呼叫時送出、釋放串流才會取消請求。先建立 `Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift`，在測試檔內以 `LKAIChatStream(_:)` 寫一個只實作串流的測試替身，逐一驗證 spec 對應 scenario 的值，再實作：
  - 「Hel」「lo」正常完成時得到 "Hello"；
  - 達到輸出上限時得到 "Partial" 與 `.maxOutputTokens`；
  - 生成途中塞滿 context window 時得到 "Partial" 與 `.contextWindowExceeded`；
  - 拒答時丟出 `.refused(detail: "cyber")`，不回傳結果；
  - 沒有結束事件時丟出 `.invalidResponse`；
  - 取消時丟出 `.cancelled`，取消後替身才丟出頻率限制錯誤時也丟出 `.cancelled`；
  - 供應商沒回報用量時 `usage` 為 `nil`；
  - 依 chat-client 的「Responding model」，供應商回報的回應模型原樣帶進結果，沒有回報時為 `nil`。

  驗證：`swift test --filter LKAICoreTests` 通過且無警告。

## 3. 共用 HTTP 與 SSE 基礎（LKAICore 與 LKAITestSupport）

- [x] 3.1 [after: 5.2] 交付位元組切行與 SSE 解析：依「共用 HTTP client 與 SSE 解析放在 LKAICore，以 package 存取層級提供」，建立手寫的 `package` 型別 `LKAIHTTPLineSplitter`、`LKAIServerSentEventParser`，以及 `package` 層級的 `LKAIServerSentEvent`（`domain/Model.swift` 樣板）。
  - 切行規則：CRLF、LF、單獨的 CR 換行，CR 後緊接 LF 算一次；保留空行；U+2028、U+2029、U+0085 不算換行；只比對 `0x0A` 與 `0x0D`，每行以 UTF-8 解碼；提供逐位元組輸入與收尾方法。不使用 `URLSession.AsyncBytes.lines`（理由見 design Context 的實測）。
  - SSE 規則（依 WHATWG）：
    - 以 `:` 開頭的行略過；
    - 其他行以第一個 `:` 分成欄位名與值，值開頭的一個空白移除；沒有 `:` 的行整行是欄位名、值為空；
    - `event` 設定事件名稱，多個 `data` 以 `\n` 串接，`id`、`retry` 與其他欄位略過；
    - 空行時資料為空就不送出、只清除事件名稱，否則送出事件並清除；
    - 收尾時丟棄尚未以空行收尾的事件。

  先建立 `Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift` 與 `Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift`，再實作。測試內容：
  - 切行：位元組 `a\r\n\r\nb\n` 切成 `["a", "", "b"]`；`a\n\nb` 切成 `["a", "", "b"]`；`a\rb` 切成 `["a", "b"]`；`x` 加上 U+2028 加上 `y\n` 切成只有一行，內容仍包含 U+2028；CR 與 LF 分在兩次輸入時仍只算一次換行。
  - SSE：以參數化測試涵蓋上述每條規則各至少一個案例。

  驗證：`swift test --filter LKAICoreTests` 通過且無警告。
- [x] 3.2 [after: 1.1, 3.1] 交付共用 HTTP client：依「共用 HTTP client 與 SSE 解析放在 LKAICore，以 package 存取層級提供」，以 `data/Service.swift` 樣板建立 `Sources/LKAICore/Networking/LKAIHTTPClient.swift`，內含 `package` 的 `LKAIHTTPClientProtocol` 與以注入的 `URLSession` 實作的 `LKAIHTTPClient`，並依 Implementation Contract 建立 `LKAIHTTPResponse`（含 `readErrorBody()`）與 `LKAIHTTPLines`（含 `package init(_:)`）。行為：
  - 標頭的 key 轉小寫；
  - 以 3.1 的 `LKAIHTTPLineSplitter` 切行；
  - `readErrorBody()` 最多讀 64 KiB，超過時截斷而不失敗，並停止讀取；
  - task 已被取消時的 `URLError(.cancelled)` 轉成 `.cancelled`，其他 `URLError` 轉成 `.transport(underlying:)`；
  - 逐行內容被釋放或迭代的 task 被取消時，取消底層傳輸。

  先建立 `Tests/LKAICoreTests/LKAIHTTPClientTests.swift`，依 design 決策「測試 target 依受測 target 增加 LKAIAnthropicTests」的 `LKAICoreTests` 做法攔截請求，逐一驗證再實作：
  - 在測試檔內自訂 `URLProtocol`，每個測試以 `URLProtocol.setProperty(_:forKey:in:)` 把假回應掛在請求上；不使用 `static` 可變狀態；
  - 假回應一律帶 `Content-Type: text/event-stream`。

  測試內容：
  - 回應內容以 `LKAIHTTPLines` 逐行交出，空行保留；
  - 標頭 key 為小寫；
  - 超過 64 KiB 的錯誤內容被截斷而不失敗；
  - 連線失敗得到 `.transport`；
  - 假回應不結束時取消迭代的 task，得到 `.cancelled` 而不是 `.transport`；
  - `LKAIHTTPLines(_:)` 的錯誤轉換：來源丟出 `CancellationError` 時正常結束，丟出非 `LKAIError` 的錯誤時得到 `.invalidResponse`。

  驗證：`swift test --filter LKAICoreTests` 通過且無警告。
- [x] 3.3 [after: 3.2] 交付 package-distribution 的「Test support stays out of the library build」所需的 target 與測試替身：依「測試替身放在不屬於任何 product 的 LKAITestSupport target」，在 `Package.swift` 新增只依賴 `LKAICore` 的 `.target(name: "LKAITestSupport")`，不列進任何 product，`LKAIKit` 也不依賴它。並以 `tests/MockService.swift` 樣板建立 `Sources/LKAITestSupport/LKAIMockHTTPClient.swift`，用 `Mutex` 取代 `@unchecked Sendable`，提供以下能力：
  - 記錄收到的 `URLRequest`；
  - 回傳預先設定的狀態碼與標頭，逐行內容以 `LKAIHTTPLines(_:)` 建立；
  - 讓測試逐行推送內容並決定何時結束；
  - 讓 `fetch` 直接丟出指定的 `LKAIError`，或在逐行內容途中丟出指定的錯誤；
  - 公開是否偵測到底層請求被取消，也就是逐行內容的來源因迭代的 task 被取消或被釋放而終止。

  這個替身沒有自己的測試 target，由 4.1 到 4.4 實際使用來驗證，manifest 的依賴在 5.3 檢查。驗證：`swift build` 成功且無警告，並逐項對照 design 的 Implementation Contract 做內容審查。

## 4. Anthropic 供應商（LKAIAnthropic）

測試檔說明：4.1 到 4.4 的測試依 design Implementation Contract 拆在 `LKAnthropicClientTests`、`LKAnthropicClientStreamTests`、`LKAnthropicClientErrorTests`、`LKAnthropicClientCancellationTests`、`LKAnthropicClientLiveTests` 五個檔；各任務文字裡的「`LKAnthropicClientTests`」指這組測試。

- [x] 4.1 [after: 2.2, 3.3] 交付 anthropic-provider 的「Messages API request」「Refusal fallback」與「API key secrecy」，以及 chat-client 的「Chat request content」在實際供應商的行為。依「測試 target 依受測 target 增加 LKAIAnthropicTests」，在 `Package.swift` 新增 `.target(name: "LKAIAnthropic", dependencies: ["LKAICore"])` 與依賴 `LKAIAnthropic`、`LKAICore`、`LKAITestSupport` 的 `LKAIAnthropicTests`。依「LKAnthropicClient 以 API 金鑰與 URLSession 建立，金鑰不出現在診斷輸出」，以 `data/Service.swift` 樣板的 Implementation 區建立 `LKAnthropicClient`，具備：
  - 公開的 `init(apiKey:urlSession:refusalFallback:)` 與 `package` 的 `init(apiKey:httpClient:refusalFallback:)`，`refusalFallback` 預設 `.disabled`；
  - 依「Anthropic 的拒答備援由 App 在建立 client 時選擇開啟」，以 `domain/EnumWithAssociatedValue.swift` 樣板建立 `LKAnthropicRefusalFallback`，`///` 依該決策寫明用量範圍、Claude Haiku 5.5 的限制與備援模型不可與請求的模型相同。開啟時帶 `anthropic-beta` 標頭與 `fallbacks`，關閉時兩者都不送；指定模型的清單違反規則時，不送請求、直接丟出 `.invalidRequest`；
  - 送出 POST 請求到 `https://api.anthropic.com/v1/messages`，帶 `x-api-key`、`anthropic-version: 2026-10-21`、`content-type` 標頭，以及 `model`、`max_tokens`、`messages`、`stream: true` 與選填的 `system`；
  - `stream(_:)` 依「以自訂 AsyncSequence 提供 typed throws 的串流」的「生產端 task 的擁有權」建立一個 task，不存進屬性，由 `onTermination` 取消；
  - 以 `CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable` 遮住金鑰。

  先建立 `Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift`，用 `LKAIMockHTTPClient` 驗證以下行為，再實作：
  - spec 的兩個請求 scenario，請求內容以 JSON 值比對，且沒有 `anthropic-beta` 標頭；
  - 「fallback settings」與「invalid fallback model lists」兩張範例表的每一列；
  - 金鑰不出現在 `String(describing:)`、`String(reflecting:)`、`dump(_:)` 與 HTTP 401 錯誤的描述中；
  - 「invalid requests」範例表的每一列，在串流與非串流呼叫都丟出 `.invalidRequest`，且替身沒有收到任何請求。

  驗證：`swift test --filter LKAIAnthropicTests` 通過且無警告。
- [x] 4.2 [after: 3.1, 4.1] 交付 anthropic-provider 的「Stream text mapping」「Stop reason mapping」「Usage mapping」「Responding model and fallback blocks」，以及 chat-client 的「Responding model」與「Streaming call」「Output token limit」「Context window limit」「Refusal」「Token usage」「Invalid responses」在 Anthropic 的行為。依「Anthropic 串流事件的對應規則」實作事件對應（事件格式已在規劃階段對官方文件查證，見 design Context），包含：
  - `message_start` 沒有 `usage` 時不視為錯誤；
  - `stop_reason` 取最後一個不是 null 的值；
  - 用量欄位為 null 時保留先前的值；
  - 沒有收到 `input_tokens` 或 `output_tokens` 時不帶用量。

  在 `LKAnthropicClientTests` 以 SSE 固定內容驗證以下 spec 範例，再實作：
  - 「stream with thinking and ping」
  - 「stop reasons」範例表的每一列，包含 `category` 為 null 的拒答
  - 「cached prompt」「thinking tokens」「usage only in the delta event」「input tokens never reported」四個用量範例
  - 「Hel」「lo」正常完成
  - 達到輸出上限
  - 拒答時先收到「Sure」再收到 `.refused(detail: "cyber")`
  - 沒有用量時 `usage` 為 `nil`
  - 「stream without a fallback block」與「fallback in the middle of a stream」兩個範例
  - 串流沒有 `message_stop` 就結束時丟出 `.invalidResponse`

  驗證：`swift test --filter LKAIAnthropicTests` 通過且無警告。
- [x] 4.3 [after: 4.2] 交付 anthropic-provider 的「Error mapping」：依「HTTP 狀態碼的預設分類放在 LKAICore，供應商依自己的錯誤格式覆寫」與「使用者自設的花費上限以錯誤訊息的開頭辨識」，先解析 Anthropic 錯誤內容的 `error.type`，解析不了或類型未知時，改用 1.1 的預設分類；`invalid_request_error` 的 `error.message` 以 "You have reached your specified" 開頭時對應 `.quotaExceeded`。HTTP 錯誤內容以 `LKAIHTTPResponse.readErrorBody()` 讀取。串流中的 `error` 事件依「Anthropic 串流事件的對應規則」對應：已知類型用固定狀態碼，未知類型為 `.serviceUnavailable(statusCode: 500)`，無法解碼為 `.invalidResponse`。先在 `LKAnthropicClientTests` 加入以下測試，再實作：
  - 「error responses」範例表的每一列；
  - 「error events」範例表的每一列；
  - 連線失敗時得到 `.transport`（以替身的 `fetch` 丟出 `.transport(underlying:)`）。

  驗證：`swift test --filter LKAIAnthropicTests` 通過且無警告。
- [x] 4.4 [after: 4.3] 交付 chat-client 的「Cancellation」在 Anthropic 的行為，以及實際 API 的測試。先在 `LKAnthropicClientTests` 加入以下測試，再實作：
  - 串流送出一段文字後取消迭代的 task，迭代沒有錯誤就結束，且 `LKAIMockHTTPClient` 偵測到底層請求被取消；
  - 「Release a stream after leaving the loop」：在一個區塊內迭代到第一段文字後離開迴圈，區塊結束、串流被釋放後，`LKAIMockHTTPClient` 偵測到底層請求被取消；
  - 等待中的非串流呼叫被取消時丟出 `.cancelled`。

  另外加入只在環境變數 `LKAI_ANTHROPIC_API_KEY` 有設定時才執行的實際 API 測試（Swift Testing 的 `.enabled(if:)`），以模型 `claude-opus-5-5`、要求只回一個詞的提示詞、`maxOutputTokens` 4096，分別跑一次串流與一次非串流，驗證都以 `.completed` 結束且文字不為空。這個測試的實際執行屬於 owner，見 5.4。驗證：`swift test --filter LKAIAnthropicTests` 通過且無警告，沒有設定環境變數時實際 API 測試顯示為略過。

## 5. 總成、命名規則與整體驗收

- [x] 5.1 [after: 4.1] 交付 anthropic-provider 的「Availability through LKAIKit」：`LKAIKit` 改為依賴 `["LKAICore", "LKAIAnthropic"]`，`Sources/LKAIKit/Exports.swift` 新增 `@_exported import LKAIAnthropic`。先在 `Tests/LKAIKitTests/ExportsTests.swift` 新增一個只透過 `import LKAIKit` 建立 `LKAnthropicClient`，並存成 `any LKAIChatClientProtocol` 的測試，確認在重新匯出前因找不到 `LKAnthropicClient` 而編譯失敗，再加入重新匯出。測試檔維持不 import `LKAICore` 或任何供應商模組的規則。驗證：`swift test --filter LKAIKitTests` 通過且無警告。
- [x] 5.2 專案規則與 worktree 位置，由主對話在派出第一批任務前完成：
  - 依「外部型別遵循本 package 的 public protocol 只能寫在 LKAICore」，在 `docs/spectra/config.yaml` 的命名規則新增一條：「非本 package 的型別遵循本 package 的 `public` protocol，只能寫在 LKAICore。」並在既有「非供應商 target」的清單補上 `LKAITestSupport`。
  - 依「平行實作時兩位實作者各用一個 git worktree」，在 `.gitignore` 新增一行 `.worktrees/`，其餘內容不動。

  驗證：
  - 內容審查 `docs/spectra/config.yaml` 的新條文與 design 該決策一致；`spectra instructions proposal --change "add-chat-abstraction-anthropic" --json` 回傳的 `context` 含有這條規則與 `LKAITestSupport`。
  - `git check-ignore .worktrees/probe` 輸出 `.worktrees/probe`；`git diff .gitignore` 只有新增的這一行。
- [x] 5.3 [after: 4.4, 5.1, 5.2] 整體驗收：
  - `swift package dump-package` 確認：
    - 「Test support stays out of the library build」與既有的「Module dependency direction」都成立：`LKAIAnthropic` 與 `LKAITestSupport` 都只依賴 `LKAICore`，`LKAIKit` 依賴 `LKAICore` 與 `LKAIAnthropic`。
    - 從 `LKAIKit` 可達的 target 不含 `LKAITestSupport` 與外部套件，products 只有 `LKAIKit` 與 `lkai`。
    - 依「跨供應商組裝邏輯暫不提供」，沒有新增組裝用的 target。
  - `swift package clean` 後 `swift build` 與完整 `swift test` 通過，LKAIKit 自身的 target 沒有編譯警告。
  - 以 XcodeBuildMCP 對 iOS 26 模擬器建置 `LKAIKit` scheme 成功。
  - 內容審查：`LKAIError`、`LKAIFinishReason`、`LKAIChatStreamEvent` 的宣告帶 `@nonexhaustive`；`LKAIChatClientProtocol` 的預設實作在 `public` extension。

  驗證：以上指令與審查的結果都符合描述。
  - spectra-exclude: package-distribution / Inspect the manifest for the test support target | target 依賴圖與 products 只能由 `swift package dump-package` 觀察，專案的單元測試環境讀不到 manifest；由本任務的 dump-package 檢查驗證（2026-11-21 執行：`LKAITestSupport` 只依賴 `LKAICore`、不在任何 product、從 `LKAIKit` 不可達），沒有自動化測試持續把關
- [x] 5.4 [after: 4.4] Owner 以自己的 Anthropic API 金鑰執行實際 API 的測試（會產生少量費用）：`LKAI_ANTHROPIC_API_KEY=<金鑰> swift test --filter LKAIAnthropicTests`。驗證：實際 API 的串流與非串流測試都有執行、沒有被略過，而且都通過。
  - 執行紀錄（2026-11-22，owner 在主目錄執行）：`LKAI_ANTHROPIC_API_KEY="$(security find-generic-password -s lkai-anthropic-api-key -w)" swift test --filter LKAIAnthropicTests`，42 個測試全部通過；`stream_要求只回一個詞_以完成結束且文字不為空` 與 `invoke_要求只回一個詞_結果以完成結束且文字不為空` 都有執行（沒有略過），分別約 0.93 與 0.94 秒通過。

## 6. 實作審查後的修正

依實作審查（`/spectra-verify`、`/spectra-review`、fable 與 opus 兩位審查者）查證成立的項目與使用者的決定；派工方式同上（各自的 worktree，主對話建置、測試與合併）。

- [x] 6.1 交付 chat-client「Cancellation」在真實傳輸上的驗證，並讓測試替身偵測得到「被釋放」：
  - `LKAIHTTPClientTests` 新增兩個測試，測試自己持有 `URLSession`，假回應送出一行後不結束：①取消迭代的 task；②迭代到第一行後離開迴圈、只釋放逐行內容、不取消任何 task。兩者都以有上限的輪詢確認 `session.allTasks` 清空（做法見 design Context 的實測）。
  - `LKAIMockHTTPClient`：依 design「測試替身放在不屬於任何 product 的 LKAITestSupport target」，逐行內容的來源只在 `fetch` 時交出一次、之後不再持有；`fetch` 之前推送的行在 `fetch` 後照常交出；`///` 與實作一致。
  - `LKAnthropicClientCancellationTests` 新增：收到 `message_stop`、交出結束事件後，client 放開回應，替身偵測到底層請求被取消。

  驗證：`swift test` 通過且無警告；主對話反向檢查：拿掉 `LKAIHTTPClient` 的 `onTermination` 取消時，①②兩個測試都失敗。
- [x] 6.2 交付 chat-client「Cancellation」對非串流的嚴格要求：依 design「同時提供串流與非串流呼叫，非串流預設由串流彙整」的取消規則，`invoke(_:)` 的預設實作在收到結束事件、回傳結果前再檢查 task 是否已取消，已取消就丟出 `.cancelled`。先在 `LKAIChatClientProtocolTests` 加測試：替身的來源預先放入 "Hel" 與結束事件，在已取消的 task 內呼叫 `invoke`（例如 task 先等一個訊號，測試取消後再放行），丟出 `.cancelled` 而不是回傳結果；確認測試在修改前失敗，再修改。同檔另外兩項：既有的「Cancel a non-streaming call」測試改成等替身的串流開始被迭代後才取消；各測試重複的 5 行請求改成型別內的 instance `private let`。驗證：`swift test --filter LKAICoreTests` 通過且無警告。
- [x] 6.3 程式碼與說明的小修正（行為不變）：
  - `LKAIHTTPResponse.readErrorBody()` 的 `- Note:` 改成上限只限制回傳字串的大小、擋不住異常大型回應佔用的記憶體（見 design Risks）；
  - `LKAIFinishReason.contextWindowExceeded` 說明裡的「本 change」改成「目前」；
  - `LKAIError.streamFailure(for:)` 與 `localizationKey` 由 `package` 改成 `internal`（只在 LKAICore 與它的 `@testable` 測試使用）；`retryDelay(from:)` 維持 `package`（LKAIAnthropic 使用）；
  - `Localizable.xcstrings` 的 10 個條目加上 `"extractionState" : "manual"`（key 在執行期組出，Xcode 抽不到字面值）；
  - `LKAnthropicErrorBody` 的 `try?` 說明移到同一行；
  - `LKAIMessage`、`LKAIUsage`、`LKAIChatCompletion`、`LKAIChatResponse` 的型別 `///` 補上與 `LKAIChatRequest` 相同的 Note：之後新增欄位時 `public init` 的新參數一律給預設值。

  驗證：`swift test` 通過且無警告；建置後 bundle 的 `en.lproj`、`zh-Hant.lproj` 仍各有 10 個字串。
- [x] 6.4 [after: 6.1] `LKAIAnthropicTests` 的共用固定資料與 helper 合併：依 ios-dev-kit `file-templates.md`「測試固定資料依使用範圍宣告」「測試共用的 helper 依使用範圍放置」，把四個測試檔重複的 `validRequest`、`CallMode`、`StreamOutcome` 與 `collectOutcome`、`callError`、SSE 事件建構，合併到 `Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift`（沒有 case 的 enum、static 成員），各測試檔改用它；並在以 `NSDictionary` 比對請求內容的測試補上「`stream` 必須是 JSON 布林」的嚴格斷言。測試行為不變，只有布林斷言是新增。驗證：`swift test --filter LKAIAnthropicTests` 通過且無警告；主對話反向檢查：請求內容的 `stream` 改送 `1` 時，新斷言失敗。
- [x] 6.5 [after: 6.1, 6.2] `LKAICoreTests` 的檔案組織：依 ios-dev-kit `project-structure.md`「測試檔的位置與主 target 對應、一個測試檔測一個型別」，把 `Tests/LKAICoreTests/` 分成 `Chat/` 與 `Networking/` 兩個子資料夾鏡像 `Sources/LKAICore/`；把 `LKAIHTTPClientTests.swift` 裡測 `LKAIHTTPResponse` 與 `LKAIHTTPLines` 的測試拆到 `LKAIHTTPResponseTests.swift`、`LKAIHTTPLinesTests.swift`，共用的假 `URLProtocol` 與請求建立方法放進 `Networking/` 的測試支援檔。測試內容與 spectra-scenario 註解不變。驗證：`swift test --filter LKAICoreTests` 通過且無警告，測試數與拆分前相同。
- [x] 6.6 依 design Implementation Contract 的「API 演進規則」，在 `docs/spectra/config.yaml` 的 context 新增三條規則。驗證：內容審查；`spectra instructions proposal --change "add-chat-abstraction-anthropic" --json` 回傳的 `context` 含有這三條。
- [x] 6.7 [after: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6] 審查修正後的整體驗收：重做 5.3 的每一項（`swift package dump-package`、`swift package clean` 後 `swift build` 與完整 `swift test`、XcodeBuildMCP 對 iOS 26 模擬器建置、`@nonexhaustive` 與 `public` 預設實作的內容審查），並以 `spectra coverage` 確認每個 scenario 與 example 都有測試或記錄的例外。驗證：以上結果都符合描述。
- [x] 6.8 第二輪實作審查的程式與說明修正（haiku）：
  - `LKAnthropicStreamEvent` 的 `message_start` 解碼：`message.model` 改成選填；沒有出現時串流照常完成，`respondingModel` 為 nil（design「Anthropic 串流事件的對應規則」）。先在 `LKAnthropicClientStreamTests` 加測試：`message_start` 的 `message` 沒有 `model`、其他事件正常，串流以 `.completed` 結束且結束事件的 `respondingModel` 為 nil；確認修改前失敗（目前解碼失敗、得到 `.invalidResponse`），再修改。
  - `finishedEvent` 從 `LKAnthropicClientStreamTests` 移進 `LKAnthropicClientTestSupport`，`LKAnthropicClientCancellationTests` 手寫的結束事件改用它。
  - `LKAIHTTPResponse.readErrorBody()` 的 `- Note:` 拿掉「（見 design Risks）」，改寫成不依賴文件位置的說法。

  驗證：`swift test` 通過且無警告。
- [x] 6.9 第二輪實作審查的 LKAICoreTests 組織修正（sonnet）：依 ios-dev-kit `file-templates.md`「一個受測型別一份 TestSupport」「測試固定資料依使用範圍宣告」：
  - `LKAIHTTPClientTestSupport` 裡處理 `LKAIHTTPLines` 的 `LineSource`、`LinesOutcome`、`collectLines` 移到 `Networking/LKAIHTTPLinesTestSupport.swift`；
  - `LKAIHTTPResponseTests` 的 `readErrorBody` 測試改成直接以 `LKAIHTTPResponse(statusCode:headers:lines:)` 與 `LKAIHTTPLines(_:)` 建立回應，不經過 client 與假 `URLProtocol`（期望值不變）；
  - `LKAIHTTPClientTests` 與 `makeOpenRequest()` 內容相同的請求改用它。

  測試名稱、期望值與 spectra-scenario 註解不變。驗證：`swift test --filter LKAICoreTests` 通過且無警告，測試數不變（61）。

  實作時追加（主對話同意，第三輪審查後補記）：`readErrorBody` 的測試改成直接建立回應後，「`fetch` 不把非 2xx 轉成錯誤」失去測試覆蓋，所以在 `LKAIHTTPClientTests` 新增 `fetch_狀態碼不是2xx_回傳回應而不轉成錯誤`（反向檢查成立），測試數因此是 62；假 `URLProtocol` 改成請求有指定 `Content-Type` 時不覆寫；`LKAIHTTPClientTestSupport` 因此只剩一個使用者，依「只有一個測試型別用的 helper 寫成該型別的 private 成員」折回 `LKAIHTTPClientTests` 並刪除。
- [x] 6.10 [after: 6.8, 6.9] 第二輪修正的文件與驗收（主對話）：`docs/spectra/config.yaml` 的 API 演進規則加上 design 記錄的指標；重做 6.7 的每一項驗收。驗證：`spectra instructions` 回傳的 context 含有指標；6.7 的每一項結果都符合描述。
  - 執行紀錄（2026-11-22，主對話在主目錄，HEAD 0f7a1de 加上未提交的 config.yaml）：`swift package dump-package` 確認 LKAIAnthropic 與 LKAITestSupport 只依賴 LKAICore、LKAIKit 依賴 LKAICore 與 LKAIAnthropic、從 LKAIKit 可達的 target 不含 LKAITestSupport 與外部套件、products 只有 LKAIKit 與 lkai；`swift package clean` 後 `swift build` 與 `swift test` 零警告，Swift Testing 共 113 個測試通過（LKAICore 62、LKAIAnthropic 42、LKAIKitCLI 7、LKAIKit 2；2 個實際 API 測試因沒有設定金鑰而略過）；XcodeBuildMCP 對 iPhone 17（iOS 26.5）模擬器建置 LKAIKit scheme 成功、零警告；`spectra coverage` 52 個有測試、1 個例外、0 個缺口；`spectra instructions` 的 context 含有 config.yaml 的指標。
- [x] 6.11 第三輪實作審查的測試小修正（haiku）：
  - `LKAIHTTPClientTests` 的假 `URLProtocol` 判斷請求是否指定 `Content-Type` 時不分大小寫（目前只比對 `Content-Type` 這一種寫法）。
  - 「Provider reports no model」的 spectra-scenario 標記：這個 scenario 的 WHEN 是非串流呼叫，`LKAnthropicClientStreamTests` 的 `stream_messageStart沒有model_照常完成且回應模型為nil` 卻是迭代串流。拿掉這個串流測試上的標記（測試保留），另加一個以 `invoke` 呼叫、斷言結果不帶回應模型的測試並標上它。
  - `LKAIHTTPResponseTests`：刪掉只讀回 helper 寫入值的 `statusCode == 400` 斷言（狀態碼由 `LKAIHTTPClientTests` 的 `fetch_狀態碼不是2xx_回傳回應而不轉成錯誤` 負責），並修正「行內不留 CR 與 LF」等與現況不符的說明。

  驗證：`swift test` 通過且無警告；主對話反向檢查：`message_start` 的 `model` 改回必填時，新的 `invoke` 測試失敗。
- [x] 6.12 [after: 6.11] 第三輪修正後的最後驗收（主對話）：重做 6.10 的每一項驗收，並把執行結果記錄在本任務下方。驗證：每一項結果都符合描述。
  - 執行紀錄（2026-11-22，主對話在主目錄，HEAD 77fbffb 加上未提交的 config.yaml、design.md、tasks.md）：`swift package dump-package` 確認依賴方向與 products 不變、從 LKAIKit 可達的 target 不含 LKAITestSupport 與外部套件；`swift package clean` 後 `swift build` 與 `swift test` 零警告，Swift Testing 共 114 個測試通過（LKAICore 62、LKAIAnthropic 43、LKAIKitCLI 7、LKAIKit 2；2 個實際 API 測試因沒有設定金鑰而略過，它們已在 5.4 以真實金鑰通過）；XcodeBuildMCP 對 iPhone 17（iOS 26.5）模擬器建置 LKAIKit scheme 成功、零警告；`spectra coverage` 52 個有測試、1 個例外、0 個缺口。
