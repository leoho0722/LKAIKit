派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1 到 7 組由 sonnet 在 `.worktrees/sonnet`（分支 `wt/cli-chat-sonnet`）依序實作，完成後合併回功能分支 `feat/add-cli-chat-command`。
- 8.1 由 owner 同意後在功能分支上執行；8.2 由主對話做。建置、測試、反向檢查、commit 與合併都由主對話執行。
- 第 9 組（實作審查後的修正）沿用同一個 worktree：9.1 到 9.5 由 sonnet 依序實作並合併回功能分支，9.6 由主對話做；之後送 fable 與 opus 複審修正的部分。複審的結論由 9.7（sonnet）與 9.8（主對話）處理，之後再複審一次。

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

## 9. 實作審查後的修正

來源：`/spectra-verify`、`/spectra-review`，以及 fable（t2c）、opus（t2g）的實作審查，主對話逐項查證後，使用者 2026-11-23 決定全部採用，修完再複審。

- [x] 9.1 [after: 8.2] 依 design「寫回答到 stdout 失敗時以退出碼 1 結束」，交付 cli-chat「Answer write failure」與 cli-output-language「Translated command text」中寫入失敗的訊息（sonnet）：
  - `LKAICommandOutput`：形狀照 Implementation Contract，`writeStandardOutput` 改成會丟出錯誤的 closure；收 `FileHandle` 的 init 讓 stdout 的錯誤往上丟，stderr 維持 `try?`；`///` 改寫成現況。
  - `LKAIChatRunner`：
    - 寫回答文字、stream 的片段與結尾的 LF 時接住錯誤，停止寫回答；stream 模式結束迭代，不再讀下一個事件，也不補 LF。
    - 在 stderr 一次寫入兩行：`Error: ` 加新訊息，以及 `Details: <domain> <code>`，domain 與 code 取自 `NSError`。
    - 不寫 `Warning:`，回傳 `.failed`。
  - 新訊息：`LKAICLIText` 加一個不帶參數的 `error.cli.*` case，String Catalog 加 en 與 zh-Hant；內容不含 `LKAI_`。
  - 「對話替身」support 檔的 `ChatRunRecorder` 加上設定：讓 stdout 的第 n 次寫入丟出指定的錯誤，預設不失敗；失敗的那次寫入也記在 timeline，測試才能確認嘗試寫入的內容與順序。
  - `LKAIChatRunnerTests` 新增：
    - 「Report a failed write of the answer」，以「failing writes」的兩列執行。
    - 「Stop reading the stream after a failed write」：timeline 只有一次讀取，失敗之後沒有任何 stdout 寫入。
    - 「Report a failed write instead of a warning」，兩種輸出方式都要測。
    - 輸出語言為 `zh-TW` 時，第一行是 `Error: ` 加 zh-Hant 的訊息。這一項沒有對應的 Scenario，所以不加標記。
  - 新增 `Tests/LKAIKitCLITests/LKAICommandOutputTests.swift`（實作審查 fable S1）：
    - 以兩條 `Pipe` 的寫入端建立 `LKAICommandOutput`，各寫入含非 ASCII 的文字，關閉寫入端後讀出，確認內容正確、沒有接反。寫入量要小於 pipe 的緩衝。
    - 以 `FileHandle(forReadingFrom:)` 開暫存資料夾內的檔案，當成 stdout 時 `writeStandardOutput` 丟出錯誤；當成 stderr 時 `writeStandardError` 不丟出錯誤。
    - 不可使用接收端已關閉的 pipe：寫入會觸發 SIGPIPE，終止整個測試行程（design Context）。
  - A 段的骨架：`writeStandardOutput` 先改成會丟出錯誤的型別，runner 的呼叫處暫時以 `try?` 忽略，行為和現在相同，讓新測試能編譯並在實作前失敗。B 段再依 spec 處理錯誤。
  - 驗證：
    - 主對話觀察到新的寫入失敗測試在實作前失敗。pipe 分流與 stderr 不丟出錯誤的測試是回歸防護。
    - `swift test --filter "LKAIChatRunnerTests|LKAICommandOutputTests|LKAICLITextTests"` 通過。
    - `swift build --build-tests` 零警告。
  - 完成紀錄（主對話，2026-11-23）：
    - 實作前失敗：新的寫入失敗測試四個函式、共 7 個案例都失敗。`LKAICommandOutputTests` 的三個測試是回歸防護；A 段骨架已讓 stdout 丟出錯誤，所以「唯讀檔案當成 stdout 會丟出錯誤」在實作前就通過。
    - 實作後：`LKAIKitCLITests` 82 個測試通過，建置零警告。
    - mutation check 三項都讓測試失敗，之後已還原：
      - 寫入失敗後繼續讀事件：讀取序號、嘗試寫入、stdout 與 Outcome 的斷言失敗。
      - 失敗後仍補 LF：invoke 與 stream 的嘗試寫入斷言失敗。
      - stdout 改回 `try?`：`writeStandardOutput_檔案是唯讀_丟出錯誤` 失敗。
    - 主對話補上 ios-dev-kit 要求的 `try?` 同行理由（`cf86fd4`）。
    - 串流先以 `LKAIError` 失敗、補 LF 時又寫入失敗：依 spec「Answer write failure」只回報寫入失敗，原本的服務錯誤不印出，退出碼都是 1。spec 與 design 沒有另外規定，維持現狀。
