派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1、2 組與 3.1 由 sonnet 在 `.worktrees/sonnet`（分支 `wt/04-sonnet`）依序實作。
- 3.2 與 4.2 由主對話做；建置、測試、反向檢查、commit 與合併都由主對話執行。4.1 由 owner 執行。

測試的做法：

- **新行為先寫測試**：先寫測試與最小的骨架讓它能編譯，主對話觀察到新測試在實作前失敗，才實作。
- **行為不變的修改**：以既有測試把關，測試的名稱、期望值與測試數不變。
- **spec 標記**：每個為 `gemini-provider` 情境寫的測試，上方加 `// spectra-scenario: gemini-provider / <情境>`，有範例時再加一行 ` / <範例>`，名稱照抄 spec。
- **期望值的寫法**：`.serviceUnavailable` 一律明寫兩個 associated value；說明文字只檢查「含有這些片段」，用 `LKAIErrorTestSupport.Expectation.invalidResponse(containing:)`。
- **排版與說明**：依 ios-dev-kit；每行不超過 100 字元，以字元數計，JSON 測試資料與 `spectra-scenario` 標記行除外。

## 1. 金鑰包裝型別與共用的測試 helper

- [x] 1.1 依 design「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」，在 `LKAICore` 新增 `package struct LKAIAPIKey`，形狀照 Implementation Contract（sonnet）：
  - **先寫測試**：`Tests/LKAICoreTests/Networking/LKAIAPIKeyTests.swift` 以參數化測試檢查：
    - `String(describing:)`、`String(reflecting:)`、`dump(_:)` 的結果都不含原始值，而且前兩者等於 `LKAIAPIKey(redacted)`。
    - 一個不寫任何描述遵循、只有 `LKAIAPIKey` 欄位的測試用 struct，三種輸出也都不含原始值。這一列固定了討論時以 Swift 6.4.2 做的實測。
    - `unredactedValue` 等於建立時的值。這一列在骨架上就會通過，屬於回歸保護；測試的其他列在骨架上失敗。
    - 先以「描述回傳原始值」的骨架讓測試編譯。
  - **實作**：`Sources/LKAICore/Networking/LKAIAPIKey.swift`。

  驗證：
  - 主對話觀察到新測試在骨架上失敗，實作後通過。
  - 完整 `swift test` 通過且零警告，`LKAICore` 從 67 個變成 68 個。這是估計值，實際數字記在 4.2。
- [x] 1.2 [after: 1.1] 依同一個決策，`LKAnthropicClient` 與 `LKOpenAIClient` 改以 `LKAIAPIKey` 保存金鑰，行為不變（sonnet）：
  - `private let apiKey` 的型別改成 `LKAIAPIKey`；公開與 `package` 的 `init(apiKey: String, …)` 不變，在 init 內包裝。
  - 只有 `makeURLRequest(for:)` 讀 `unredactedValue`。
  - 三個描述遵循的內容不變。

  驗證：
  - 兩家既有的金鑰遮蔽測試（anthropic-provider 與 openai-provider 的「Describe a configured client」）不改就通過。
  - 完整 `swift test` 通過且零警告，測試數不變。
  - `grep -rn 'unredactedValue' Sources | grep -v '///'` 只出現在 `LKAIAPIKey.swift` 與兩家的 `makeURLRequest(for:)`；`grep -rn 'let apiKey: String' Sources` 沒有結果。
- [x] 1.3 依 design「與供應商無關的測試 helper 收進 LKAITestSupport」，把兩家測試裡與供應商無關的 helper 搬進 `LKAITestSupport`，兩家的測試改用它們，行為不變（sonnet）：
  - **新增**：`Sources/LKAITestSupport/` 的 `LKAITestJSON` 與 `LKAIErrorTestSupport`，形狀照 Implementation Contract；`LKAIErrorTestSupport.Expectation.matches(_:)` 的 nil 一律不符合；`Expectation` 的說明採用 Anthropic 那份。
  - **測試**：`Tests/LKAITestSupportTests/` 新增三個測試：
    - `matches` 的參數化測試，列出：錯誤相等、錯誤不相等、無效回應含全部片段、缺一個片段、不是無效回應、空的片段清單、nil。
    - `optionalField` 的參數化測試，列出有值與 nil 兩列。
    - `booleanField` 的參數化測試，列出：`true`、`false`、數字 `1`（丟出）、字串 `"true"`（丟出）、欄位不存在（丟出）。
  - **遷移**：
    - 刪掉 `LKAnthropicClientTests` 與 `LKOpenAIClientTests` 的 `jsonObject(from:)` 與 `jsonFragment(from:)`，以及 `LKAIServerSentEvent+AnthropicEvents.swift` 與 `LKAIServerSentEvent+OpenAIEvents.swift` 的 `optionalField(_:_:)`。
    - 刪掉 `LKOpenAIClientTests` 的 `BooleanFlagsBody` 與 `decodeBooleanFlags(of:)`，以及 `LKAnthropicClientTests` 的 `StreamFlagBody` 與 `decodeStreamFlag(of:)`，呼叫端改用 `LKAITestJSON.booleanField(_:in:)`。`decodeBooleanFlags(of:)` 一次要求 `stream` 與 `store` 都是 JSON 布林，所以原本只斷言 `store` 的保存設定測試，也要呼叫 `booleanField("stream", in:)`，保持行為不變。
    - 刪掉 `LKAnthropicClientErrorTests` 與 `LKOpenAIClientErrorTests` 的 `Expectation` 與 `matches(_:_:)`，以及 `LKAnthropicClientStreamTests` 與 `LKOpenAIClientStreamTests` 的 `isInvalidResponse(_:)`。
    - `LKOpenAIClientStreamTests.ErrorExpectation` 改用 `LKAIErrorTestSupport.Expectation`，不帶值的 `.invalidResponse` 改成 `.invalidResponse(containing: [])`。
    - 呼叫端改用搬過去的版本。
  - `LKAIErrorTests.UnrecognizedStreamCase.Expectation` 不動。

  驗證：
  - `LKAIAnthropicTests` 仍是 45 個、`LKAIOpenAITests` 仍是 23 個，名稱與期望值不變；`LKAITestSupportTests` 從 3 個變成 6 個。
  - 完整 `swift test` 通過且零警告。
  - Implementation Contract「完成後的狀態」中 `Tests/` 的 grep 條件都成立。
  - 主對話的反向檢查，三種改壞方式各做一次：
    - `matches` 改成不檢查片段：`LKAITestSupportTests` 的「缺一個片段」列失敗。比對變寬鬆只會讓「預期不符合」的列失敗，兩家帶片段的列在正確實作上本來就符合，所以不會失敗。
    - `.invalidResponse` 的比對一律回傳 false：兩家期望 `.invalidResponse(containing:)` 的列都失敗，例如 `new_unknown_*` 與資料不是 JSON 的列；呼叫 `isInvalidResponse(_:)` 的測試也會失敗，因為它以 `matches` 實作。
    - `booleanField` 改成接受數字 `1`：`LKAITestSupportTests` 的數字 `1` 列失敗。

