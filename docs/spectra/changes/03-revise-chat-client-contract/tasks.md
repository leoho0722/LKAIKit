派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1、2 組與 3.1 由 sonnet 在 `.worktrees/sonnet` 依序實作。
- 3.2 與第 4 組由主對話做；建置、測試、反向檢查與合併也都由主對話執行。

測試的做法依 design「測試在既有的參數化測試加列」：

- **新行為先寫測試**：先在範例表加列或改期望值，主對話觀察到這些列在實作前失敗，才實作。
- **行為不變的修改**：以既有測試把關，測試的名稱與期望值不變，測試數不變。
- **只改說明文字的任務**：沒有行為可以觀察，以內容審查與 `swift test` 全部通過把關。
- **期望值的寫法**：
  - `.serviceUnavailable` 一律明寫兩個 associated value，例如 `.serviceUnavailable(statusCode: 503, retryAfter: .seconds(5))`，以 `==` 比對。
  - 兩家的串流錯誤測試都要能表達「`.invalidResponse`，而且說明含指定的文字」：OpenAI 已有 `Expectation.invalidResponse(containing:)`，Anthropic 在 2.2 改成同樣的形狀。

## 1. 服務不可用的等待時間

- [ ] 1.1 依 design「服務不可用的錯誤帶上等待時間，不給預設值」，把 `LKAIError` 的 case 改成 `serviceUnavailable(statusCode: Int, retryAfter: Duration?)`，行為不變（sonnet）：
  - 35 處以 `.serviceUnavailable(statusCode:` 建立的寫法都補上 `retryAfter: nil`：`Sources/` 9 處、`Tests/` 26 處。`init(httpStatusCode:retryAfter:)` 的 5xx 這時也先傳 nil，1.2 才改。
  - case 的 `///` 寫明：供應商沒有提供或無法解讀時為 nil，串流中途的錯誤一律為 nil，取狀態碼的寫法是 `case .serviceUnavailable(let statusCode, let retryAfter)`。

  驗證：
  - 完整 `swift test` 通過且零警告；共 147 個測試，名稱不變，期望值只多了 `retryAfter: nil`。
  - `grep -rn '\.serviceUnavailable(statusCode:' Sources Tests` 的每一行都含 `retryAfter:`；`Sources/` 與 `Tests/` 內沒有 `case .serviceUnavailable(statusCode: let`。
- [ ] 1.2 [after: 1.1] 依 design「5xx 的預設分類與 Anthropic 的 HTTP 錯誤讀 retry-after」，交付 chat-client 的「Error classification and retryability」與「Default HTTP status classification」，以及 openai-provider「Error mapping」中 HTTP 503 帶等待時間的那一列（sonnet）：
  - **先加測試**：
    - `LKAIErrorTests` 的 `init_狀態碼與retryAfter標頭_分類為範例表的錯誤`，依 spec 加上 503 `5`、503 `-1`、529 HTTP 日期三列。
    - `isRetryable_各種錯誤種類_與範例表的可否重試一致` 加上「status 503, retry delay 5 seconds」一列。
    - `LKOpenAIClientErrorTests` 的 HTTP 錯誤範例表，503 `server_is_overloaded` 列的期望值改成等待 5 秒。
  - **實作**：`init(httpStatusCode:retryAfter:)` 的 5xx 以 `retryDelay(from:)` 帶上等待時間。
  - **`///` 說明**：
    - `init` 的 Note 改成 429 與 5xx 都讀 `retryAfter`。
    - `LKOpenAIClient.httpError(statusCode:headers:body:)` 的 Note「只有走預設分類的 429 限流才由共同流程讀它」改成 429 與 5xx 都由共同流程讀。

  驗證：
  - 主對話先觀察到 503 `5` 列與 OpenAI 的 503 列在實作前失敗，實作後通過。
  - 完整 `swift test` 通過且零警告，測試數不變。