- [x] 9.2 [after: 9.1] 經 `execute` 的測試（回歸防護；實作審查的 `/spectra-verify` W1、fable W1）（sonnet）：
  - `LKAICommandTests` 的 `executeCommand` 增加可由呼叫端傳入的 `ChatRunRecorder`，預設建立新的一個。
  - 不給 `--max-output-tokens` 時，請求的 `maxOutputTokens` 是 4096，標 `cli-chat / Build the request from the options`。
  - 以 `--output-language zh-TW --apiKey sk-secret-123` 執行，替身的 `invoke(_:)` 丟出訊息含 `sk-secret-123` 的 `.invalidRequest`。斷言：
    - stderr 第一行是 `Error: ` 加 `errorDescription(localization: "zh-Hant")`。
    - 第二行含 `[REDACTED]`，整段不含 `sk-secret-123`。
    - `execute` 丟出 `ExitCode.failure`。
    - 標 `cli-chat / Redact the API key in the detail` 與 `cli-output-language / Translate an error from the AI service`。
  - 記錄器讓 stdout 寫入失敗時，`execute` 丟出 `ExitCode.failure`，標 `cli-chat / Report a failed write of the answer`。
  - 驗證：
    - `swift test --filter LKAICommandTests` 通過。
    - 主對話暫時做三種修改，各確認至少一個新測試會失敗，然後還原：`execute` 傳給 runner 的 `language:` 改成 `.enUS`；`apiKey:` 改成空字串的金鑰；`maxOutputTokens` 的預設值改成 4095。
  - 完成紀錄（主對話，2026-11-23）：
    - 三個新測試都是回歸防護，`LKAIKitCLITests` 87 個測試通過，建置零警告。
    - mutation check 四項都讓新測試失敗，之後已還原：
      - `language:` 改成 `.enUS`：zh-TW 與金鑰的測試失敗。
      - `apiKey:` 改成 `LKAIAPIKey("")`：同一個測試失敗。
      - 預設值改成 4095：4096 的測試失敗。
      - `execute` 的 `.failed` 改成 `return`（sonnet 建議）：寫入失敗的測試、既有的 `execute_對話結果_對應成退出碼`，以及 zh-TW 與金鑰的測試失敗。
- [x] 9.3 [after: 9.1] 翻譯的防護（回歸防護；實作審查 opus W1、fable S5）（sonnet）：
  - `LKAICLITextTests` 加參數化測試：每個 `LKAICLIText` case 在 `LKAIOutputLanguage.allCases` 查到的字串兩兩不同。
  - `LKAIOutputLanguageTests` 加參數化測試：每個 `LKAIError` case 的 `errorDescription(localization: language.localization)`，在 `LKAIOutputLanguage.allCases` 之間兩兩不同。
  - 驗證：
    - `swift test --filter "LKAICLITextTests|LKAIOutputLanguageTests"` 通過。
    - 主對話暫時把 `LKAIOutputLanguage.zhTW` 的 `localization` 改成 `"zh-TW"`，確認兩個新測試都失敗，然後還原。這模擬語言資料夾名稱不符時，查詢靜默退回英文的情況。
  - 完成紀錄（主對話，2026-11-23）：
    - 兩個新測試都是回歸防護，通過。
    - mutation check：`LKAIOutputLanguage.zhTW` 的 `localization` 改成 `"zh-TW"` 後，兩個新測試與既有的 `localization_各輸出語言_對應語言資料夾的名稱` 都失敗，之後已還原。
    - sonnet 推測：機器的語言是正體中文時，退回的查詢可能取得 zh-Hant 的字串，這個 mutation 就會漏掉。實測結果：這台機器的偏好語言是 `zh-Hant-TW`、`en-TW`，退回的查詢得到的仍是 en 的字串，所以新測試抓得到。
