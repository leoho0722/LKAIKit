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

- [ ] 1.1 依 design「金鑰遮蔽由 LKAICore 的 LKAIAPIKey 保證，三個遵循保留」，在 `LKAICore` 新增 `package struct LKAIAPIKey`，形狀照 Implementation Contract（sonnet）：
  - **先寫測試**：`Tests/LKAICoreTests/Networking/LKAIAPIKeyTests.swift` 以參數化測試檢查：
    - `String(describing:)`、`String(reflecting:)`、`dump(_:)` 的結果都不含原始值，而且前兩者等於 `LKAIAPIKey(redacted)`。
    - 一個不寫任何描述遵循、只有 `LKAIAPIKey` 欄位的測試用 struct，三種輸出也都不含原始值。這一列固定了討論時以 Swift 6.4.2 做的實測。
    - `unredactedValue` 等於建立時的值。這一列在骨架上就會通過，屬於回歸保護；測試的其他列在骨架上失敗。
    - 先以「描述回傳原始值」的骨架讓測試編譯。
  - **實作**：`Sources/LKAICore/Networking/LKAIAPIKey.swift`。

  驗證：
  - 主對話觀察到新測試在骨架上失敗，實作後通過。
  - 完整 `swift test` 通過且零警告，`LKAICore` 從 67 個變成 68 個。這是估計值，實際數字記在 4.2。
- [ ] 1.2 [after: 1.1] 依同一個決策，`LKAnthropicClient` 與 `LKOpenAIClient` 改以 `LKAIAPIKey` 保存金鑰，行為不變（sonnet）：
  - `private let apiKey` 的型別改成 `LKAIAPIKey`；公開與 `package` 的 `init(apiKey: String, …)` 不變，在 init 內包裝。
  - 只有 `makeURLRequest(for:)` 讀 `unredactedValue`。
  - 三個描述遵循的內容不變。

  驗證：
  - 兩家既有的金鑰遮蔽測試（anthropic-provider 與 openai-provider 的「Describe a configured client」）不改就通過。
  - 完整 `swift test` 通過且零警告，測試數不變。
  - `grep -rn 'unredactedValue' Sources | grep -v '///'` 只出現在 `LKAIAPIKey.swift` 與兩家的 `makeURLRequest(for:)`；`grep -rn 'let apiKey: String' Sources` 沒有結果。
- [ ] 1.3 依 design「與供應商無關的測試 helper 收進 LKAITestSupport」，把兩家測試裡與供應商無關的 helper 搬進 `LKAITestSupport`，兩家的測試改用它們，行為不變（sonnet）：
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

- [ ] 2.1 [after: 1.1, 1.3] 依 design「以 Interactions API v1 實作，串流與非串流都送 stream: true」「回應保存預設關閉，由 App 建立 client 時開啟」，建立 `LKAIGemini` 與 `LKGeminiClient`，交付 gemini-provider 的「Interactions API request」「Response storage setting」「API key secrecy」「Availability through LKAIKit」（sonnet）：
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
- [ ] 2.2 [after: 2.1] 依 design「文字只取 model_output 步驟的 text 片段，步驟類型依 step.start 的 index 記錄」「interaction.completed 依狀態對應結束原因，incomplete 回報 maxOutputTokens」「用量的輸出 token 加上思考 token」「實際回應的模型取自 interaction.completed」「事件的巢狀欄位只在用得到時才解碼，手寫的鍵用 camelCase」，交付 gemini-provider 的「Stream text mapping」「Finish mapping」（`failed` 六列除外，見 2.3）「Responding model」「Usage mapping」（sonnet）：
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
- [ ] 2.3 [after: 2.2] 依 design「HTTP 錯誤處理 Interactions 與 Google 通用兩種格式」「生成被擋下的代碼回報 refused，HTTP 與串流相同」「串流的 error 事件依 error.code 分類」，交付 gemini-provider 的「Error mapping」與「Finish mapping」的 `failed` 六列（sonnet）：
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
- [ ] 2.4 [after: 2.1] 依 design「實際 API 測試以 gemini-3.5-flash-lite 執行，由 owner 手動跑」，新增 `Tests/LKAIGeminiTests/LKGeminiClientLiveTests.swift`（sonnet）：
  - 串流與非串流各一個，比照 `LKOpenAIClientLiveTests`。
  - 只在設定 `LKAI_GEMINI_API_KEY` 時執行，模型 `gemini-3.5-flash-lite`，輸出上限 64。
  - 檢查以完成結束、文字不為空、回應的模型不是 nil 也不是空字串。

  驗證：沒有設定環境變數時，完整 `swift test` 把這兩個測試列為略過；主對話審查測試內容。實際執行見 4.1。

## 3. 文件

- [ ] 3.1 [after: 1.2, 2.3, 2.4, 4.1] 依 `config.yaml` 的指標與 `docs/adding-a-provider.md` 第 1 章「什麼時候更新」，把清單更新成 Gemini 實作後的狀態，逐列處理下面每一處（sonnet）：
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
- [ ] 3.2 [after: 3.1] 主對話依 design 的「完成後的狀態」與清單核對 `config.yaml` 的指標與 API 演進規則：確認不必修改，或修改並寫明原因。

  驗證：主對話的檢查結果記在本任務下方。

## 4. 驗收

- [ ] 4.1 [after: 2.3, 2.4] owner 以自己的金鑰執行實際 API 測試：`LKAI_GEMINI_API_KEY="$(security find-generic-password -s lkai-gemini-api-key -w)" swift test --filter LKGeminiClientLiveTests`，在功能分支上執行：2.1 到 2.4 都已合併回功能分支之後。排在整體驗收與清單更新之前，因為這是唯一以真實 API 檢查 mapper 的步驟；失敗而要改 mapper 時，整體驗收與清單的 Gemini 一欄都不必重做。

  驗證：串流與非串流兩個測試都通過，輸出沒有出現金鑰。
- [ ] 4.2 [after: 1.2, 2.3, 2.4, 3.2, 4.1] 合併後的整體驗收（主對話）：依 design Implementation Contract 的「完成後的狀態」與「驗收」逐項執行，含十八項反向檢查，並把每一項的結果，以及 4.1 的結果，記錄在本任務下方。

  驗證：
  - 每一項都符合 Implementation Contract 的描述。
  - 測試數與估計值比對，不同時記錄實際數字與原因。
  - `spectra coverage 04-add-gemini-provider` 顯示每個情境與範例都有測試。