- [ ] 1.3 [after: 1.1] 依 design「5xx 的預設分類與 Anthropic 的 HTTP 錯誤讀 retry-after」，交付 anthropic-provider「Error mapping」中 HTTP 的服務不可用錯誤帶等待時間的部分（sonnet）：
  - **先加測試**：`LKAnthropicClientErrorTests` 的 HTTP 錯誤範例表，依 spec 加上 529 `overloaded_error` `retry-after: 10`、500 `api_error` `retry-after: 3`、504 `timeout_error` `retry-after: 7` 三列。
  - **實作**：`LKAnthropicErrorBody.Detail.lkaiError(statusCode:retryAfter:)` 的 `api_error`、`overloaded_error`、`timeout_error` 三個分支都帶上 `LKAIError.retryDelay(from: retryAfter)`。
  - **`///` 說明**：`LKAnthropicClient.httpError(statusCode:headers:body:)` 的 `headers` 參數說明「只讀 `retry-after`，用來算限流的等待時間」與 Note「`retry-after` 只有 `rate_limit_error` 會用到」，都改成三種服務不可用的錯誤也會讀。

  驗證：
  - 主對話先觀察到三列在實作前都失敗，實作後通過。
  - 完整 `swift test` 通過且零警告，測試數不變。

## 2. 不認得的串流錯誤

- [ ] 2.1 [after: 1.2] 依 design「不認得的串流錯誤以 unrecognizedStreamError 統一回報」，交付 chat-client 的「Unrecognized stream errors」，並讓 OpenAI 改用共用的函式（sonnet）：
  - **`LKAIError`**：在 Internal Method 區新增 `package static func unrecognizedStreamError(code: String?, message: String?) -> LKAIError`，說明文字的格式依 design 的 Implementation Contract。
  - **測試**：
    - 在 `LKAIErrorTests` 新增一個參數化測試，涵蓋 spec 範例表的四列，檢查錯誤種類、說明含的文字與 `isRetryable`。
    - 測試上方加兩行標記：`spectra-scenario: chat-client / Report a stream error the provider does not recognize` 與 `spectra-scenario: chat-client / Report a stream error the provider does not recognize / unrecognized stream errors`。
    - 先寫一律回傳 `.invalidResponse(reason: "")` 的最小骨架，讓測試能編譯。
  - **OpenAI**：
    - `LKOpenAIErrorBody.Detail.streamError` 的「其他不是 null 的代碼」與 null 代碼兩個分支，以及 `LKOpenAIStreamState` 在 `response.failed` 沒有 `response.error` 時的分支，都改呼叫新函式。
    - 這是行為不變的替換：`LKOpenAIClientErrorTests` 既有列的期望值不改。
    - `LKOpenAIClientErrorTests` 的串流 `error` 事件範例表，依 spec 加上兩列：`code` 與 `message` 都沒有（期望 500），以及 `code` 是數字 `500`（期望 `.invalidResponse`）。`ErrorEventCase` 的 `code` 只能表達字串或 null，這兩列改以原始的 `data` 字串組出事件。這兩列描述的是現有的行為，實作前就會通過。
    - `streamError` 的 `///` 拿掉「這和 Anthropic 把不認得的類型當成 500 不同」，改成指向 chat-client 的共同規則。

  驗證：
  - 主對話先觀察到新測試在骨架上失敗，實作後通過。
  - LKAIOpenAI 仍是 23 個測試，名稱與既有列的期望值不變而且通過。
  - 完整 `swift test` 通過且零警告；LKAICore 多 1 個測試。
  - `grep` 確認 `Sources/` 內沒有 `Unexpected error code`。
- [ ] 2.2 [after: 1.3, 2.1] 依 design「不認得的串流錯誤以 unrecognizedStreamError 統一回報」，交付 anthropic-provider「Error mapping」中串流錯誤改依共同規則的部分，以及 HTTP 沒有 `error.type` 時改用預設分類（sonnet）：
  - **`LKAnthropicErrorBody.Detail.type`** 改成 `String?`；`lkaiError(statusCode:retryAfter:)` 在 `type` 為 nil 時回傳 nil。
  - **`LKAnthropicStreamState.handle(_:)`**：`lkaiError` 回傳 nil 時，改丟 `LKAIError.unrecognizedStreamError(code: type, message: message)`。
  - **`///` 說明**，依 design 的同名決策：
    - `LKAnthropicErrorBody` 型別說明與 `Detail.lkaiError(statusCode:retryAfter:)` 的說明與 Returns：「類型不認得時」改成「沒有類型或類型不認得時」。
    - `Detail.type` 加上「沒有時為 nil」。
    - `LKAnthropicClient.httpError(statusCode:headers:body:)` 的說明與 Returns 同樣補上。
    - `LKAnthropicStreamState.handle(_:)` 拿掉「依規格以 500 處理」。
  - **`LKAnthropicClientErrorTests`**：
    - `Expectation` 改成和 OpenAI 相同的形狀：不帶值的 `.invalidResponse` 換成 `.invalidResponse(containing:)`，原本用它的列改成 `.invalidResponse(containing: [])`，並加上判斷說明含全部片段的比對。
    - 串流 `error` 事件範例表的 `new_unknown_error` 列帶上訊息 "Something went wrong."，期望值改成說明含 "new_unknown_error" 與 "Something went wrong." 的 `.invalidResponse`。
    - 同一張表加上兩列：`error` 物件沒有 `type`（期望 500），以及 `{"type":"error"}` 沒有 `error` 物件（期望 `.invalidResponse`）。
    - HTTP 錯誤範例表加上「400、`error` 物件沒有 `type`、`error.message` 為 "Bad request"」一列，期望 `.invalidRequest(message: nil)`。

  驗證：
  - 主對話先觀察到 `new_unknown_error` 列與串流「沒有 `type`」列在實作前失敗，實作後通過。
  - HTTP 400 列與串流「沒有 `error` 物件」列，描述的是實作前後都相同的行為，在實作前就會通過；依 TDD 的 Regression，由第 4 組的反向檢查「`lkaiError` 在 `type` 為 nil 時當成 `invalid_request_error`」把關 HTTP 400 列。
  - 完整 `swift test` 通過且零警告，LKAIAnthropic 仍是 45 個測試。

