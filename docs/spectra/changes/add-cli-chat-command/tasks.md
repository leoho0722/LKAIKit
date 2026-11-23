派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1 到 7 組由 sonnet 在 `.worktrees/sonnet`（分支 `wt/cli-chat-sonnet`）依序實作，完成後合併回功能分支 `feat/add-cli-chat-command`。
- 8.1 由 owner 同意後在功能分支上執行；8.2 由主對話做。建置、測試、反向檢查、commit 與合併都由主對話執行。

測試的做法：

- **新行為先寫測試**：先寫測試與能編譯的最小骨架，主對話觀察到新測試在實作前失敗，才實作。參數化測試以整個測試函式在實作前是否失敗為準，不要求每一列都失敗。
- **回歸防護**：任務中標「回歸防護」的測試，在實作前就會通過（現在的行為已經符合，或前一個任務已經做到），不列入「實作前失敗」的驗證，只確認實作後仍通過。
- **行為不變的修改**：以既有測試把關，名稱與期望值不變；例外只有 5.2 的 `USAGE: lkai` 比對方式。
- **spec 標記**：每個為 spec 情境寫的測試，上方加 `// spectra-scenario: <capability> / <情境>`，有範例時再加一行 ` / <範例>`，名稱照抄 spec。
- **字串的期望值**：不在測試裡寫死翻譯；以 `LKAICLIText`、`LKAIChatInputError.message(in:)` 或 `LKAILocalization` 查出期望值再比對，或只檢查 spec 指定的 token。
- **說明的寬度**：依 design「說明文字的測試固定寬度」，in-process 以 `helpMessage(columns:)`、`fullMessage(for:columns:)` 指定寬度，process 測試由 `runLKAI` 設定 `COLUMNS`。
- **兩個 support 檔**：4.1 的「對話替身」support 檔（替身 client、記錄輸出、記錄先後順序的事件來源）與 5.1 的「行程 helper」support 檔（`runLKAI` 等）是兩個不同的檔案。
- **用語**：換行字元寫 LF、CR、CRLF（第一次出現附 `\n`、`\r`），不寫「回車」；「換行」只指一行結束。
- **排版與說明**：依 ios-dev-kit；每行不超過 100 字元，以字元數計，`spectra-scenario` 標記行除外。新檔案先查 ios-dev-kit 的樣板選擇表，沒有對應樣板的依 design 引用的 add-swift-package-foundation「只有測試檔使用 ios-dev-kit 樣板」手寫。

## 1. LKAICore 指定語言的查詢