## 2. Gemini 供應商

- [x] 2.1 [after: 1.1, 1.3] 依 design「以 Interactions API v1 實作，串流與非串流都送 stream: true」「回應保存預設關閉，由 App 建立 client 時開啟」，建立 `LKAIGemini` 與 `LKGeminiClient`，交付 gemini-provider 的「Interactions API request」「Response storage setting」「API key secrecy」「Availability through LKAIKit」（sonnet）：
  - **target**：`Package.swift` 新增 `LKAIGemini` 與 `LKAIGeminiTests`，`LKAIKit` 加上依賴；`Sources/LKAIKit/Exports.swift` 加上 `@_exported import LKAIGemini`。
  - **client**：`LKGeminiClient` 比照 `LKOpenAIClient` 的結構與 MARK 分區，形狀照 Implementation Contract，以 `LKAIAPIKey` 保存金鑰；`makeURLRequest(for:)` 與請求內容 `LKGeminiInteractionsRequestBody`。`httpError` 先一律回傳 nil，`makeEventMapper()` 先回傳不交出任何事件的 `LKGeminiStreamState`，2.2 與 2.3 再實作。
  - **先寫測試**：
    - `Tests/LKAIGeminiTests/LKGeminiClientTests.swift`：spec 的三個請求情境、保存設定範例表、以 `URLSession` 建立時的 `Mirror`、金鑰遮蔽情境。請求與保存設定的測試，另以 `LKAITestJSON.booleanField(_:in:)` 確認 `stream` 與 `store` 是 JSON 布林，因為 `NSDictionary` 比對會把 `1` 當成 `true`（第一份 design 的實測）。
    - `LKGeminiClientTestSupport`：比照 `LKOpenAIClientTestSupport` 提供共用的請求、建立 client 與預期的結束事件。
    - `Tests/LKAIKitTests/ExportsTests.swift`：加上 Gemini 的測試。

  驗證：
  - 主對話觀察到請求與保存設定的測試在實作前失敗，例如請求內容與標頭不符，實作後通過。
  - 下列測試在實作前就會通過，屬於回歸保護，不代表測試寫錯：
    - `ExportsTests` 的 Gemini 測試：型別存在就通過。
    - 三種描述與 `dump(_:)` 不含金鑰：`LKAIAPIKey` 本身就保證遮蔽。
    - HTTP 401 的錯誤描述不含金鑰：骨架的 `httpError` 回傳 nil，預設分類得到 `.invalidAPIKey`。
    - 以 `URLSession` 建立時的 `Mirror`：骨架有預設為 false 的 `shouldStoreResponses` 欄位時就會通過。
  - 完整 `swift test` 通過且零警告；`swift package dump-package` 顯示 `LKAIGemini` 只依賴 `LKAICore`，products 仍只有 `LKAIKit` 與 `lkai`。
- [x] 2.2 [after: 2.1] 依 design「文字只取 model_output 步驟的 text 片段，步驟類型依 step.start 的 index 記錄」「interaction.completed 依狀態對應結束原因，incomplete 回報 maxOutputTokens」「用量的輸出 token 加上思考 token」「實際回應的模型取自 interaction.completed」「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」，交付 gemini-provider 的「Stream text mapping」「Finish mapping」（`failed` 六列除外，見 2.3）「Responding model」「Usage mapping」（sonnet）：
  - **先寫測試**：
    - `Tests/LKAIGeminiTests/LKGeminiClientStreamTests.swift`，事件以 `Tests/LKAIGeminiTests/LKAIServerSentEvent+GeminiEvents.swift` 的建構函式產生，比照兩家的寫法。範例表的值照抄 spec。
    - 實際回應模型的測試，`interaction.created` 不帶 `model`，只有 `interaction.completed` 帶，才分得出實作取的是哪一則。
  - **實作**：
    - `LKGeminiStreamEvent` 依 `event_type` 解碼，經 `LKAISnakeCaseJSON`：最外層的分派比照 `LKOpenAIStreamEvent`，巢狀的 `step`、`delta`、`interaction` 比照 `LKAnthropicStreamEvent` 的 `ContentBlock` 與 `Delta` 手寫條件式解碼，`CodingKeys` 用 camelCase、不寫 raw value，見 Implementation Contract。
    - `LKGeminiStreamState` 持有 `index` 到步驟類型的對照，比照 `LKOpenAIStreamState` 的結構，依 Implementation Contract 的事件對應表處理。
    - 解碼照 Implementation Contract「只在用得到時才解碼欄位」：`step.content` 只在 `model_output` 時解、`delta.text` 只在 `delta.type` 為 `text` 時解而且必須是字串（沒有、null 或型別不對都在解碼時失敗，不論步驟類型），`interaction.errors` 在 2.2 不讀。
    - `error` 事件先當成不認得的事件略過，`failed` 狀態先當成其他狀態回報 `.invalidResponse`，2.3 再實作；這樣 2.3 的新測試才會在實作前失敗。
  - **說明**：`LKAIFinishReason.maxOutputTokens` 的 `///` 例子加上 Gemini，只改 `///`。

  驗證：
  - 主對話觀察到新測試在 2.1 的 mapper 骨架上失敗，實作後通過。
  - 「Fail on malformed event data」與「Fail on events missing required fields」在骨架上就會通過，屬於回歸保護：骨架不交出任何事件，讀完沒有 `.finished` 時，共同流程同樣回報 `.invalidResponse`。
  - 完整 `swift test` 通過且零警告；`LKAIFinishReason.swift` 相對 `main` 只有 `///` 行改變。