## 3. 說明文字與新增供應商的清單

- [ ] 3.1 [after: 2.2] 依 design「Context window limit 只適用於分開回報的供應商」「refused 的 detail 說明補上隱私提醒」，更新共用型別的說明，並為 chat-client「Context window limit」新增的情境加上測試標記（sonnet）：
  - `LKAIFinishReason` 的 `.maxOutputTokens` 與 `.contextWindowExceeded` 依 design 改寫 `///`，保留「輸入在生成前就超過上限時以錯誤出現」的提示，型別與 case 不變。
  - `LKAIError.refused(detail:)` 的 `///` 依 design 補上隱私提醒。
  - `LKAIError.invalidResponse(reason:)` 的 `///` 依 design 補上：也包含串流中供應商回報、但本套件不認得的錯誤代碼，`reason` 帶供應商的代碼與訊息。
  - `LKOpenAIClientStreamTests` 中標記 `openai-provider / Map terminal events` 的測試，再加一行 `spectra-scenario: chat-client / Provider reports a full context window as the output token limit`。

  驗證：
  - 主對話審查說明文字，確認符合 design 的寫法。
  - `git diff` 中 `LKAIFinishReason.swift` 的修改只有 `///` 行；`LKAIError.swift` 在 3.1 的修改只有 `///` 行。
  - 完整 `swift test` 通過且零警告。
- [ ] 3.2 [after: 2.2, 3.1] 依 design「新增供應商的清單取代 config.yaml 的層層指標」，新增 `docs/adding-a-provider.md`，並把 `docs/spectra/config.yaml` API 演進規則的指標換成 design 引用的文字（主對話）：
  - 清單有 design 列的七個章節。
  - 對照表三欄都寫上查證日期與方式；Gemini 一欄依本 change design 的 Context。
  - 第 3 章的規則、第 5 章的改寫對照、第 6 章的已定事項，都依實作完成後的程式碼與 spec 撰寫。
  - `config.yaml` 的 API 演進規則加上 design 決策「服務不可用的錯誤帶上等待時間，不給預設值」引用的那一條。

  驗證：
  - 主對話逐章對照 design，確認章節與內容齊全。
  - 第 7 章的對帳：把三份封存 design 的 Open Questions 逐項列出，與第 7 章比對，每一項都有，而且標了狀態。
  - `spectra instructions proposal --change "03-revise-chat-client-contract" --json` 回傳的 context 含有新的指標與新的 API 演進規則，都與 design 引用的文字逐字相同。

## 4. 驗收

- [ ] 4.1 [after: 1.2, 1.3, 2.2, 3.1, 3.2] 合併後的整體驗收（主對話）：依 design Implementation Contract 的「完成後的狀態」與「驗收」逐項執行，完成清單的核對與反向檢查表的十一項，並把每一項的執行結果記錄在本任務下方。

  驗證：
  - 每一項都符合 Implementation Contract 的描述。
  - 測試數與 Implementation Contract 的估計比對；不同時記錄實際的數字與原因。
  - `spectra coverage` 顯示 `chat-client`、`anthropic-provider`、`openai-provider` 的每個情境與範例都有測試。