- [x] 1.1 依 design「指定語言查 String Catalog 的方法放在 LKAICore」，讓 `LKAICore` 能以指定的語言查 String Catalog，並讓 `LKAIError` 以指定的語言給出說明；公開 API 不變（sonnet）：
  - 新增 `Sources/LKAICore/LKAILocalization.swift`，`package enum LKAILocalization` 的 `string(forKey:in:localization:)`，形狀照 Implementation Contract。
  - `LKAIError` 新增 `package func errorDescription(localization:)`；公開的 `errorDescription` 不改。
  - `LKAIAPIKey` 只改 `///`：依 design「API 金鑰：--apiKey 優先，其次是供應商的環境變數」，把允許讀取 `unredactedValue` 的用途寫成組 HTTP 請求、把金鑰交給 client、遮蔽輸出中的金鑰，不點名使用的模組。
  - 新增 `Tests/LKAICoreTests/LKAILocalizationTests.swift`：以 `LKAICore` 的一個既有 key 驗證 `zh-Hant` 與 `en` 查到的字串和 `.lproj` 子 bundle 直接查到的相同，而且兩者不同；不存在的 localization 改用 bundle 預設的查詢；不存在的 key 回傳 key。
  - `LKAIErrorTests` 新增參數化測試：`errorKinds` 的每一種錯誤，在 `en` 與 `zh-Hant` 的 `errorDescription(localization:)` 都等於既有測試以 `.lproj` 查到的說明。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter "LKAILocalizationTests|LKAIErrorTests"` 通過；內容審查確認 `Sources/LKAICore/` 新增的宣告都是 `package` 層級。

## 2. CLI 的輸出語言與字串

- [x] 2.1 [after: 1.1] 依 design「CLI 的字串放在 LKAIKitCLI 自己的 String Catalog」與「輸出語言先掃描命令列，說明文字以 TaskLocal 取得」，建立 CLI 的語言與字串查詢，交付 cli-output-language「Output language option」的掃描規則與「Translated command text」的「Provide both translations for every CLI string」（sonnet）：
  - `Package.swift` 的 `LKAIKitCLI` 加上 `resources: [.process("Resources")]`；新增 `Sources/LKAIKitCLI/Resources/Localizable.xcstrings`，`en` 與 `zh-Hant`。
  - 新增 `LKAIOutputLanguage`（`scanned(from:)` 與 `@TaskLocal static var current`）與 `LKAICLIText`，形狀照 Implementation Contract；`LKAIOutputLanguage` 不 import ArgumentParser。`scanned(from:)` 的 `///` 寫明 design 列的要跟著修改的時機。
  - 這一步只放說明用的 key（`cli.help.*`）：簡介、discussion，以及十個選項各一則說明。discussion 以一個 `%@` 代入環境變數清單，並列出四個退出碼（design「退出碼：0 完成、1 服務錯誤、2 沒有正常完成、64 輸入錯誤」）；`--prompt` 的說明寫明以 `-` 開頭的內容改用 `--prompt=<text>` 或 `--prompt-file`（design「以 - 開頭的 prompt 維持解析器的行為，說明提示替代寫法」）；`--apiKey` 的說明寫明在 CI 中優先使用環境變數；`--timeout` 的說明寫明是多久沒有收到資料就放棄。選項名稱在兩種語言都照原樣寫，String Catalog 不寫供應商與環境變數的名稱。
  - 新增 `Tests/LKAIKitCLITests/LKAIOutputLanguageTests.swift`：`scanned(from:)` 涵蓋 spec「option positions」表的五種寫法、沒有給選項、不合法的值、前面不合法而最後合法、`--output-language` 是最後一個引數而沒有值、`zh-tw` 小寫、`--` 之後的選項不算，以及 `localization` 的對應。骨架的 `scanned(from:)` 回傳 `.zhTW`，預期 `.enUS` 的列才能在實作前失敗。
  - 新增 `Tests/LKAIKitCLITests/LKAICLITextTests.swift`：`LKAICLIText` 的每個 case 在 `en` 與 `zh-Hant` 都不為空、也不等於 key；帶 `%@` 的字串代入參數後含有該參數；String Catalog 的字串不含 `LKAI_`。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter "LKAIOutputLanguageTests|LKAICLITextTests"` 通過；主對話審查 String Catalog 的兩種文案。

## 3. 供應商與對話輸入

- [x] 3.1 [after: 2.1] 依 design「client 以預設設定與 ephemeral 的 URLSession 建立」，建立 `LKAIChatProvider`，交付 cli-chat「Chat request construction」的「Map the provider to its client」與「API key resolution」的環境變數表（sonnet）：
  - 形狀照 Implementation Contract；不 import ArgumentParser。
  - 新增 `Tests/LKAIKitCLITests/LKAIChatProviderTests.swift`：spec「provider values」表的 client 型別與 `description`，以及「environment variables」表。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter LKAIChatProviderTests` 通過。
