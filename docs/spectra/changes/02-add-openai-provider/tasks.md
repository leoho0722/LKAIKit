派工方式依 design「平行實作沿用兩個 git worktree」：

- 第 1、3 組由 haiku 在 `.worktrees/haiku` 實作，第 2 組由 sonnet 在 `.worktrees/sonnet` 實作。
- 建置、測試、反向檢查與合併都由主對話執行。

測試的做法：

- **1.1 是行為不變的搬移**：依 TDD 的 Regression，以既有測試把關，不改期望值。
- **2.1 到 2.4 是新行為**：
  - 先寫測試，以及讓測試能編譯的最小型別骨架。主對話觀察到新測試失敗後，才實作。
  - 測試寫在 `Tests/LKAIOpenAITests/`，事件以 1.1 搬過去的 `LKAIServerSentEventTestSupport` 組成逐行內容。
  - 每個測試上方依 spec 加 `spectra-scenario: openai-provider / <情境>` 註解，有範例時再加 ` / <範例>`。
  - 依 design「共同流程的分支不在 OpenAI 的測試重寫一份」，不為請求驗證、連線失敗、沒有結束事件、取消與釋放串流另寫 OpenAI 的測試。
- **2.1 的事件對應與錯誤分類**：讓 client 可以編譯的最小寫法。
  - 事件對應每則事件都回傳空陣列，2.2 起依 spec 逐步加入。
  - `httpError(statusCode:headers:body:)` 一律回傳 nil，交給共用的預設狀態碼分類；2.4 再加入 OpenAI 的分類。

## 1. SSE 分框的測試 helper

- [ ] 1.1 依 design「SSE 分框的測試 helper 搬進 LKAITestSupport」，讓兩家供應商的測試共用同一個 SSE 分框 helper，並為它沒有事件名稱的分支補上測試（haiku）：
  - 新增 `Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift`：沒有 case 的 `package enum`，只有 `package static func lines(of events: [LKAIServerSentEvent]) -> [String]`；`event` 為 nil 時不輸出 `event:` 那一行。
  - `LKAnthropicClientTestSupport` 移除自己的 `SSEEvent` 與 `lines(of:)`；Anthropic 的事件建構函式改寫成 `extension LKAIServerSentEvent` 的 static 方法。
  - `makeClient(events:)` 與 `LKAnthropicClientStreamTests`、`LKAnthropicClientErrorTests`、`LKAnthropicClientCancellationTests` 的呼叫處跟著修改。
  - `event` 為 nil 時不輸出 `event:` 行是新的分支，兩家目前的事件都走不到。新增 `Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift`，以參數涵蓋 `event` 有值與為 nil 兩種，先寫測試再實作。

  驗證：
  - `swift test` 全部通過且零警告，LKAIAnthropic 仍是 45 個測試，測試名稱與期望值不變。
  - `Tests/` 內的 `spectra-scenario:` 行排序後與修改前逐行相同。
  - `grep` 確認 `LKAnthropicClientTestSupport` 不再宣告 `SSEEvent` 與 `lines(of:)`。
  - 主對話先觀察到 `LKAIServerSentEventTestSupportTests` 在實作前失敗，實作後通過；LKAITestSupportTests 由 2 個增為 3 個測試。

## 2. LKAIOpenAI

- [ ] 2.1 交付 openai-provider 的「Responses API request」「Response storage setting」「API key secrecy」「Availability through LKAIKit」。依 design「LKOpenAIClient 照 LKAnthropicClient 的結構建立並遵循共同流程」「回應保存由 App 在建立 client 時選擇，預設不保存」「送出 Responses API 的請求內容」「輸出上限照原樣送出，由 API 檢查最小值」「金鑰遮蔽由每家 client 各自實作三個遵循」「型別依 ios-dev-kit 樣板建立，測試 target 依受測 target 增加」，完成以下改動（sonnet）：
  - **`Package.swift`**：新增 `LKAIOpenAI` 與 `LKAIOpenAITests`，`LKAIKit` 依賴 `LKAIOpenAI`。`Sources/LKAIKit/Exports.swift` 重新匯出 `LKAIOpenAI`。
  - **`LKOpenAIClient`**：建立方式、`LKAIChatClientProtocol` 與 `LKAIServerSentEventChatStreaming` 的遵循，以及三個不含金鑰的描述遵循。
  - **`LKOpenAIResponsesRequestBody`**：請求內容。
  - **事件對應**：先建立回傳空陣列的 `LKOpenAIStreamState`，2.2 起依 spec 加入對應。
  - **`///` 說明**：`LKOpenAIClient` 寫明 `refused` 的 detail 可能是模型寫的拒答文字、可能引用使用者的內容，記錄 log 時留意。
  - **新增的測試**：
    - 在 `LKOpenAIClientTests` 新增 spec「Responses API request」的四個情境、「Response storage setting」的範例表與以 URL session 建立的情境、「API key secrecy」的情境。
    - 在 `ExportsTests` 新增「Availability through LKAIKit」的情境。

  驗證：
  - 主對話先觀察到新測試在實作前失敗，實作後通過。觀察順序：
    - 「Availability through LKAIKit」只能以編譯失敗觀察。先在還沒有 `@_exported import LKAIOpenAI` 時看到 `ExportsTests` 編譯失敗，再補上重新匯出。
    - 補上之後，整個 `swift test` 才能建置，這時再觀察其餘新測試失敗。
  - 完整 `swift test` 通過且零警告；LKAIKit 為 3 個測試，其餘既有測試不變。