- [x] 2.3 [after: 2.2] 依 design「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」「生成被擋下的代碼回報 refused，HTTP 與串流相同」「串流的 error 事件依 error.code 分類」，交付 gemini-provider 的「Error mapping」與「Finish mapping」的 `failed` 六列（sonnet）：
  - **先寫測試**：
    - `Tests/LKAIGeminiTests/LKGeminiClientErrorTests.swift` 的 HTTP 錯誤範例表與 `error` 事件範例表，以及 2.2 的結束事件範例表補上 `failed` 六列。範例表的值照抄 spec。
    - HTTP 測試以非串流呼叫，比照 `LKOpenAIClientErrorTests`。
    - `error` 事件之後再接一則 status 為 `completed` 的 `interaction.completed`，比照 `LKOpenAIClientErrorTests`，讓「把 `error` 事件略過」的錯誤實作會失敗。
  - **實作**：
    - `LKGeminiErrorBody`（Interactions 格式）與 `LKGeminiGoogleErrorBody`（Google 通用格式，陣列與物件兩種外層都接受），由 `httpError(statusCode:headers:body:)` 依序嘗試，比照 `LKOpenAIErrorBody` 的結構。
    - `error` 事件與 `failed` 的 `errors` 共用同一個依代碼分類的函式，對應不到時呼叫 `LKAIError.unrecognizedStreamError(code:message:)`。
    - `interaction.errors` 只在 `status` 為 `failed` 時解碼，照 Implementation Contract「只在用得到時才解碼欄位」。

  驗證：
  - 主對話觀察到新的列在實作前失敗。
  - HTTP 表中走預設分類就得到期望值的列，在實作前就會通過，屬於回歸保護：
    - 402 `payment_required`、沒有 `message` 的 400 `invalid_request`。
    - 429 `too_many_requests`、429 `rate_limit_exceeded`、503、500、502。
    - 401 與 403 的 Google 通用格式、沒有 `API_KEY_INVALID` 的兩列 400 Google 通用格式。
  - 結束事件表的 `failed` 帶數字代碼一列，在 2.2 把 `failed` 當成其他狀態時就會通過，也屬於回歸保護。
  - 完整 `swift test` 通過且零警告；`Sources/LKAIGemini/` 內沒有「Unrecognized stream error code」、`Task {` 與 `JSONDecoder()`。
- [x] 2.4 [after: 2.1] 依 design「實際 API 測試以 gemini-3.5-flash-lite 執行，由 owner 手動跑」，新增 `Tests/LKAIGeminiTests/LKGeminiClientLiveTests.swift`（sonnet）：
  - 串流與非串流各一個，比照 `LKOpenAIClientLiveTests`。
  - 只在設定 `LKAI_GEMINI_API_KEY` 時執行，模型 `gemini-3.5-flash-lite`，輸出上限 64。
  - 檢查以完成結束、文字不為空、回應的模型不是 nil 也不是空字串。

  驗證：沒有設定環境變數時，完整 `swift test` 把這兩個測試列為略過；主對話審查測試內容。實際執行見 4.1。

## 3. 文件