- [x] 3.2 [after: 3.1] 依 design「API 金鑰：--apiKey 優先，其次是供應商的環境變數」「輸入檢查依 spec 的順序，只回報第一個錯誤」「--timeout 設定 URLSession 的閒置逾時，預設 60 秒」「prompt 只以一則使用者訊息送出，輸出語言不影響請求」「--max-output-tokens 預設 4096」，建立 `LKAIChatInput` 與 `LKAIChatInputError`，交付 cli-chat「Chat request construction」「Prompt sources」「API key resolution」「Network timeout」的設定部分，以及「Input validation failures」的檢查順序（sonnet）：
  - 形狀照 Implementation Contract；String Catalog 加上十一個 `error.cli.*` 的 key（`blankPrompt` 與 `blankPromptFile` 各一個），兩種語言的訊息都含 spec「validation rules in order」表中的 token。
  - 新增 `Tests/LKAIKitCLITests/LKAIChatInputTests.swift`：
    - 「Build the request from the options」「Send the prompt file content unchanged」（檔案以暫存資料夾建立）、「prompt file paths」表。
    - 「blank prompt sources」表的兩列，以 `LKAIChatInputError` 的 case 與 `message(in:)` 含有的 token 比對。
    - 「key sources for openai」表；「Read the environment variable of the selected provider」以三家參數化，environment 同時放三個變數、值各不相同，確認取到該供應商的值。
    - 「timeout values」表：`makeSessionConfiguration().timeoutIntervalForRequest` 等於表中的值；骨架回傳不是 60 的值，`none` 列才能在實作前失敗。
    - 「validation rules in order」表的十列（以 `LKAIChatInputError` 的 case 比對），以及每個錯誤在兩種語言的 `message(in:)` 含有表中的 token。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter LKAIChatInputTests` 通過。

## 4. 對話的執行與輸出

- [x] 4.1 [after: 2.1, 3.2] 依 design「預設 invoke，--stream 才邊收邊寫」「同一個 package 的 @nonexhaustive enum 一律窮舉」與「命令列介面集中在 LKAICommand，對話流程拆成輸入、執行與輸出」的 `Outcome`，建立 `LKAICommandOutput` 與 `LKAIChatRunner` 的成功與截斷路徑，交付 cli-chat「Invoke output」「Stream output」的成功部分與「Incomplete answer reporting」（sonnet）：
  - 形狀照 Implementation Contract；String Catalog 加上兩個 `warning.cli.*` 的 key（`maxOutputTokens`、`contextWindowExceeded`）。
  - 失敗路徑在 4.2 之前的過渡行為：遇到錯誤時 runner 回傳 `Outcome.failed`，不寫 stderr，stream 也不補 LF；Error／Details 與補 LF 在 4.2 完成。
  - 新增「對話替身」support 檔（`Tests/LKAIKitCLITests/` 內，名稱由實作決定）：
    - 替身 client：以 `LKAIChatStream(_:)` 實作 `stream(_:)`，另外實作 `invoke(_:)`，能直接回傳指定的結果或丟出指定的 `LKAIError`。
    - 記錄 stdout 與 stderr 的 `LKAICommandOutput`。
    - 記錄「讀取下一個事件」與「寫入」先後順序的事件來源，以 `AsyncThrowingStream(unfolding:)` 建立。
  - 新增 `Tests/LKAIKitCLITests/LKAIChatRunnerTests.swift`：
    - invoke 的「trailing line terminator」表四列，與 stream 的「streamed line terminators」表五列；`none` 列一併斷言 `Outcome.completed` 與 stderr 為空。
    - 「Write deltas as they arrive」：寫入發生在讀取第二個事件之前。
    - 「finish reasons」表在兩種輸出方式下的 stdout、stderr 與 `Outcome.incomplete`。
    - cli-output-language「Translate an incomplete answer warning」。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter LKAIChatRunnerTests` 通過；內容審查確認 `LKAIChatRunner.swift` 與 `LKAICommandOutput.swift` 沒有 `import ArgumentParser`、`LKAICommandOutput` 沒有 `static` 成員。
  - 完成紀錄（主對話）：「對話替身」依 ios-dev-kit「一個檔案一個頂層型別」拆成 `MockChatClient.swift` 與 `ChatRunRecorder.swift` 兩個檔案；兩則警告的 key 為了讓測試能查期望值，在 A 段就加入。
- [x] 4.2 [after: 4.1] 依 design「錯誤印通用說明加上 Details 行，細節中的金鑰換成 [REDACTED]」與「預設 invoke，--stream 才邊收邊寫」中「沒有結束事件就結束」的規則，完成 `LKAIChatRunner` 的失敗路徑與 `LKAIError` 的細節，交付 cli-chat「Service failure reporting」「Stream output」的「Report a stream that ends without a finish event」、「Network timeout」的「Report a timeout」，以及 cli-output-language「Translate an error from the AI service」（sonnet）：
  - 新增 `Sources/LKAIKitCLI/LKAIError+Details.swift`，`details` 照 spec「detail lines」表，`switch` 窮舉、不寫 `@unknown default`。
  - 測試（以替身的 `invoke(_:)` 丟出指定的錯誤）：「detail lines」表的每一列，包括 `cancelled`——stderr 第一行是 `Error: ` 加上 `errorDescription(localization: "en")`、第二行或沒有第二行、`Outcome.failed`、stdout 為空、不印用法；「Redact the API key in the detail」；「Report a timeout」；`zh-TW` 時第一行使用 `zh-Hant` 的說明。
  - 測試（stream）：「Keep partial streamed text on failure」（斷言 stdout 結尾的 LF）、「Fail a stream before any text」（同時斷言 stderr 第一行以 `Error: ` 開頭）、「Report a stream that ends without a finish event」。
  - 驗證：主對話觀察到新測試在實作前失敗；`swift test --filter "LKAIChatRunnerTests|LKAIErrorDetailsTests"` 通過（細節的測試型別名稱由實作決定，回報時寫明）。