- [x] 9.4 [after: 9.1] 其他測試的補強與修正（回歸防護）（sonnet）：
  - 補 cli-chat「Keep partial streamed text on failure」新增的順序（實作審查 opus S3）：`LKAIChatRunnerTests` 的 `run_stream中途失敗_stdout保留已收到的文字並補LF` 與 `run_stream沒有結束事件就結束_當成失敗並寫出細節`，以 `recorder.timeline` 斷言補的 LF 寫在第一個 stderr 寫入之前。
  - 補兩個情境，都寫在 `LKAIChatRunnerTests`：
    - 「Keep a multi-line detail as received」（實作審查 opus S2）。
    - 「Write an answer that repeats the key unchanged」（實作審查 opus S7）。
  - `LKAICommandProcessTests`：
    - `lkai_違反輸入規則_錯誤訊息含指定的詞且退出碼為64` 加一個斷言：stderr 有一行以 `Usage: lkai ` 開頭（2026-11-23 實測的輸出是 `Usage: lkai --provider <provider> ...`）。
    - 新增測試：`["-v", "--provider", "bogus"]` 的退出碼是 64，stdout 為空。cli-root-command「Version output」的本文寫了這條規則，但沒有對應的 Scenario，所以只在 `///` 註明，不加標記（實作審查的 `/spectra-verify` S1、S2）。
  - `LKAIChatInputTests` 兩處相對路徑 `missing.txt`，改成暫存資料夾內一個不存在的絕對路徑，比照 `UnreadableFile.missing`（實作審查 opus S5）。
  - `LKAIChatProviderTests` 加斷言：每個 `apiKeyEnvironmentName` 都以 `LKAI_` 開頭、以 `_API_KEY` 結尾，和 `LKAICommandTestSupport` 移除金鑰的樣式相同（實作審查 fable S4）。
  - `LKAICommandLiveTests` 的 `makeChecks` 中，`hasSuffix("\n")` 改成 `utf8.last == UInt8(ascii: "\n")`（實作審查的 `/spectra-review`）。
  - 驗證：
    - `swift test --filter "LKAIChatRunnerTests|LKAICommandProcessTests|LKAIChatInputTests|LKAIChatProviderTests|LKAICommandLiveTests"` 通過，實際 API 測試顯示為略過。
    - 主對話暫時對調 `runStream(_:)` 中補 LF 與寫 stderr 的順序，確認順序的斷言會失敗，然後還原。
  - 完成紀錄（主對話，2026-11-23）：
    - 新增與修改的斷言都是回歸防護。`LKAIKitCLITests` 91 個測試通過，3 個實際 API 測試略過，建置零警告。
    - 順序斷言的寫法和任務描述不同：sonnet 改成「stdout 的寫入都排在第一個 stderr 寫入之前」。原因是兩個測試的第二列本來就不會補 LF（文字已經以 LF 結尾，或根本沒有文字）。補 LF 的那一列已涵蓋 spec 要求的順序。
    - mutation check 四項都讓新測試失敗，之後已還原：
      - 先寫 stderr 再補 LF：兩個串流失敗測試失敗。
      - 細節的 LF 換成空格：多行細節的測試失敗。
      - 回答也遮蔽金鑰：回答原樣寫出的測試失敗。
      - Gemini 的環境變數改成 `GEMINI_API_KEY`：名稱樣式的測試失敗。
    - 用法那一行，以及 `-v --provider bogus` 的退出碼，都由 swift-argument-parser 產生，沒有做 mutation check。