- [x] 3.1 [after: 1.2, 2.3, 2.4, 4.1] 依 `config.yaml` 的指標與 `docs/adding-a-provider.md` 第 1 章「什麼時候更新」，把清單更新成 Gemini 實作後的狀態，逐列處理下面每一處（sonnet）：
  - **第 2 章**：把「Gemini 查證時，文件與實際回應有四處不同」更新成本 change Context 的結果。
  - **第 3 章**：
    - 「金鑰與隱私」：金鑰以 `LKAIAPIKey` 保存，只有 `makeURLRequest(for:)` 讀 `unredactedValue`；附上兩個 grep 檢查：`grep -rn 'unredactedValue' Sources | grep -v '///'` 只出現在 `LKAIAPIKey.swift` 與各家的 `makeURLRequest(for:)`，`grep -rn 'let apiKey: String' Sources` 沒有結果。原本那一條結尾的「04 預定加上包裝型別，見第 6 章」改成指向本 change 的決策「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」。
    - 「測試」：錯誤的期望值與 JSON helper（含 `booleanField(_:in:)`）用 `LKAIErrorTestSupport` 與 `LKAITestJSON`；`LKAICoreTests` 不依賴 `LKAITestSupport`，所以 `LKAIErrorTests` 保留自己的 `Expectation`，出處寫 `01-extract-chat-stream-skeleton` 的決策「Anthropic 的測試走不到的共同行為在 LKAICoreTests 直接測試」。
    - 第 3 章新增的每一條規則，都在括號中附上出處：change 名稱與決策標題。
    - 「錯誤」：供應商的錯誤格式不只一種時，每種都在 `httpError` 中處理；狀態碼之外的金鑰錯誤要辨識出來。
    - 「串流的共同流程」：事件的巢狀欄位只在用得到時才解碼，比照 `LKAnthropicStreamEvent` 與 `LKGeminiStreamEvent`；經 `LKAISnakeCaseJSON` 解碼的型別，手寫的 `CodingKeys` 用 camelCase、不寫 raw value。出處是本 change 的決策「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」。並寫明 `LKOpenAIStreamEvent` 的 `Response` 是已知的例外，見第 7 章。
  - **第 4 章**：Gemini 一欄改成本 change 的查證結果，含「不認得的串流錯誤」一列；「查證日期與方式」比照另外兩家，寫上 4.1 實際 API 測試的模型與日期；「伺服器端保存」的「04 預定比照 OpenAI 預設不保存」改成已實作的狀態。
  - **第 5 章**：
    - 加上 `03-revise-chat-client-contract` 的決策「新增供應商的清單取代 config.yaml 的層層指標」中「Google 通用格式交給預設分類」一句，對應到本 change 的決策「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」。
    - 更新既有的「02 的決策『金鑰遮蔽由每家 client 各自實作三個遵循』」一列：依據從「預定由 04 改寫」改成本 change 的決策，不另加一列。
  - **第 6 章**：內容移進第 3、4、7 章後清空，章名改成「下一家供應商」，寫明目前沒有已定好的事；保留一句通用的生命週期說明：下一家供應商的 change 封存時，同樣把這一章的內容移走後清空。原本「不做的事」（`makeURLRequest(for:)` 與 `encodeBody(for:)` 不收進 `LKAICore`）移到第 7 章的對應列。
  - **第 7 章**：
    - 「屬於下一家」的兩項標成已解決，依據是本 change 的決策。
    - 01「金鑰遮蔽的三個遵循要每家各寫一次」一列：「04 加上包裝型別，見第 6 章」改成指向本 change 的決策。
    - 02「`makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 各寫一份」一列：依據改成不依賴第 6 章的句子，並寫明重新評估的條件，即 02 設的「要統一加標頭或改編碼設定時」，也就是本 change 的 Non-Goals。
    - 第一份與 02 的「輸入超過 context window」兩項：依據改成本 change 的決策「輸入超過 context window 不特別處理」，拿掉「列在第 6 章待實測」。
    - 加上本 change 的四項 Open Questions。
  - 完成後，清單內沒有指向第 6 章舊內容的引用。第 2 章步驟 2「處理第 6 章與第 7 章中屬於這家供應商的項目」與第 7 章開頭「屬於下一家（見第 6 章）」說明的是流程，保留不改。

  驗證：
  - 主對話審查內容：每一處修改都有 design 或程式碼的依據，第 3 章提到的符號都存在。
  - `grep -n '第 6 章' docs/adding-a-provider.md` 只剩第 2 章步驟 2 與第 7 章開頭兩處。
  - `grep -n -E '預定|由 04' docs/adding-a-provider.md` 沒有結果。
- [x] 3.2 [after: 3.1] 主對話依 design 的「完成後的狀態」與清單核對 `config.yaml` 的指標與 API 演進規則：確認不必修改，或修改並寫明原因。

  驗證：主對話的檢查結果記在本任務下方。

  檢查結果（2026-11-22，主對話，功能分支 `0569ec7`）：`config.yaml` 不必修改。
  - **指標**：「新增供應商的 change 開始前，先讀 `docs/adding-a-provider.md`」那條只指向清單本身，不寫章節號，3.1 改寫章節內容後仍然正確；「以 SSE 串流回答的供應商一律遵循 `LKAIServerSentEventChatStreaming`，不自行建立 `Task`」與實作相符（`grep 'Task {' Sources/LKAIGemini` 沒有結果）。本 change 新增的規則（`LKAIAPIKey`、條件式解碼、camelCase 的 `CodingKeys`、測試 helper）都寫在清單第 3 章，依 03 的決策「新增供應商的清單取代 config.yaml 的層層指標」，不在 `config.yaml` 另寫。
  - **命名規則**：模組 `LKAIGemini` 符合 `LKAI<名稱>`；供應商 target 的頂層型別都以 `LKGemini` 開頭；`LKAITestSupport` 與 `LKAICore` 新增的 `LKAITestJSON`、`LKAIErrorTestSupport`、`LKAIAPIKey` 符合 `LKAI<名稱>`；沒有型別與模組同名；新增的 Sources 沒有頂層函式，extension 都是本 package 的型別。
  - **API 演進規則**：`git diff main -- Sources/LKAICore` 沒有任何 `public` 宣告改變（`LKAIFinishReason` 只改 `///`，`LKAIAPIKey` 是 `package`）；公開 API 只新增 `LKGeminiClient`，沒有修改共用公開型別，不需要另開 change 修改 chat-client spec。

## 4. 驗收

- [x] 4.1 [after: 2.3, 2.4] owner 以自己的金鑰執行實際 API 測試：`LKAI_GEMINI_API_KEY="$(security find-generic-password -s lkai-gemini-api-key -w)" swift test --filter LKGeminiClientLiveTests`，在功能分支上執行：2.1 到 2.4 都已合併回功能分支之後。排在整體驗收與清單更新之前，因為這是唯一以真實 API 檢查 mapper 的步驟；失敗而要改 mapper 時，整體驗收與清單的 Gemini 一欄都不必重做。

  驗證：串流與非串流兩個測試都通過，輸出沒有出現金鑰。