## 5. 根指令

- [x] 5.1 依 design「process 測試清掉 LKAI_*_API_KEY」，先做行為不變的搬移與拆分：把 `runLKAI`、`CommandOutput`、`BundleLocator` 從 `LKAICommandTests` 搬到 `Tests/LKAIKitCLITests/` 的「行程 helper」support 檔，`runLKAI(arguments:environment:)` 預設移除 `LKAI_*_API_KEY` 並設定 `COLUMNS`；既有測試拆成 `LKAICommandTests`（in-process）與 `LKAICommandProcessTests`（process）兩個型別，測試名稱、期望值與數量不變（sonnet）。驗證：`swift test --filter "LKAICommand(Process)?Tests"` 通過，測試數與搬移前相同；內容審查確認既有測試的斷言沒有改變。
- [x] 5.2 [after: 2.1, 3.1, 5.1] 依 design「自訂 -v/--version 旗標取代內建的版本旗標」「輸出語言先掃描命令列，說明文字以 TaskLocal 取得」「說明輸出改以開頭比對用法那一行」「說明文字的測試固定寬度」，改寫 `LKAICommand` 的命令列介面，交付 cli-root-command「Version output」、cli-output-language「Output language option」「Parser-generated text stays in English」與「Translated command text」的說明部分，以及 cli-chat「Prompt sources」的「Name the alternatives in the prompt help」與「API key resolution」的「List every environment variable in the help」（sonnet）：
  - 照 Implementation Contract 宣告全部選項（`--prompt-file` 的 `valueName: "path"`）、自訂兩行的 `usage`、自訂 `main()`、`-v`/`--version`，拿掉 `version:`；`ExpressibleByArgument` 的兩個空 extension 寫在這個檔案。這一步的 `run()` 對任何輸入都丟出 `CleanExit.helpRequest(self)`，和現在相同；對話流程在 5.3 接上。
  - 既有測試：三處「有一行剛好是 `USAGE: lkai`」改成「有一行以 `USAGE: lkai `（含結尾空格）開頭」，三個對應的 `///` 一起更新；其他期望值不變。
  - 新增測試（實作前失敗）：
    - 「Request the version with the short flag」「Request the version together with chat options」。
    - 「option positions」表的五種寫法（process）。
    - 「Reject an unsupported language」的兩列：第一行含 `ja-JP`，`Help:` 行含 `en` 的 `--output-language` 說明。
    - 「Keep the help headings in English」：以 `USAGE: lkai ` 開頭的行、`OPTIONS:`，以及 `zh-Hant` 的簡介。
    - 「Keep a parse error in English」：現在的 `lkai` 會先拒絕 `--output-language`，第一行不是 `--bogus`。
    - in-process 以 `LKAIOutputLanguage.$current.withValue(_:)` 與 `helpMessage(columns:)` 產生兩種語言的說明：`zh-Hant` 的說明含 `zh-Hant` 的簡介與 `--provider` 的說明；兩種語言的說明都含每個 `LKAIChatProvider.allCases` 的 `apiKeyEnvironmentName`（「List every environment variable in the help」），`--prompt` 的說明都含 `--prompt=` 與 `--prompt-file`（「Name the alternatives in the prompt help」）。
  - 新增測試（回歸防護）：參數化測試，每一組能解析成功、不含 `-h` 與 `-v` 的引數，`LKAIOutputLanguage.scanned(from:)` 等於 `parseAsRoot(_:)` 解析出的 `outputLanguage`（掃描在 2.1 已完成）。
  - 新增測試（不列入實作前失敗）：「Use English by default even on a Chinese system」以 `lkai -h` 執行；實作前是否失敗取決於 `en` 簡介的文案是否和現在相同。`///` 寫明只有系統偏好語言以 `zh-Hant` 開頭時才驗得到前提，測試讀 `Locale.preferredLanguages` 並以 `Comment` 記錄前提是否成立。
  - 驗證：主對話觀察到「實作前失敗」的新測試在實作前失敗，既有測試只有 `USAGE: lkai` 的比對方式改變；`swift test --filter "LKAICommand(Process)?Tests"` 通過。
  - 完成紀錄（主對話）：「Keep a parse error in English」改標成回歸防護——骨架要宣告 `--output-language` 才能讓一致性測試編譯，宣告之後 `--bogus` 的錯誤在骨架上就是英文的 `Unknown option`。實作前失敗的 9 個函式都觀察到失敗（25 項）。