- [x] 9.5 [after: 9.1] 註解、說明文字與文件（sonnet）：
  - String Catalog 的 `cli.help.discussion` 中退出碼 1 的說明，en 與 zh-Hant 改成 design Implementation Contract「行為」寫的文字（實作審查 opus S6）。
  - `///` 的修改（實作審查 fable S2）：
    - `LKAICommand` 的 `outputLanguage` 屬性，以及 `extension LKAIOutputLanguage: ExpressibleByArgument {}`，各加一段：改名稱、parsing 策略或值的轉換時，要同步修改 `LKAIOutputLanguage.scanned(from:)`，並在 `scanned_可解析的引數_與解析出的輸出語言相同` 加一組引數。
    - `scanned(from:)` 的清單補上「自訂 `init?(argument:)`」，並把「加短名稱」改成「加任何其他名稱（短名稱或第二個長名稱）」。
    - `LKAIOutputLanguage.current` 寫明只給解析階段讀；解析之後，一律用解析出的 `outputLanguage`。
  - `LKAICommandTestSupport`（實作審查 opus S8、fable S6）：
    - `helpColumns` 的 `///` 改成點名 `--output-language` 那一行。2026-11-23 以 `COLUMNS=300` 實測，這一行是 244 字元，是最長的一行。
    - 檔頭「與之後的實際 API 測試共用」改成現況。
  - 用語：`LKAICommandProcessTests` 的 `lkai_要求版本_版本只印到標準輸出且退出碼為0`，`///` 的「加一個換行」改成「加一個 LF」。
  - `docs/adding-a-provider.md` 第 7 章加四列，出處都是 `add-cli-chat-command`，狀態都是「留給之後」：
    - `lkai` 要和 `LKAIKit_LKAICore.bundle`、`LKAIKit_LKAIKitCLI.bundle` 放在同一個資料夾。漏掉 Core 的 bundle 時，只在服務回報錯誤時中止（實測退出碼 133，`Error:` 印不出來）。發佈方式由做 release 的 change 決定，那個 change 的驗收要加上「複製到空資料夾後，`-v` 與一個服務錯誤的情境都正常」（實作審查 fable W2）。
    - `"Stream ended before a finish event"` 寫在三處：`LKAIChatClientProtocol`、`LKAIServerSentEventChatStreaming` 與 `LKAIChatRunner`。下次動到這句時，在 `LKAICore` 加一個 `package` 的工廠讓三處共用，比照 `unrecognizedStreamError(code:message:)`（實作審查 fable S3）。
    - 有思考的模型在思考期間會不會送資料，沒有查證。`--timeout` 遇到實例時記錄在這份文件。
    - 替身 client 在 `LKAICoreTests` 與 CLI 測試各有一份，出現第三份時收進 `LKAITestSupport`。
  - 驗證：
    - `swift build --build-tests` 零警告，`swift test --filter LKAIKitCLITests` 通過。
    - 內容審查確認 discussion 的兩種語言、`///` 與第 7 章的四列。
  - 完成紀錄（主對話，2026-11-23）：
    - 「加一個換行」改成 LF 的用語修正，和 9.4 一起 commit。
    - discussion 改寫之後，以 `COLUMNS=300` 重新實測：最長的一行仍是 `--output-language` 的 244 字元，`helpColumns` 的說明仍然正確。
- [x] 9.6 [after: 9.2, 9.3, 9.4, 9.5] 修正後的驗收（主對話），依 design「完成後的狀態」與「驗收」：
  - `swift package clean` 後的建置與完整測試零警告，記錄測試數。
  - iOS 模擬器建置 `LKAIKit` scheme。
  - 反向檢查，包括新的 `try?` 規則。
  - 以 Keychain 的金鑰重跑 `LKAICommandLiveTests`，輸出不含金鑰。
  - 手動以 Gemini 執行 `lkai --provider google -m gemini-3.5-flash-lite -p "Reply with the single word OK." >&-`，確認退出碼 1，stderr 是 `Error: ` 加寫入失敗的訊息，以及 `Details: NSCocoaErrorDomain 512`。
  - 驗證：每一項的結果記錄在本任務下方。
  - 執行紀錄（2026-11-23，主對話，功能分支在 b128161，三個 `LKAI_*_API_KEY` 都沒有設定）：
    - 建置：`swift package clean` 後，`swift build`、`swift build --build-tests` 與 `swift test` 都以退出碼 0 結束，三份紀錄都沒有 `warning:`。
    - 測試數：263 個測試、41 個 suite 全部通過，其中 `LKAIKitCLITests` 有 91 個。9 個實際 API 測試略過；4 個 known issue 是 `LKAITestSupportTests` 刻意驗證的預期失敗，和 8.2 相同。
    - iOS：以 XcodeBuildMCP 執行 `build_sim`，對象是 iPhone 17（iOS 26.5）的 `LKAIKit` scheme。結果 SUCCEEDED，沒有 warning，也沒有 error。
    - 反向檢查：和 8.2 的項目相同，全部符合，另外加上新的 `try?` 規則：
      - `Sources/LKAIKitCLI/` 內的 `try?` 只有 `LKAICommandOutput` 寫 stderr 的那一處，同一行有可忽略的理由。
      - `unredactedValue` 的位置和 8.2 相同。
      - `LKAICore` 的 `public` 沒有新增，也沒有刪除。
      - 改動的 Swift 檔中，沒有超過 100 字元的行（`spectra-scenario` 標記行除外）。
    - 實際 API 測試：以 Keychain 的金鑰執行 `swift test --filter LKAICommandLiveTests`，退出碼 0。三家 × invoke、`--stream` 共 6 個案例通過，實際產生 6 次請求。
    - stdout 關閉時：以 Gemini 執行 `lkai --provider google -m gemini-3.5-flash-lite -p "Reply with the single word OK." >&-`，加上與不加 `--stream` 各一次，共 2 次請求。兩次的退出碼都是 1，stderr 都是 `Error: Couldn't write the answer to standard output.` 與 `Details: NSCocoaErrorDomain 512`。
    - 金鑰：測試紀錄與手動執行的 stderr 都不含三把金鑰，已用 `grep -F` 逐把確認。
    - spec 情境：`spectra coverage` 回報 59 項都有測試標記，0 項排除，0 項缺少。另有 10 個標記指向主 spec cli-root-command 既有的情境，和 8.2 之後相同。