- [x] 4.2 [after: 1.2, 2.3, 2.4, 3.2, 4.1] 合併後的整體驗收（主對話）：依 design Implementation Contract 的「完成後的狀態」與「驗收」逐項執行，含十八項反向檢查，並把每一項的結果，以及 4.1 的結果，記錄在本任務下方。

  驗證：
  - 每一項都符合 Implementation Contract 的描述。
  - 測試數與估計值比對，不同時記錄實際數字與原因。
  - `spectra coverage 04-add-gemini-provider` 顯示每個情境與範例都有測試。

  驗收結果（2026-11-22，主對話，功能分支 `0569ec7`；`Sources/`、`Tests/` 與 `Package.swift` 在 `ceeef86` 之後沒有改變，十八項反向檢查在 `ceeef86` 執行）：

  **4.1 的結果**：owner 同意後由主對話在功能分支（`ceeef86`）執行 `LKAI_GEMINI_API_KEY="$(security find-generic-password -s lkai-gemini-api-key -w)" swift test --filter LKGeminiClientLiveTests`，模型 `gemini-3.5-flash-lite`、輸出上限 64：串流與非串流兩個測試都通過；在同一個 shell 以 `grep -F` 比對，輸出沒有出現金鑰。

  **完成後的狀態**：
  - `grep -rn 'unredactedValue' Sources | grep -v '///'`：只有 `LKAIAPIKey.swift`（宣告、init 參數與賦值）與三家 client 的 `makeURLRequest(for:)` 各一處。
  - `grep -rn 'let apiKey: String' Sources`：沒有結果。
  - `Tests/` 內的 helper grep：只剩 `Tests/LKAICoreTests/Chat/LKAIErrorTests.swift` 的 `UnrecognizedStreamCase.Expectation`（依規定保留）。
  - `Sources/LKAIGemini/` 內沒有「Unrecognized stream error code」、`Task {` 與 `JSONDecoder()`。
  - `LKAIAnthropicTests` 45 個、`LKAIOpenAITests` 23 個；1.3 前後比對過測試名稱與每個參數化測試的列數，都沒有改變。

  **建置與測試**：`swift package clean` 後，`swift build`、`swift build --build-tests` 與完整 `swift test` 都成功、零警告。XcodeBuildMCP 清除後對 iOS 模擬器（iPhone 17）建置 `LKAIKit` scheme 成功、零警告，log 確認 `Sources/LKAIGemini/` 的 6 個檔案都有編譯。

  **測試數**（都與估計值相同）：`LKAICore` 67 → 68；`LKAITestSupportTests` 3 → 6；`LKAIKit` 3 → 4；`LKAIGemini` 新增 19 個（含 2 個實際 API 測試，沒有設定環境變數時列為略過）；`LKAIKitCLITests` 7 個不變。

  **spec 覆蓋**：`spectra coverage 04-add-gemini-provider` 為 annotated 25、excluded 0、missing 0；逐一讀過標記的測試，斷言對應 THEN，spec 範例中的 58 個 JSON 字面值都原樣出現在測試中，每張範例表的每一列都有測試案例。

  **十八項反向檢查**（每項改壞一處、以 `swift test --no-parallel --filter 'LKAIGeminiTests|LKAIAPIKeyTests'` 執行、再還原；做完 `git diff -- Sources` 沒有差異）：
  1. 思考步驟的片段也交出：範例「stream with lifecycle events and a thought step」失敗。
  2. 不記錄步驟類型，只看 `delta.type`：同一個範例失敗。
  3. `incomplete` 回報完成：結束事件表的 `incomplete` 列失敗；「Finish at the output token limit while still thinking」也失敗。
  4. 輸出 token 不加思考 token：用量表第一列失敗。
  5. 不讀 `API_KEY_INVALID`：HTTP 表中帶 `API_KEY_INVALID` 的兩列（陣列與物件外層）失敗。
  6. 串流的 `safety` 不回報 `.refused`：`error` 事件表的 `safety` 列失敗；同一個寫法也讓 `recitation` 列與結束事件表 `failed` 帶 `safety` 列失敗。
  7. `store` 預設送 true：保存設定表的「not set」列失敗；「Send a request with a system prompt」的兩列也失敗。
  8. 不認得的代碼回報 500：`error` 事件表的 `new_unknown_code` 列失敗。
  9. `LKAIAPIKey.description` 回傳原始值：`LKAIAPIKey` 的測試失敗（`unredactedValue` 以外的 6 列）。
  10. `failed` 不看 `errors`：結束事件表 `failed` 帶 `safety` 列失敗。
  11. Interactions 規則 3 不排除 429：HTTP 表的 429 `too_many_requests` 列失敗；429 `rate_limit_exceeded` 列也失敗。
  12. `step.start` 的 `step.content` 不交出：範例「text in the start of a model output step」失敗。
  13. 把無法解碼的 `error` 事件略過：`error` 事件表的 `{"event_type":"error"}` 列失敗；`code` 為數字的列也失敗。
  14. Google 通用格式只接受陣列外層：HTTP 表中物件外層、帶 `API_KEY_INVALID` 的列失敗。
  15. 不論步驟類型都解碼 `step.content`：範例「stream with lifecycle events and a thought step」失敗（`google_search_call` 的物件 `content`）。
  16. 不論狀態都解碼 `interaction.errors`：結束事件表「status `completed`、`errors` 是 `"none"`」列失敗。
  17. 不論 `delta.type` 都解碼 `delta.text`：範例「stream with lifecycle events and a thought step」失敗（`google_search_result` 的物件 `text`）。
  18. 照簡化前的規則實作（`delta.text` 解成 Optional，只有 `model_output` 步驟缺 `text` 才失敗）：缺欄位表中 `index` 3、`delta.text` 為 null 的列失敗。改壞的寫法同時放寬了 `step.content` 項目的 `text`（兩者共用 `TextPart`），所以「content 項目缺 `text`」列也失敗。