- [x] 5.3 [after: 3.2, 4.2, 5.2] 依 design「命令列介面集中在 LKAICommand，對話流程拆成輸入、執行與輸出」「必填檢查放在 run()，未定義的輸入仍先被拒絕」「沒有對話選項時印說明」「退出碼：0 完成、1 服務錯誤、2 沒有正常完成、64 輸入錯誤」，把對話流程接上 `LKAICommand.run()`，交付 cli-chat「Help when no chat option is given」「Input validation failures」「Prompt sources」的以 `-` 開頭的情境與「Network timeout」的行程層級行為，以及 cli-output-language「Translate a validation failure」「Answer language unaffected」（sonnet）：
  - 照 Implementation Contract 實作 `execute(environment:makeClient:output:)`，`run()` 只傳入真正的環境變數、建立 client 的方法與寫到 `FileHandle` 的輸出；`run()` 的 `URLSession(` 那一行呼叫 `makeSessionConfiguration()`。
  - 測試（process，實作前失敗）：「validation rules in order」表的十列（stderr 第一行以 `Error: ` 開頭並含 token、stdout 為空、退出碼 64）、「Keep the key out of error output」（第一行含 `--max-output-tokens`、退出碼 64、輸出不含金鑰）、「Translate a validation failure」（第一行等於 `Error: ` 加上 `LKAIChatInputError.missingProvider.message(in: .zhTW)`）。
  - 測試（process，回歸防護）：「Only a non-chat option is given」、「Reject a value the parser does not accept」、「dash-prefixed prompt text」表中被拒絕的 `-p "- item"` 與 `-p "--- a/file"` 兩列，以及既有的 `--bogus`、`foo` 仍是原本的第一行。
  - 測試（in-process，以 `parseAsRoot(_:)` 解析後呼叫 `execute`，注入替身，實作前失敗）：
    - 「Map the provider to its client」三列，由 `makeClient` 收到的 `LKAIChatInput` 確認供應商與金鑰。
    - 「timeout values」表，由 `makeClient` 收到的 `LKAIChatInput.makeSessionConfiguration()` 確認。
    - 「dash-prefixed prompt text」表中被接受的三列（`-p -`、`--prompt=- item`、`--prompt=--- a/file`）：替身收到的請求的訊息文字等於表中的值。
    - 「Send the same request in both languages」：比較替身收到的請求。
    - 成功、截斷與服務錯誤各一例，確認丟出的 `ExitCode` 為 0（不丟出）、2、1。
  - 驗證：主對話觀察到「實作前失敗」的新測試在實作前失敗；完整的 `swift test` 通過；`grep` 確認 `.ephemeral` 在 `Sources/LKAIKitCLI/` 只出現在 `makeSessionConfiguration()`。

## 6. 實際 API 測試

- [x] 6.1 [after: 5.3] 依 design「實際 API 測試以三家 × 兩種輸出方式執行，由 owner 手動跑」，新增 `Tests/LKAIKitCLITests/LKAICommandLiveTests.swift`：以 5.1 的「行程 helper」support 檔中的 `runLKAI` 執行 `lkai`，三家各以 invoke 與 `--stream` 送出一次，只在對應的環境變數有設定時執行（沒有設定時顯示為略過），金鑰只經環境變數傳入（sonnet）。驗證：沒有設定環境變數時 `swift test --filter LKAICommandLiveTests` 顯示六個略過；內容審查確認金鑰不在命令列參數、斷言訊息與輸出中。實際執行在 8.1。
  - 完成紀錄（主對話）：Swift Testing 的 `.enabled(if:)` 只能套在整個測試函式，所以實作為三家各一個函式、各以兩種輸出方式參數化；沒有設定環境變數時顯示三個函式略過（共六個案例），已在沒有 `LKAI_*_API_KEY` 的環境確認。