- [ ] 9.7 [after: 9.6] 實作複審後的修正（回歸防護；實作複審 fable W1、S1 到 S3，opus S1 到 S4）（sonnet）：
  - `LKAIChatRunnerTests` 加 cli-chat「Report a failed write of the trailing LF in a stream」的測試。
    - 以「stream endings」的兩列參數化，標 spectra-scenario。
    - 記錄器讓第 3 次 stdout 寫入失敗，也就是寫結尾 LF 的那一次。
    - 斷言：嘗試寫入的內容是 `Hel`、`lo`、LF；stderr 整段是寫入失敗的兩行；Outcome 是 `.failed`。
  - `///` 補上「寫回答到標準輸出失敗」：
    - `LKAIChatRunner.Outcome.failed` 的說明。
    - `LKAICommand.execute(environment:makeClient:output:)` 的 `- Throws:`。
    - `LKAICLIText` 型別說明中 key 的格式：`error.cli.*` 也用於寫入失敗。
    - `LKAIChatRunner.runStream(_:)` 補一個 Note：補 LF 時寫入失敗，優先於串流的錯誤，只回報寫入失敗。
  - `makeTemporaryDirectory()` 收進 `LKAICommandTestSupport`。`LKAIChatInputTests`、`LKAICommandProcessTests`、`LKAICommandOutputTests` 刪掉各自的副本，改用共用的。
  - `docs/adding-a-provider.md` 第 7 章 bundle 那一列補上：少帶 `LKAIKit_LKAIKitCLI.bundle` 時每次執行都中止，包括 `-v`（8.2 實測退出碼 133）。
  - 驗證：
    - `swift test --filter LKAIKitCLITests` 通過。
    - 主對話做兩項 mutation check，之後還原：
      - `runStream(_:)` 補 LF 的 `catch` 改成不處理、繼續往下：2026-11-23 實測時，現有測試全部通過，新測試要失敗。
      - 改成先印服務錯誤：新測試的第二列要失敗。
- [ ] 9.8 [after: 9.7] 複審修正後的驗收（主對話）：
  - `swift package clean` 後的建置與完整測試零警告，記錄測試數。
  - iOS 模擬器建置 `LKAIKit` scheme。
  - 反向檢查。
  - `spectra coverage` 回報 cli-chat 新情境有測試。
  - 以 `git diff 29c5540..HEAD -- Sources/` 確認 9.7 在 `Sources/` 只改了 `///`，所以不重跑實際 API 測試。
  - 之後送 fable 與 opus 複審 9.7。
  - 驗證：每一項的結果記錄在本任務下方。

不採用的建議（不建立任務）：
- fable S4 的兩點：`runLKAI` 改成只收要追加的環境變數；三個實際 API 測試函式合併。
- fable S6：「detail lines」表在兩個測試檔各有一份；`outputModes` 與「取第一行」的寫法重複。`makeTemporaryDirectory()` 在 9.1 之後已經有三份，改由 9.7 收進共用的 support 檔（實作複審 fable S3）。
- 理由：以上都沒有造成錯誤，再多一份時再整理。
- 用語：「空白與換行」共八處，其中的「換行」指一行結束，符合用語規則，維持原樣。