- [ ] 2.2 [after: 1.1, 2.1] 交付 openai-provider 的「Stream text mapping」「Responding model」「Usage mapping」。依 design「OpenAI 串流事件的對應規則」「實際回應的模型與用量取自結束事件的 response 物件」，讓 `LKOpenAIStreamState` 交出 `response.output_text.delta` 的文字，並在 `response.completed` 交出帶模型與用量的完成事件；其他事件不交出事件，`data` 不是合法的 JSON 時丟出 invalid response（sonnet）。
  - `LKOpenAIStreamEvent` 以 `LKAISnakeCaseJSON` 解碼。
  - 在 `LKOpenAIClientStreamTests` 新增以下測試：
    - spec「Stream text mapping」的兩個情境，含 stream with lifecycle and reasoning events 範例。
    - 「Responding model」的情境。
    - 「Usage mapping」的範例表。

  驗證：
  - 主對話先觀察到新測試在實作前失敗，實作後通過；完整 `swift test` 通過且零警告。
  - 例外：「Fail on malformed event data」在 2.1 的骨架上就會通過，看不到 RED，改由 4.1 的反向檢查「解碼失敗改成略過該則事件」把關。
- [ ] 2.3 [after: 2.2] 交付 openai-provider 的「Finish and refusal mapping」。依 design「OpenAI 串流事件的對應規則」「拒答文字作為 refused 的 detail，content_filter 以固定字串表示」「Responses API 沒有 context window 的結束原因」，加入以下對應（sonnet）：
  - `response.refusal.delta` 與 `response.refusal.done` 累積拒答文字；有 delta 時以 delta 為準，沒有時改用 done。
  - `response.completed`、`response.incomplete` 在拒答文字不為空時丟出 refused。
  - `response.incomplete` 依 `incomplete_details.reason` 對應。
  - `LKAIFinishReason` 的 `.maxOutputTokens` 與 `.contextWindowExceeded` 只改 `///` 說明，寫明 OpenAI 以 `.maxOutputTokens` 回報 context window 塞滿。
  - 在 `LKOpenAIClientStreamTests` 新增 spec「Finish and refusal mapping」的兩個情境，含 terminal events 範例表的七列；每列在第一個結束事件之後，再接一個 `response.completed`。

  驗證：主對話先觀察到新測試在實作前失敗，實作後通過；完整 `swift test` 通過且零警告。
- [ ] 2.4 [after: 2.3] 交付 openai-provider 的「Error mapping」。依 design「錯誤依 error.code 與 error.type 分類」「輸入超過 context window 的錯誤不設專屬種類」，完成錯誤對應（sonnet）：
  - 新增 `LKOpenAIErrorBody`，`message`、`type`、`code` 都宣告為 Optional，並提供判斷政策性阻擋代碼與額度代碼的兩個函式，HTTP 與串流共用。
  - `httpError(statusCode:headers:body:)` 依序套用 design 的四條 HTTP 規則。
  - 串流的 `error` 事件與 `response.failed` 依 `code` 分類，不認得的代碼丟出說明帶 `code` 與 `message` 的 invalid response。
  - 在 `LKOpenAIClientErrorTests` 新增 spec「Error mapping」的三個情境，含 error responses、error event codes、failed response errors 三個範例表。

  驗證：主對話先觀察到新測試在實作前失敗，實作後通過；完整 `swift test` 通過且零警告。

## 3. 實際 API 測試與文件

- [ ] 3.1 [after: 2.1] 依 design「實際 API 測試以 gpt-6-luna 執行，由 owner 手動跑」，新增 `Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift`（haiku）：
  - 串流與非串流各一個測試，都以 `gpt-6-luna`、輸出上限 4096 要求只回一個詞，檢查以完成結束、文字去掉空白後不為空。
  - 只在環境變數 `LKAI_OPENAI_API_KEY` 存在時執行，金鑰不出現在程式碼與輸出。
  - owner 的實際執行記在 4.2。

  驗證：主對話在沒有設定金鑰的環境執行 `swift test`，兩個測試顯示為略過，建置零警告。
- [ ] 3.2 依 design「config.yaml 的指標加上本 change」，把 `docs/spectra/config.yaml` API 演進規則的指標換成 design 引用的文字（主對話）。

  驗證：`spectra instructions proposal --change "02-add-openai-provider" --json` 回傳的 context 含有新的指標。

## 4. 驗收

- [ ] 4.1 [after: 1.1, 2.4, 3.1, 3.2] 合併兩組任務後的整體驗收（主對話）：依 design Implementation Contract 的「完成後的狀態」與「驗收」逐項執行，完成反向檢查表的十三項，並把每一項的執行結果記錄在本任務下方。

  驗證：每一項結果都符合 Implementation Contract 的描述：
  - LKAIAnthropic 仍是 45 個測試，LKAIKit 為 3 個。
  - `spectra coverage` 顯示 `openai-provider` 的每個情境與範例都有測試。
  - `LKAIKit-Package` 的 iOS 測試建置只有既有的 `Process` 錯誤。
- [ ] 4.2 [after: 4.1] owner 以自己的 OpenAI 金鑰執行實際 API 測試：
  - 金鑰存進 Keychain 的 service `lkai-openai-api-key`。
  - 執行 `LKAI_OPENAI_API_KEY="$(security find-generic-password -s lkai-openai-api-key -w)" swift test --filter LKAIOpenAITests`。

  驗證：兩個實際 API 測試都有執行而且通過，結果由主對話記錄在本任務下方。