## 7. 文件

- [x] 7.1 [after: 5.3] 依 design「新增供應商時 CLI 要跟著加 --provider 的值」與「同一個 package 的 @nonexhaustive enum 一律窮舉」，更新 `docs/adding-a-provider.md`（sonnet）：
  - 第 3 章「架構與命名」的「新增供應商要動的既有檔案」加上 CLI 的部分。
  - 第 3 章「共用型別與 API 演進」加一句：`LKAICore` 的 `LKAIError`、`LKAIFinishReason` 增減 case 時，CLI 會因窮舉而編譯失敗，同時要更新 cli-chat spec 的「detail lines」與「finish reasons」兩張表。
  - 第 7 章「錯誤訊息回顯金鑰」一列補上 `lkai` 的處理方式。
  - 驗證：主對話審查內容，確認列出的檔案與型別名稱和實作相同。

## 8. 驗收

- [x] 8.1 [after: 6.1, 7.1] owner 同意後，主對話以 Keychain 的金鑰執行實際 API 測試：以 `security find-generic-password -s <service> -w` 分別從 `lkai-anthropic-api-key`、`lkai-openai-api-key`、`lkai-gemini-api-key` 取得 `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`，執行 `swift test --filter LKAICommandLiveTests`，在功能分支上、第 1 到 7 組都合併之後執行。另外依 design「實際 API 測試以三家 × 兩種輸出方式執行，由 owner 手動跑」，以任一家加上 `--timeout 1` 手動執行 `lkai` 一次並記錄結果。驗證：六個測試通過，輸出不含金鑰；兩者的結果與用量記錄在本任務下方。
  - 執行紀錄（2026-11-23，主對話，功能分支合併到 6918a64 之後；owner 先前指示金鑰在 Keychain 時由主對話直接執行）：
    - `swift test --filter LKAICommandLiveTests`：Gemini 的兩個案例（invoke、`--stream`）通過；Anthropic 與 OpenAI 的四個案例失敗，`lkai` 以退出碼 1 結束，stderr 為 `Error: The API key is invalid.`。輸出與測試紀錄都不含三把金鑰（`grep -F` 計數皆為 0）。
    - 判斷：以同樣的金鑰執行 library 的 `LKAnthropicClientLiveTests` 與 `LKOpenAIClientLiveTests`，四個測試都以 `.invalidAPIKey` 失敗，所以是 Keychain 中 `lkai-anthropic-api-key` 與 `lkai-openai-api-key` 的金鑰已被供應商拒絕（長度 106、164 字元，不是 128 字元截斷），不是 CLI 的問題；CLI 在金鑰無效時的行為符合 cli-chat「Service failure reporting」。
    - `--timeout`：以 Gemini 手動執行 `lkai --provider google -m gemini-3.5-flash-lite -p "Reply with the single word OK." --timeout 1`，退出碼 1，stderr 為 `Error: Couldn't connect to the service. Check your network connection.` 與 `Details: URLError -1001`，證明 `--timeout` 有接到連線上；同一指令改成 `--timeout 60` 時 stdout 為 `OK`、退出碼 0。
    - 用量：`lkai` 不輸出 token 用量；這次實際產生 token 的請求是 Gemini 的 3 次（兩個測試案例與 `--timeout 60` 那一次），Anthropic 與 OpenAI 的請求都在驗證金鑰時被拒絕。
    - 重跑紀錄（2026-11-23，owner 更新 `lkai-anthropic-api-key` 與 `lkai-openai-api-key` 之後，功能分支在 58dcc1b）：`swift test --filter LKAICommandLiveTests` 退出碼 0，三個測試函式、六個案例（三家 × invoke、`--stream`）全部通過，最慢的 OpenAI 在 3.6 秒內完成。輸出不含三把金鑰（`grep -F` 逐把確認）。這次實際產生 token 的請求是三家各 2 次，共 6 次。