## 5. 實作審查的修正

四份審查（`/spectra-verify`、`/spectra-review`、fable、opus）都沒有必須修正的問題。以下是主對話查證成立、使用者在 2026-11-22 決定處理的項目：

- 5.1、5.2 修正說明與共用 helper，5.3 補清單，5.4 補 spec 新增的範例與情境的測試，5.5 是行為不變的重構。
- 其餘不處理的項目寫在 design 的 Open Questions，由 5.3 寫進清單第 7 章。
- 派工依 design「實作由 sonnet 在單一 worktree 依序進行」：5.1 到 5.5 由 sonnet 在 `.worktrees/sonnet`（分支 `wt/04-sonnet`）依序做，完成後第三次合併回功能分支，5.6 由主對話做。

- [x] 5.1 修正實作審查找到的三處說明與規範，行為不變（sonnet）：
  - `LKGeminiClientTestSupport.finishedEvent(_:usage:respondingModel:)` 的 `///`：預設模型對應的是 `LKAIServerSentEvent.interactionCompleted(status:model:usage:errors:)` 預設的模型，不是 `validRequest` 的模型；比照 `LKOpenAIClientTestSupport` 的寫法。
  - `LKGeminiErrorBody.Detail.httpError(statusCode:)` 的 `///` 中「額度用完不讀 `retry-after`」的理由，改成 design 決策「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」的理由：`quota_exceeded` 要等每日額度重置、`payment_required` 要補餘額，重試沒有用。不再寫成 Gemini 文件的說法。
  - `LKAITestJSON` 的 `OptionalBoolean.init(from:)`：`try?` 的理由依 ios-dev-kit `coding-style.md` 寫在同一行，格式是「// 失敗可忽略，因為 …」。超過 100 字元時縮短理由。

  驗證：
  - 完整 `swift test` 通過且零警告，測試數不變。
  - 主對話審查 diff：只有 `///` 與註解改變。
- [x] 5.2 依 design 決策「與供應商無關的測試 helper 收進 LKAITestSupport」補上的 `sourceLocation`，讓 `LKAITestJSON.jsonObject(from:)` 解析失敗時，問題記在呼叫端那一行（sonnet）：
  - **先寫測試**：`Tests/LKAITestSupportTests/LKAITestJSONTests.swift` 加一個參數化測試，列出文字版與 `Data` 版，傳入最外層不是物件的 JSON（例如 `[1]`），以 `try withKnownIssue { … } matching: { $0.sourceLocation?.fileName == "LKAITestJSONTests.swift" }` 確認問題記在測試檔。
  - **實作**：兩個版本加上 `sourceLocation: SourceLocation = #_sourceLocation`，文字版轉傳給 `Data` 版，`Data` 版傳給 `#require`；`///` 補上參數說明。`jsonFragment(from:)` 不改，理由見 design。

  驗證：
  - 主對話觀察到新測試在實作前失敗（問題記在 `LKAITestJSON.swift`），實作後通過。
  - 完整 `swift test` 通過且零警告；`LKAITestSupportTests` 從 6 個變成 7 個。
- [x] 5.3 把實作審查的結論寫進 `docs/adding-a-provider.md`，讓下一家供應商照著做（sonnet）：
  - **第 3 章「架構與命名」**：
    - 加一條：參考實作是 `Sources/LKAIGemini/` 與 `Tests/LKAIGeminiTests/`，逐一列出每個檔案的角色（client、請求內容、串流事件、mapper、兩種錯誤格式；測試的請求、串流、錯誤、實際 API、事件建構函式、測試 helper）。錯誤分類用 `streamError` 與 `httpError(statusCode:)` 兩個入口。
    - 列出新增供應商要動的既有檔案：`Package.swift` 的三處（新 target、新測試 target、`LKAIKit` 的依賴）、`Sources/LKAIKit/Exports.swift`、`Tests/LKAIKitTests/ExportsTests.swift`。
    - 出處是本 change 的實作審查（fable 指出）。
  - **第 3 章「金鑰與隱私」**：有伺服器端保存的那一條補上參數名一律是 `shouldStoreResponses`，讓 App 換供應商時寫法一致（`02-add-openai-provider` 與本 change 的決策「回應保存預設關閉，由 App 建立 client 時開啟」）。
  - **第 7 章**：加上 design Open Questions 中「實作審查（2026-11-22）留下」的五項，出處寫 `04`，狀態「留給之後」，依據照 design 的句子。其中 `decode(_:)` 與 `encodeBody(for:)` 的重複，併進既有的 02「`makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 各寫一份」一列：補上三家的 `decode(_:)` 相同，重新評估的時機加上「下一家供應商的第一組任務」。

  驗證：
  - 主對話審查內容：每一處都有 design 或程式碼的依據，提到的檔案與符號都存在。
  - `grep -n '第 6 章' docs/adding-a-provider.md` 仍只有第 2 章步驟 2 與第 7 章開頭兩處；`grep -n -E '預定|由 04' docs/adding-a-provider.md` 沒有結果。
- [x] 5.4 為 spec 新增的範例內容與情境補上測試，交付 gemini-provider「Stream text mapping」與「Responding model」新增的部分（sonnet）：
  - 範例「stream with lifecycle events and a thought step」的測試，在 `index` 2 的 `step.stop` 之後加上 `index` 5、`delta.type` 為 `text`、文字 "Orphan" 的 `step.delta`，期望值不變。
  - 範例「text in the start of a model output step」的測試，`step.content` 加上 `{"type":"image","data":"aGk="}` 項目，期望值不變。
  - 缺欄位範例表加上 `content` 不是陣列、`content` 項目沒有 `type` 的兩列，data 照抄 spec。
  - 新增情境「Report no model when the completed interaction has none」的測試：`interaction.created` 帶 `gemini-3.6-flash`、`interaction.completed` 不帶 `model`，期望結束事件的模型是 nil；上方加 `spectra-scenario` 標記。

  驗證：
  - 這些都是已經實作的行為，在目前的實作上就會通過，依 TDD 的 Regression 由 5.6 的反向檢查 19 到 22 確認它們抓得到錯。
  - 完整 `swift test` 通過且零警告；`LKAIGemini` 從 19 個變成 20 個。
  - `spectra coverage 04-add-gemini-provider` 沒有缺漏。
- [x] 5.5 [after: 5.4] 依 design 決策「解碼端的判斷結果帶在事件裡，mapper 不再比對字串」重構 `LKGeminiStreamEvent` 與 `LKGeminiStreamState`，行為不變（sonnet）：
  - `step.start` 的事件帶「是不是 `model_output` 步驟」的布林值與要交出的文字；`LKGeminiStreamState` 改存 `model_output` 步驟的 `index` 集合，同一個 `index` 之後以別的類型開始時從集合移除。
  - `interaction.completed` 的 `failed` 解成獨立的事件，帶 `errors` 的第一筆；其他狀態照舊帶 `Interaction`。解碼的欄位與順序不變，`failed` 時仍解碼 `usage` 與 `model`。
  - 同步修改兩個型別的 `///`；design 的 Implementation Contract 已描述重構後的結構，不必修改。

  驗證：
  - 測試檔不改；完整 `swift test` 通過且零警告，測試數與 5.4 完成時相同。
  - `grep -n '"model_output"\|"failed"' Sources/LKAIGemini/LKGeminiStreamState.swift` 沒有結果。