- [x] 8.2 [after: 7.1, 8.1] 合併後的整體驗收（主對話）：依 design Implementation Contract 的「完成後的狀態」與「驗收」逐項執行，包括零警告的乾淨建置與完整測試、iOS 模擬器建置 `LKAIKit` scheme、反向檢查、`lkai -h`、`lkai --output-language zh-TW -h`、`lkai -v` 的實際輸出，以及把 `lkai` 單獨複製到 scratchpad 的暫存資料夾執行 `-v` 的結果。驗證：每一項的結果記錄在本任務下方。
  - 執行紀錄（2026-11-23，主對話，功能分支在 58dcc1b 加上 8.1 的紀錄；三個 `LKAI_*_API_KEY` 都沒有設定）：
    - 建置：`swift package clean` 後，`swift build`、`swift build --build-tests` 與 `swift test` 都以退出碼 0 結束，三份紀錄都沒有 `warning:`。測試紀錄中含 `error:` 的行，都是參數化測試名稱中的參數標籤（例如 `(language:error:)`），不是編譯錯誤。
    - 測試數：247 個測試、40 個 suite，全部通過。其中 9 個實際 API 測試因為沒有環境變數而略過：library 6 個、`LKAICommandLiveTests` 3 個。`LKAITestSupportTests` 的 4 個 known issue 是以 `withKnownIssue` 刻意驗證的預期失敗，本分支沒有修改這個目錄。
    - iOS：以 XcodeBuildMCP 執行 `build_sim`，先查 session defaults：workspace 是 `.swiftpm/xcode/package.xcworkspace`，scheme 是 `LKAIKit`，模擬器是 iPhone 17（iOS 26.5）。結果是 SUCCEEDED，沒有 warning，也沒有 error。
    - 反向檢查（`Sources/`，排除 `///` 行）：
      - `LKAICommand.swift` 沒有 `version:`。
      - `Sources/LKAIKitCLI/` 沒有 `print(`、`@unknown default` 與 `HTTP status`。
      - `ProcessInfo.processInfo.environment`、`URLSession(` 與 `LKAICommandOutput(` 各出現一次，都在 `LKAICommand.run()`。`LKAICommandOutput(` 的 `standardOutput:` 引數換到下一行，所以以呼叫的開頭比對。`URLSession(` 那一行含有 `makeSessionConfiguration()`。
      - `URLSessionConfiguration` 與 `.ephemeral` 只在 `LKAIChatInput.makeSessionConfiguration()` 出現，`.ephemeral` 只出現一次。
      - 只有 `LKAICommand.swift` 有 `import ArgumentParser`。
      - `LKAICommandOutput.swift` 沒有 `static`。
      - `unredactedValue` 只出現在 `LKAIAPIKey.swift`、三家的 `makeURLRequest(for:)` 內，以及 `LKAICommand.run()` 與 `LKAIChatRunner` 的遮蔽各一處。
      - `git diff main...HEAD -- Sources/LKAICore` 新增的宣告只有三個 `package` 宣告：`LKAILocalization`、`string(forKey:in:localization:)` 與 `errorDescription(localization:)`。`public` 沒有新增，也沒有刪除。
      - `Package.swift` 中 `LKAIKitCLI` 的依賴仍只有 `LKAIKit` 與 `ArgumentParser`。
      - String Catalog 中 `LKAI_` 出現 0 次。
    - 手動確認：以 `.build/debug/lkai`、`COLUMNS=80` 執行，三個指令的退出碼都是 0。
    - `lkai -h`：

      ```text
      OVERVIEW: Send a prompt to an AI service and print the answer, for CI/CD
      workflows.

      Sends the prompt to an AI service as one request and prints the answer to
      standard output. Errors and warnings go to standard error.

      Without --apiKey, the API key is read from the environment variable of the
      selected provider, one of: LKAI_ANTHROPIC_API_KEY, LKAI_OPENAI_API_KEY,
      LKAI_GEMINI_API_KEY

      Exit codes:
      0: The answer is complete.
      1: The AI service returned an error, the request timed out, or the stream
      stopped before it finished.
      2: The answer did not finish normally, for example because it reached
      --max-output-tokens. The answer is still printed.
      64: The input is invalid.

      USAGE: lkai --provider <provider> --model <model> (--prompt <prompt> | --prompt-file <path>) [<options>]
             lkai --version

      OPTIONS:
        --provider <provider>   The AI service to use. Required to send a prompt.
                                (values: anthropic, openai, google)
        -m, --model <model>     The name of the model to use, passed to the service
                                as given. Required to send a prompt.
        -p, --prompt <prompt>   The prompt text. Use either --prompt or
                                --prompt-file. If the text starts with -, write
                                --prompt=<text> or use --prompt-file instead.
        -f, --prompt-file <path>
                                The path of a .txt or .md file that holds the prompt,
                                read as UTF-8. Use either --prompt or --prompt-file.
        --apiKey <apiKey>       The API key. If not given, the environment variable
                                of the selected provider is used. In CI, prefer the
                                environment variable: command-line arguments stay in
                                the shell history and the process list.
        --max-output-tokens <max-output-tokens>
                                The maximum number of tokens in the answer. Models
                                that think before answering count their thinking
                                tokens too. (default: 4096)
        --timeout <timeout>     How many seconds to wait without receiving any data
                                from the AI service before giving up. The timer
                                restarts each time data arrives. (default: 60)
        --stream                Print the answer as it arrives instead of after it is
                                complete. If the call fails, part of the answer may
                                already be printed.
        --output-language <output-language>
                                The language of lkai's own messages: help text, input
                                errors and warnings. Text generated by the argument
                                parser stays in English. The language of the AI's
                                answer is not affected. (values: en-US, zh-TW;
                                default: en-US)
        -v, --version           Show the version number and exit.
        -h, --help              Show help information.

      ```

    - `lkai --output-language zh-TW -h`：

      ```text
      OVERVIEW: 將提示詞送給 AI 服務並印出回答，適合用在 CI/CD 流程。

      將提示詞作為一次請求送給 AI 服務，回答印到標準輸出，錯誤與警告印到標準錯誤。

      沒有給 --apiKey 時，從所選供應商的環境變數讀取 API 金鑰，可用的環境變數：LKAI_ANTHROPIC_API_KEY,
      LKAI_OPENAI_API_KEY, LKAI_GEMINI_API_KEY

      退出碼：
      0：回答完整。
      1：AI 服務回報錯誤、連線逾時，或串流在結束前停止。
      2：回答沒有正常完成，例如達到 --max-output-tokens；回答仍會印出。
      64：輸入有誤。

      USAGE: lkai --provider <provider> --model <model> (--prompt <prompt> | --prompt-file <path>) [<options>]
             lkai --version

      OPTIONS:
        --provider <provider>   要使用的 AI 服務。送出提示詞時必填。 (values: anthropic, openai,
                                google)
        -m, --model <model>     要使用的模型名稱，原樣交給 AI 服務。送出提示詞時必填。
        -p, --prompt <prompt>   提示詞的文字，與 --prompt-file 擇一使用。內容以 - 開頭時，請改寫成
                                --prompt=<text>，或改用 --prompt-file。
        -f, --prompt-file <path>
                                存放提示詞的 .txt 或 .md 檔案路徑，以 UTF-8 讀取，與 --prompt 擇一使用。
        --apiKey <apiKey>       API 金鑰。沒有給時，讀取所選供應商的環境變數。在 CI 中請優先使用環境變數，因為命令列引數會留在
                                shell 的歷史紀錄與程序清單中。
        --max-output-tokens <max-output-tokens>
                                回答最多可使用的 token 數。會先思考的模型，思考用的 token 也會計入。 (default:
                                4096)
        --timeout <timeout>     多久沒有收到 AI 服務的任何資料就放棄，單位為秒。每收到資料就重新計時。 (default: 60)
        --stream                邊收邊印出回答，不等回答完成。呼叫失敗時，可能已經印出部分回答。
        --output-language <output-language>
                                lkai 自己的訊息使用的語言，包含說明、輸入錯誤與警告；引數解析器產生的文字固定為英文。不影響 AI
                                回答的語言。 (values: en-US, zh-TW; default: en-US)
        -v, --version           顯示版本號碼並結束。
        -h, --help              Show help information.

      ```

    - `lkai -v`：

      ```text
      0.1.0
      ```

    - 發佈的基準：
      - 只把 `.build/debug/lkai` 複製到 scratchpad 的空資料夾，執行 `./lkai -v`，以退出碼 133（SIGTRAP）中止。stderr 是 `LKAIKitCLI/resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named LKAIKit_LKAIKitCLI`，和 design Context 的預期一致。
      - 把 `LKAIKit_LKAICore.bundle` 與 `LKAIKit_LKAIKitCLI.bundle` 一起複製後，`./lkai -v` 印出 `0.1.0`、退出碼 0。`./lkai --output-language zh-TW -h` 也以中文輸出，退出碼 0。