- [x] 5.6 [after: 5.1, 5.2, 5.3, 5.4, 5.5] 第三次合併後的驗收（主對話）：
  - 依 design Implementation Contract 的「完成後的狀態」與「驗收」重新執行：`swift package clean` 後的建置與完整測試、iOS 模擬器建置、`spectra coverage`、各項 grep。
  - 反向檢查 1 到 23 全部重跑：1 到 18 的改壞方式配合 5.5 的新結構調整，19 到 23 是第 5 組新增的。
  - 以 Keychain 的金鑰重跑實際 API 測試（`LKGeminiClientLiveTests`），因為 5.5 改了 mapper 的結構。
  - 每一項的結果記錄在本任務下方。

  驗證：每一項都符合 Implementation Contract 的描述；測試數與 design 的估計相同，不同時記錄實際數字與原因。

  驗收結果（2026-11-22，主對話，功能分支 `3d6123f`；之後 `Sources/`、`Tests/` 與 `Package.swift` 沒有改變）：

  **建置與測試**：`swift package clean` 後，`swift build`、`swift build --build-tests` 與完整 `swift test` 都成功、零警告。XcodeBuildMCP 清除後對 iOS 模擬器（iPhone 17）建置 `LKAIKit` scheme 成功、零警告，log 確認 `Sources/LKAIGemini/` 的 6 個檔案都有編譯。

  **測試數**（都與估計值相同）：`LKAITestSupportTests` 6 → 7；`LKAIGemini` 19 → 20（含 2 個實際 API 測試，沒有設定環境變數時列為略過）；`LKAICore` 68、`LKAIKit` 4、`LKAIAnthropicTests` 45、`LKAIOpenAITests` 23、`LKAIKitCLITests` 7 不變。「known issues」4 個：2 個是原有的，2 個是 5.2 的測試以 `withKnownIssue` 預期記錄的問題。

  **實際 API 測試**：以 Keychain 的金鑰重跑 `LKGeminiClientLiveTests`（`gemini-3.5-flash-lite`），串流與非串流都通過；在同一個 shell 以 `grep -F` 比對，輸出沒有出現金鑰。

  **spec 覆蓋與完成後的狀態**：`spectra coverage 04-add-gemini-provider` 為 annotated 26、excluded 0、missing 0。4.2 列的 grep 條件仍然成立；`LKGeminiStreamState.swift` 內沒有 `"model_output"` 與 `"failed"`，兩個判斷只在 `LKGeminiStreamEvent.swift` 各寫一次。

  **二十三項反向檢查**（每項改壞一處、以 `swift test --no-parallel --filter 'LKAIGeminiTests|LKAIAPIKeyTests|LKAITestJSONTests'` 執行、再還原；做完 `git diff -- Sources` 沒有差異）。1 到 18 的結果與 4.2 相同，只有改壞的位置配合 5.5 的新結構調整：
  - 第 1 項改成「非 `model_output` 的 `step.start` 也加入集合」。
  - 第 2 項改成 guard 不看集合。
  - 第 10 項改成 `.failed` 不看 `firstError`。
  - 第 15、16 項改成解碼端的條件恆真。
  - 第 18 項把 guard 拆成「不在集合就略過、在集合而沒有文字才失敗」。

  第 5 組新增的 19 到 23：
  19. 沒有記錄過的 `index` 也當成回答交出（改壞時另外記下開始過的 `index`，只略過開始成非 `model_output` 的）：範例「stream with lifecycle events and a thought step」失敗（`index` 5 的 "Orphan"）。5.4 之前這個改法讓 19 個測試全部通過。
  20. `step.content` 的每個項目都要求字串 `text`：範例「text in the start of a model output step」失敗（`image` 項目）。`TextPart` 也用在 `delta`，所以只帶 `thought_signature` 的片段也失敗，lifecycle 範例與「Finish at the output token limit while still thinking」跟著失敗。
  21. `step.content` 格式不符時以 `try?` 略過：缺欄位表中 `content` 不是陣列、項目沒有 `type` 的兩列失敗；同一個寫法也略過了「content 項目缺 `text`」，那一列跟著失敗。
  22. `interaction.completed` 沒有 `model` 時改用 `interaction.created` 的模型（改壞時讓 `interaction.created` 帶出模型）：情境「Report no model when the completed interaction has none」失敗。
  23. `LKAITestJSON` 的 `#require` 不傳 `sourceLocation`：`LKAITestSupportTests` 的 `sourceLocation` 測試兩列都失敗。

## 6. 第二輪實作審查的修正

第二輪的四份審查（`/spectra-verify`、`/spectra-review`、fable、opus）都沒有必須修正的問題，上一輪的意見都已處理或已記錄。以下是主對話查證成立、使用者在 2026-11-22 決定處理的七項：

- design 的兩處（反向檢查調整清單多列了第 12 項、Implementation Contract 表格的 `jsonObject(from:)` 簽名沒有 `sourceLocation`）已在 ingest 時直接修正。
- 6.1 修正 5.2 測試的比對條件與排版，6.2 修正清單，6.3 驗收。
- `/spectra-verify` 的 Warning（供應商的錯誤訊息回顯金鑰）已記在清單第 7 章，本組不處理。
- 派工依 design「實作由 sonnet 在單一 worktree 依序進行」：6.1、6.2 由 sonnet 在 `.worktrees/sonnet` 依序做，完成後第四次合併回功能分支，6.3 由主對話做。

- [ ] 6.1 讓 `LKAITestJSONTests` 的 `sourceLocation` 測試只在 `#require` 記下的問題落在測試檔時通過（sonnet）：
  - `withKnownIssue` 的比對條件先以 `guard case .expectationFailed = issue.kind else { return false }` 限定問題的種類，再比對 `fileName`，比照 `LKAIMockHTTPClientTests` 限定問題種類的寫法。理由見 design 決策「與供應商無關的測試 helper 收進 LKAITestSupport」補上的 `sourceLocation` 一段。
  - 依 ios-dev-kit `formatting.md`「測試本體的 `// When`、`// Then` 之前空 1 行」，在同一個測試的 `// When` 與 `// Then` 之間補空行，說明兩段寫在同一個呼叫的註解保留。

  驗證：
  - 主對話在 6.1 之前先執行反向檢查 24（`jsonObject(from:)` 的 `Data` 版改成直接丟一般錯誤），觀察到這個測試照樣通過；6.1 之後同一個改法讓它失敗，記在 6.3。
  - 完整 `swift test` 通過且零警告，測試數不變。
- [ ] 6.2 更正並補充 `docs/adding-a-provider.md`，讓下一家供應商不會照著錯的前提做（sonnet）：
  - **第 7 章** 02「`makeURLRequest(for:)` 的網址檢查與 `encodeBody(for:)` 各寫一份」那一列：「三家的請求內容目前都沒有 dictionary 欄位（fable 確認）」改成 design Open Questions 更正後的句子（沒有以資料當鍵的 dictionary；Anthropic 的 `Fallbacks.encode(to:)` 會編碼鍵固定為 `model` 的 dictionary，評估時以 anthropic-provider 的 fallbacks 測試確認鍵沒有被改）。
  - **第 3 章參考實作**那一條：「檔名把 `Gemini` 換成供應商名」改成「檔案的角色與它對應」，並補上三點：
    - 請求內容的檔名是 `LK<供應商><API 名>RequestBody`，例如 `LKOpenAIResponsesRequestBody`、`LKAnthropicMessagesRequestBody`。
    - 第二種錯誤格式的檔案只在供應商有不只一種錯誤格式時才需要。
    - 供應商專屬的公開設定另開檔案，例如 `LKAnthropicRefusalFallback`。
  - **第 3 章「串流的共同流程」**：在「事件的巢狀欄位只在用得到時才解碼」那條之後加一條：解碼端依判別欄位做的判斷，把結果帶在事件裡，mapper 不再比對同一個字串，比照 `LKGeminiStreamEvent` 的 `stepStart(index:isModelOutput:texts:)` 與 `failed(firstError:)`。出處寫本 change 的決策「解碼端的判斷結果帶在事件裡，mapper 不再比對字串」。

  驗證：
  - 主對話審查內容：每一處都有 design 或程式碼的依據，提到的檔案與符號都存在。
  - `grep -n '第 6 章' docs/adding-a-provider.md` 仍只有第 2 章步驟 2 與第 7 章開頭兩處。
  - `grep -n -E '預定|由 04|fable 確認' docs/adding-a-provider.md` 沒有結果。
- [ ] 6.3 [after: 6.1, 6.2] 第四次合併後的驗收（主對話）：
  - 完整 `swift test` 通過且零警告，測試數與 5.6 相同。
  - 重跑反向檢查 23 與 24：兩者都要讓 `sourceLocation` 測試失敗。
  - 重跑 6.2 的兩個 grep。
  - `spectra coverage 04-add-gemini-provider` 沒有缺漏。
  - 結果記錄在本任務下方。第 6 組沒有改 `Sources/` 的產品程式碼與 mapper，所以不重跑 iOS 建置、實際 API 測試與反向檢查 1 到 22。

  驗證：每一項都符合上面的描述。
