## Context

`lkai`（target `LKAIKitCLI`，根指令 `LKAICommand`）目前只有 swift-argument-parser 內建的 `--help` 與 `--version`，沒有 `run()`。三家供應商的 client 都已完成，App 端以 `any LKAIChatClientProtocol` 呼叫。這個 change 讓 `lkai` 在根指令上送出一次對話請求，給 CI/CD 使用。

**使用者在 2026-11-23 決定的事**（規劃時兩輪提問，規劃審查後一輪）：

- 執行檔沿用 `lkai`（需求寫的 `ikai` 是筆誤）。
- API 金鑰兩種來源都支援，旗標名稱用 `--apiKey`；沒給旗標時讀環境變數。
- 加一個旗標決定 stream 或 invoke：`--stream`，預設 invoke。
- `--output-language` 只影響 CLI 自己的訊息，不影響 AI 回答的語言。
- swift-argument-parser 產生的文字維持英文，不自己產生說明與解析錯誤。
- 新增 `--max-output-tokens` 並給預設值（4096）。
- 回答被截斷時照樣印出、stderr 警告、退出碼非 0。
- AI 服務的錯誤印通用說明加上技術細節。
- 規劃審查（fable、opus）之後：以 `-` 開頭的 prompt 維持解析器的行為，只在說明寫明替代寫法；新增 `--timeout` 選項；審查的其餘修正全部採用。

**查證方式**（2026-11-23，主對話）：

- 讀 `.build/checkouts/swift-argument-parser`（1.8.2）的原始碼，以及 `.build/out/Intermediates.noindex` 中實際建置用的 `resource_bundle_accessor.swift`。
- 在 scratchpad 建一個最小 package 實測，結構和本 repo 相同：library target 帶 `.xcstrings`、重新匯出它的總成 target、依賴總成與 ArgumentParser 1.8.2 的 executable target（也帶 `.xcstrings`），以及 `@testable import` 這個 executable 的測試 target。
- 在 scratchpad 跑一個會延遲回應的本機 HTTP 伺服器，以 `URLSession.bytes(for:)` 測逾時。
- 實測環境：macOS 27.2.1、Swift 6.4.2，系統偏好語言為 `zh-Hant-TW`、`en-TW`。package 的 deployment target 是 macOS 26。

**swift-argument-parser 1.8.2 的行為**：

| 項目 | 結果 |
| --- | --- |
| 內建版本旗標 | 名稱寫死為 `.long("version")`，說明寫死為 `Show the version.`（原始碼 `HelpGenerator.swift` 的 `versionArgumentDefinition()`、`CommandParser.swift` 的 `checkForBuiltInFlags`）。沒有像 `helpNames` 那樣的設定可以加上 `-v` |
| 自己宣告 `-v`/`--version` | `@Flag(name: [.short, .long]) var version` 並在 `validate()` 丟出 `CleanExit.message(版號)`：`-v`、`--version` 都只在 stdout 印出版號加一個 LF，退出碼 0；和 `--provider openai` 一起給時仍印版號（實測）。前提是其他選項都宣告為 Optional，否則缺少必填選項的錯誤會先出現 |
| `validate()` 的時機 | 在「未定義的輸入」檢查之前執行。必填檢查寫在 `validate()` 時，`--bogus` 與 `foo` 的錯誤變成「缺少 --provider」；寫在 `run()` 時，`--bogus` 仍是 `Error: Unknown option '--bogus'`、`foo` 仍是 `Error: Unexpected argument 'foo'`（實測） |
| `run()` 丟出 `ValidationError` | 和在 `validate()` 丟出相同：stderr 第一行 `Error: <訊息>`，接著印用法，退出碼 64（實測） |
| `run()` 丟出 `ExitCode(2)` | 不印任何訊息，以 2 結束；先寫到 stdout、stderr 的內容照樣保留（實測） |
| 說明文字在執行時決定 | 每次解析都以 `Mirror(reflecting: type.init())` 讀選項（原始碼 `ParsableArguments.swift`），`configuration` 與 `@Option(help:)` 的文字在這時求值。以 `@TaskLocal` 的值決定語言、在 `withValue` 的範圍內解析，說明就改用那個語言；同一行程裡沒有綁定時是預設語言（實測）。平行的測試互不影響，是依 TaskLocal 的語意推論的，沒有實測 |
| 說明文字的折行 | 依序取環境變數 `COLUMNS`、終端機回報的寬度、80 作為寬度，在半形空格處折行（原始碼 `Platform.swift`、`StringExtensions.swift`）；`COLUMNS=60` 時選項說明斷成多行（實測）。`helpMessage(columns:)` 與 `fullMessage(for:columns:)` 可以指定寬度（原始碼） |
| 框架自己的文字 | `OVERVIEW:`、`USAGE:`、`OPTIONS:`、`-h, --help` 的 `Show help information.`、`(default: …)`、`(values: …)`、`Error:` 前綴、解析錯誤（例如 `The value 'bogus' is invalid for '--provider <provider>'`）、`Help:` 前綴、`Usage:` 與 `See '… --help' for more information.` 都寫死英文；1.8.2 沒有本地化機制（原始碼與實測） |
| 解析錯誤後的 `Help:` 行 | 值不合法時，第二行是 `Help:  <選項>  <選項說明>`，選項說明就是我們宣告、會翻譯的文字；`--output-language zh-TW --provider bogus` 的 `Help:` 行是中文（實測） |
| 不合法的值與 `-h` | `--provider bogus` 與 `-h` 一起給時，不論順序都是解析錯誤、退出碼 64：值在 `LenientParser.parse()` 轉換時就丟錯，早於說明的檢查（實測三種順序） |
| 重複的選項 | 值都合法時取最後一個（實測）；任何一次的值不合法就以 64 失敗，即使最後一個合法（實測 `--provider bogus --provider openai`） |
| 以 `-` 開頭的值 | `-p "- item"`、`-p "-x"` 回 `Error: Missing value for '-p <prompt>'`；`-p "--- a/file"` 回 `Error: Invalid option: --- a/file`；`--prompt=- item` 與 `--prompt=--- a/file` 可用；只有一個 `-` 的 `-p -` 可用，值是 `-`（實測，`-p -` 與 `--prompt=--- a/file` 是第二輪規劃審查時補測的）。改成 `parsing: .unconditional` 時前兩者可用，`---` 開頭仍失敗，而且 `-p --stream` 會把 `--stream` 當成 prompt（實測）；使用者選擇不改 |
| 自訂 `usage` | 多行的 `usage` 原樣出現在說明的 `USAGE:` 與錯誤後的 `Usage:`（實測） |
| 值的名稱 | 預設取長名稱，例如 `--prompt-file <prompt-file>`、`--apiKey <apiKey>`（原始碼 `ArgumentDefinition.valueName` 與實測） |
| 未定義選項的建議 | 宣告和本 change 相同的選項名稱後，`--bogus` 仍只回 `Error: Unknown option '--bogus'`，沒有 `Did you mean`（實測），既有測試的逐字比對成立 |
| `--apiKey` | `.customLong("apiKey")` 可用；輸入 `--api-key` 時回 `Error: Unknown option '--api-key'. Did you mean '--apiKey'?`（實測） |
| 自訂 `main()` | 在 `@main` 的 `AsyncParsableCommand` 型別上宣告 `static func main() async`，先綁定 TaskLocal，再呼叫 `parseAsRoot(_:)`、`run()`，錯誤交給 `exit(withError:)`，行為與預設的 `main()` 相同（實測） |

**String Catalog 與資源 bundle**：

| 項目 | 結果 |
| --- | --- |
| `String(localized:bundle: .module)` | 一律回英文，系統偏好語言是 `zh-Hant-TW` 也一樣：`Bundle.main.preferredLocalizations` 是 `["en"]`，CLI 沒有自己的語言設定（實測）。這和 add-chat-abstraction-anthropic「錯誤說明以 String Catalog 提供英文與正體中文」記錄的「字串跟隨 App 本身支援的語言」一致 |
| `String(localized:bundle:locale:)` | `locale` 為 `zh-Hant`、`zh-TW`、`zh_Hant_TW` 時都回英文，`locale` 不決定查哪個語言（實測） |
| 取 `<語言>.lproj` 子 bundle 再查 | `Bundle(path: bundle.path(forResource: "zh-Hant", ofType: "lproj"))` 的 `localizedString(forKey:value:table:)` 回正體中文，`en` 回英文（實測） |
| executable target 的資源 | `resources: [.process("Resources")]` 會在執行檔旁產生 `<package>_<target>.bundle`，同樣可以用上一列的方式查字串（實測） |
| 測試行程讀 executable 的 bundle | 測試 target `@testable import` executable target 時，SwiftPM 把 executable 的 bundle 放進 `<測試>.xctest/Contents/Resources`，測試裡的 `Bundle.module` 讀得到（實測） |
| `package` 宣告穿過 `@_exported import` | executable target 只 import 總成 target，就能呼叫被重新匯出的 target 的 `package` 宣告（實測，規劃審查時重新建置確認） |
| 找不到資源 bundle | 實際建置的 `Bundle.module` 依序找 `Bundle.main.resourceURL`、`Bundle(for:)` 的 `resourceURL`、`Bundle.main.bundleURL`（DEBUG 另讀環境變數 `PACKAGE_RESOURCE_BUNDLE_PATH`），都沒有就 `fatalError`（讀 `.build/out/Intermediates.noindex` 中的 `resource_bundle_accessor.swift`）。沒有「建置當下的絕對路徑」這個後備：那只出現在索引用建置（`.build/index-build`）的版本，規劃時誤讀，規劃審查時更正 |

**URLSession 的逾時**（本機延遲伺服器，`URLSessionConfiguration.ephemeral`，`URLRequest(url:)` 不設定 `timeoutInterval`，與三家 client 相同）：

| 設定的 `timeoutIntervalForRequest` | 伺服器的行為 | 結果 |
| --- | --- | --- |
| 3 秒 | 回應標頭延遲 6 秒 | 3.0 秒時 `URLError` -1001 |
| 3 秒 | 標頭立即送出，內容延遲 6 秒 | 3.0 秒時 -1001 |
| 3 秒 | 每 2 秒送一段，共 8 秒 | 正常完成：收到資料就重新計時 |
| 100 秒 | 回應標頭延遲 70 秒 | 正常完成：`URLRequest` 預設的 60 秒沒有蓋掉設定 |
| 100 秒 | 兩段之間間隔 70 秒 | 正常完成 |

**Swift 的行為**（實測）：

- `"Hello\r\n".last == "\n"` 與 `hasSuffix("\n")` 都是 `false`，因為 CR LF 是一個 `Character`；`utf8.last == 10` 是 `true`。
- 同一個 package 的其他模組窮舉 `@nonexhaustive` 的 enum 時，寫或不寫 `@unknown default` 都沒有警告。既有的三個 live tests 窮舉 `LKAIChatStreamEvent`，也沒有寫 `@unknown default`。

**寫入 stdout 失敗時的行為**（2026-11-23 實作審查後實測，scratchpad 的 `write-probe`：Swift 程式以 `FileHandle.standardOutput.write(contentsOf:)` 寫入 1 MB，共四次）：

| stdout 接到的地方 | 結果 |
| --- | --- |
| 已關閉（`>&-`） | 每次都丟出 `NSCocoaErrorDomain` 512 |
| 2 MB 的 HFS+ 磁碟映像上的檔案，寫到滿 | 丟出 `NSCocoaErrorDomain` 640，丟出之前已寫入一部分 |
| 接收端已結束的 pipe（`\| (exec 0<&-; true)`） | 沒有丟出錯誤，行程被 SIGPIPE 終止，退出碼 141 |
| `/dev/null` | 正常 |

原本的 `LKAICommandOutput` 以 `try?` 寫入，前兩種情況會被忽略，回答沒有寫完，退出碼仍是 0（實作審查 opus S1）。

**相關的既有決策**（`spectra decisions`）：

- add-swift-package-foundation「CLI 以 swift-argument-parser 建立 lkai 根指令」：`LKAICommand` 採 `AsyncParsableCommand`，就是為了之後會呼叫網路 API。本 change 實作 `run()`，沿用這個協定。
- add-swift-package-foundation「以行程層級測試驗證 lkai 的輸出分流」：沿用。其中「stdout 有一行剛好是 `USAGE: lkai`」的比對方式要改，見決策「說明輸出改以開頭比對用法那一行」。
- add-chat-abstraction-anthropic「錯誤說明以 String Catalog 提供英文與正體中文」：公開的 `errorDescription` 照舊跟隨 App 的語言，不改；CLI 另用 `package` 層級、指定語言的查詢。
- add-chat-abstraction-anthropic「跨供應商組裝邏輯暫不提供」：library 仍不提供。依 `--provider` 選 client 的邏輯寫在 `LKAIKitCLI`，就像 App 自己建立 client，不必新增組裝 target，也不必修改 package-distribution 的「Module dependency direction」。
- add-chat-abstraction-anthropic 的 `LKAnthropicClient` 說明「逾時與連線設定由 App 決定」：在逾時這件事上，CLI 就是決定設定的使用端，以 `--timeout` 決定。這不表示 `config.yaml` 給 App 的其他規則都適用於 CLI，見決策「同一個 package 的 @nonexhaustive enum 一律窮舉」。
- 02-add-openai-provider「輸出上限照原樣送出，由 API 檢查最小值」：CLI 只檢查 `--max-output-tokens` 至少為 1，和共用的請求檢查相同；OpenAI 的最小值 16 仍由 API 檢查。
- add-swift-package-foundation 的 Non-Goals「CLI 子指令與任何實際的 CI/CD 工作流程」、02 的 Non-Goals「`lkai` 的子指令」：都是當時那個 change 的範圍限制。本 change 實作 CLI 的功能，但仍不新增子指令。
- add-swift-package-foundation「只有測試檔使用 ios-dev-kit 樣板」：沿用。新檔案先查 ios-dev-kit 的樣板選擇表，沒有對應樣板的依檔頭規則、`formatting.md` 與 `coding-style.md` 手寫。

## Goals / Non-Goals

**Goals:**

- `lkai --provider <p> -m <model> (-p <text> | -f <file>)` 送出一次對話，stdout 只有回答，CI 以退出碼判斷結果。
- 說明、CLI 自己的錯誤與警告、AI 服務的錯誤說明，都能以 `en-US` 或 `zh-TW` 輸出，而且不受系統語言影響。
- 既有 spec 的行為不變：不帶參數印說明、`--help`、`-h`、`--version`，以及未定義輸入的錯誤訊息。
- 長期維護：命令列解析、輸入檢查、對話執行與輸出各自獨立，不連網就能測試全部的分支；新增供應商時要改的程式集中在 `LKAIChatProvider` 一個型別。

**Non-Goals:**

- 子指令、系統指示的選項、多輪對話、從 stdin 讀 prompt。
- 讓 `-p` 接受以 `-` 開頭的內容（使用者 2026-11-23 選擇維持解析器的行為）。
- 在輸出中加上用量、結束原因或實際回答的模型；JSON 輸出。
- 自動重試；依 `LKAIError` 的種類給不同的退出碼。
- 翻譯 swift-argument-parser 產生的文字（使用者 2026-11-23 選擇維持英文）。
- `en-US`、`zh-TW` 以外的輸出語言。
- 改變公開的 `LKAIError.errorDescription` 或任何公開 API。
- 在 CLI 開放 Anthropic 的拒答備援、OpenAI 與 Gemini 的回應保存等 client 設定；整個請求的總時間上限。
- 發佈方式（release 執行檔、Homebrew）與處理 SIGINT、SIGPIPE。

## Decisions

### 命令列介面集中在 LKAICommand，對話流程拆成輸入、執行與輸出

- `LKAICommand` 只負責命令列：宣告選項、版本旗標、自訂 `main()`，在 `execute` 把選項交給下面的型別，並把結果對應成退出碼。
- `LKAIChatInput` 把選項與環境變數變成檢查過的輸入（供應商、金鑰、`LKAIChatRequest`、逾時）；檢查失敗時丟出 `LKAIChatInputError`。它不依賴 ArgumentParser。
- 只有 `LKAICommand.swift` import ArgumentParser：`LKAIChatProvider` 與 `LKAIOutputLanguage` 在宣告處只遵循 `String`、`CaseIterable`、`Sendable`，`ExpressibleByArgument` 以空的 extension 寫在 `LKAICommand.swift`。「完成後的狀態」因此能以一條 grep 檢查整個 target 的依賴範圍（規劃審查第二輪，fable）。
- `LKAIChatRunner` 拿 client 執行 invoke 或 stream，把回答、警告與錯誤寫到 `LKAICommandOutput`，回傳自己的結果 `Outcome`（`completed`、`incomplete`、`failed`）。它不依賴 ArgumentParser，四個退出碼只在 `LKAICommand` 決定，和列出退出碼的 discussion 在同一處。
- `LKAIChatProvider` 是 `--provider` 的值，負責「供應商 → client 與環境變數」的對應；新增供應商時程式只改這個型別，文件與測試見決策「新增供應商時 CLI 要跟著加 --provider 的值」。
- 理由：
  - 不連網就能測試每個分支：測試以 `LKAIChatStream(_:)` 建立替身 client，以記錄用的 `LKAICommandOutput` 檢查輸出。
  - 之後加子指令時，把選項搬到新的指令型別並設成 `defaultSubcommand`，原本的命令列寫法不變，`LKAIChatInput`、`LKAIChatRunner`、`LKAIChatProvider`、`LKAICommandOutput` 都不必修改。
- 考慮過的替代方案：
  - 全部寫在 `LKAICommand.run()`：測試只能透過行程執行，而每個情境都要連到真實的 API，否決。
  - `LKAIChatRunner` 直接回傳 ArgumentParser 的 `ExitCode`：耦合有限，但退出碼會分散在兩個檔案，規劃審查（fable）建議改成回傳自己的結果，採用。

### 自訂 -v/--version 旗標取代內建的版本旗標

- 拿掉 `CommandConfiguration` 的 `version:`，改宣告 `@Flag(name: [.short, .long]) var version`，在 `validate()` 為 `true` 時丟出 `CleanExit.message(LKAIKitInfo.version)`。
- 對話選項全部宣告為 Optional（`--max-output-tokens`、`--timeout`、`--stream`、`--output-language` 有預設值），`-v` 才不會被缺少必填選項的錯誤擋下。
- 理由：內建的版本旗標只有 `--version`，沒有設定可以加上 `-v`（Context）。
- 解析器不接受的值（例如 `-v --provider bogus`）仍是解析錯誤、退出碼 64，因為值的轉換早於 `validate()`（Context）；cli-root-command 的「Version output」寫明這一點。
- 未定義的選項或引數與版本旗標一起給時，印出版本、退出碼 0；`-h`、`--help` 與版本旗標一起給時，不論先後都印出說明。
  - 原因：`validate()` 早於「未定義的輸入」的檢查；說明旗標在 swift-argument-parser 處理 `CleanExit` 時先被檢查。
  - 2026-11-23 實測：`lkai -v --bogus`、`lkai -v foo`、`lkai --version --bogus` 都印出 `0.1.0`、退出碼 0；`lkai -v -h`、`lkai -h -v`、`lkai --version --help` 都印出說明、退出碼 0。
  - 在 `main` 上，內建的 `--version` 也是這樣：`--version --bogus`、`--version foo` 印出版本、退出碼 0，`--version -h` 印出說明。所以這不是這個 change 造成的改變。
  - 這和主 spec「Invalid input rejection」的退出碼 64 字面衝突。使用者 2026-11-23 選擇維持行為，在「Version output」寫明優先順序；cli-chat「Help when no chat option is given」也寫明讓位（封存前最終審查：opus S1、S2，fable S4）。
- 考慮過的替代方案：保留內建的 `--version`，另外宣告 `-v`。兩者都叫 `version`，說明裡會出現兩列，而且行為由兩處決定，否決。

### 必填檢查放在 run()，未定義的輸入仍先被拒絕

- `--provider`、`--model`、prompt、`--max-output-tokens`、`--timeout` 與金鑰的檢查都在 `run()` 之後的 `execute`，以 `ValidationError` 回報，退出碼仍是 64。
- 理由：`validate()` 比「未定義的輸入」檢查先執行（Context）。檢查放在那裡時，`lkai --bogus` 會回報「缺少 --provider」，違反 cli-root-command 的「Invalid input rejection」。
- 版本旗標的檢查留在 `validate()`：它要比所有對話檢查都先執行。

### 沒有對話選項時印說明

- `--provider`、`--model`、`--prompt`、`--prompt-file` 都沒給時，`execute` 丟出 `CleanExit.helpRequest(self)`，和 swift-argument-parser 預設的 `run()` 相同。
- 理由：保住 cli-root-command「Run the executable without arguments」，也讓 `lkai --output-language zh-TW` 印出中文說明。只看這四個選項，因為其他選項都有預設值，或者單獨出現沒有意義。

### 說明輸出改以開頭比對用法那一行

- 自訂 `usage`，固定兩行、不翻譯：

  ```
  lkai --provider <provider> --model <model> (--prompt <prompt> | --prompt-file <path>) [<options>]
  lkai --version
  ```

- `--prompt-file` 宣告 `valueName: "path"`，OPTIONS 與錯誤訊息中的寫法才會和自訂 usage 相同（值的名稱預設取長名稱，見 Context）。
- 加了選項之後，不論有沒有自訂 `usage`，用法那一行都不再剛好是 `USAGE: lkai`。既有測試的三處比對（不帶參數執行 `run()`、`--help`／`-h`、以行程執行的三種輸入）改成「有一行以 `USAGE: lkai `（含結尾空格）開頭」，三個寫著「剛好是 `USAGE: lkai`」的 `///` 一起更新。含結尾空格，現在內建說明的 `USAGE: lkai` 那一行就不會符合，新測試能在實作前失敗。spec 寫的是「stdout contains `USAGE: lkai`」，不必修改。
- 這修改了 add-swift-package-foundation「以行程層級測試驗證 lkai 的輸出分流」中的一項比對方式；行程層級測試的其他做法都沿用。
- 理由：自動產生的用法把每個選項都包在 `[...]` 裡，看不出 `--provider` 與 `--model` 是必填。

### 說明文字的測試固定寬度

- in-process 的測試以 `helpMessage(columns:)`、`fullMessage(for:columns:)` 產生說明與錯誤訊息，寬度固定為足以讓每則說明不折行的值。
- process 測試的 `runLKAI(arguments:environment:)` 預設在環境變數設定同一個 `COLUMNS`。
- 理由：說明依終端機寬度折行（Context），比對整段的簡介或選項說明時，結果會隨執行的終端機與 CI 改變。
- 字串本身不限制長度；寬度的值由實作決定，寫在測試的 support 檔，並在任務回報中寫明。

### 輸出語言先掃描命令列，說明文字以 TaskLocal 取得

- `LKAIOutputLanguage` 有 `@TaskLocal static var current`，預設 `.enUS`。
- 自訂的 `main()` 先以 `LKAIOutputLanguage.scanned(from:)` 掃描命令列，在 `$current.withValue(...)` 的範圍內解析、執行與結束，所以 `-h` 與解析階段的文字也用那個語言。
- 掃描規則和解析器一致（Context 的「重複的選項」）：
  - 支援 `--output-language <值>` 與 `--output-language=<值>`，只看 `--` 之前的引數。
  - 以 `LKAIOutputLanguage(rawValue:)` 判斷，大小寫要完全相同，所以 `zh-tw` 不合法。
  - 任何一次出現的值不合法，或 `--output-language` 是最後一個引數而沒有值時，回 `.enUS`；否則取最後一次出現的值。
- `scanned(from:)` 的 `///` 寫明要跟著修改的時機：為 `--output-language` 加短名稱、改變任一選項的 parsing 策略、加位置引數或子指令時。加子指令時，`--output-language` 要以 `@OptionGroup` 讓每個子指令都接受。
- `configuration` 的簡介與說明、每個 `@Option`/`@Flag` 的 `help` 都讀 `LKAIOutputLanguage.current`。
- `execute` 之後的訊息（輸入錯誤、警告、AI 服務的錯誤）改用解析出的 `outputLanguage` 選項。正常執行時兩者相同，5.2 以參數化測試確認（回歸防護，因為掃描在 2.1 已完成）：每一組能解析成功、而且不含 `-h` 與 `-v` 的引數，掃描的結果都等於解析出的值。
- 直接呼叫 `parseAsRoot(_:)` 的單元測試，檢查 `execute` 之後的訊息時不必綁定 TaskLocal；但 `execute` 丟出的 `CleanExit.helpRequest(self)`，在測試以 `fullMessage(for:columns:)` 產生說明時仍讀 TaskLocal，要檢查中文說明時須綁定。
- 考慮過的替代方案：
  - 全域變數：Swift 6 要標 `nonisolated(unsafe)`，平行執行的測試會互相影響，否決。
  - 自己產生說明與解析錯誤，讓全部文字都翻譯：使用者 2026-11-23 選擇維持英文，否決。

### 指定語言查 String Catalog 的方法放在 LKAICore

- `LKAICore` 新增 `package enum LKAILocalization`，以 `string(forKey:in:localization:)` 從 bundle 的 `<localization>.lproj` 查字串；沒有這個 `.lproj` 時改用 bundle 預設的查詢。
- `LKAIError` 新增 `package func errorDescription(localization:)`，以同一個 key 查 `LKAICore` 的 String Catalog。公開的 `errorDescription` 不變，照舊跟隨 App 的語言。
- CLI 自己的字串也用 `LKAILocalization` 查，傳入 `LKAIKitCLI` 的 bundle。
- 理由：
  - CLI 行程中預設的查詢一律是英文，`locale:` 也不決定語言，只有取 `.lproj` 子 bundle 查得到中文（Context）。
  - `LKAIError` 的字串在 `LKAICore` 的 bundle 裡，只有 `LKAICore` 讀得到它的 `Bundle.module`，所以指定語言的說明必須由 `LKAICore` 提供。
  - 查詢的寫法只有一份，CLI 與 `LKAIError` 共用；`LKAIErrorTests` 已經用同一種 `.lproj` 的查法驗證字串，這次把它變成正式的 `package` API。
- 這不是供應商的 change，也沒有修改共用的公開型別，符合 `config.yaml`「供應商的 change 不得為了自己的格式修改 LKAICore 的共用公開型別」。可觀察的行為沒有改變，所以不修改 chat-client spec。
- 考慮過的替代方案：
  - 把 `LKAIError` 的說明複製一份到 CLI 的 String Catalog：兩份文案會分歧，否決。
  - 在行程啟動時改寫語言設定（例如 `AppleLanguages`）：會影響整個行程的查詢，沒有採用，也沒有實測。

### CLI 的字串放在 LKAIKitCLI 自己的 String Catalog

- `Sources/LKAIKitCLI/Resources/Localizable.xcstrings`，提供 `en` 與 `zh-Hant`；`Package.swift` 為 `LKAIKitCLI` 加上 `resources: [.process("Resources")]`。
- key 以 `LKAICLIText`（`String` raw value、`CaseIterable`）列舉。說明的 key 為 `cli.help.<項目>`，輸入錯誤為 `error.cli.<case>`，警告為 `warning.cli.<case>`；錯誤的 key 依 ios-dev-kit 的 `error.<領域>.<case>` 規則，領域為 `cli`。
- 帶參數的字串（檔案路徑、環境變數名稱、環境變數清單）用 `%@`，查到後以 `String(format:)` 代入。
- discussion 的環境變數清單是一個 `%@`，由 `LKAIChatProvider.allCases` 的 `apiKeyEnvironmentName` 組成後代入；String Catalog 不寫任何供應商或環境變數的名稱，新增供應商時不必修改字串。
- 選項名稱在兩種語言中都照原樣寫，不翻譯。
- 理由：沿用 add-chat-abstraction-anthropic「錯誤說明以 String Catalog 提供英文與正體中文」的做法；`CaseIterable` 讓測試能檢查每個 key 在兩種語言都有值。
- 考慮過的替代方案：在 Swift 程式碼裡依語言 `switch` 寫死字串，就不需要資源 bundle。和既有的 String Catalog 做法不一致，而且 `LKAICore` 的 bundle 本來就需要，省不掉發佈時的 bundle，否決。

### API 金鑰：--apiKey 優先，其次是供應商的環境變數

- `--apiKey` 不是空字串時用它；否則讀 `LKAIChatProvider.apiKeyEnvironmentName`（`LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`）不是空字串的值；都沒有時是輸入錯誤，訊息同時寫出 `--apiKey` 與環境變數的名稱。
- 環境變數的名稱與三家的實際 API 測試相同，owner 不必為 CLI 另外設定。
- 旗標名稱照使用者指定的 `--apiKey`（以 `.customLong("apiKey")` 宣告），和其他 kebab-case 的選項不同；輸入 `--api-key` 時，swift-argument-parser 會提示正確的名稱（Context）。
- `--apiKey` 的說明寫明在 CI 中優先使用環境變數，因為命令列參數會留在 shell 的歷史紀錄與程序列表。
- 金鑰存成 `LKAIAPIKey`。CLI 只在兩處讀 `unredactedValue`：把金鑰交給 client、遮蔽錯誤細節中的金鑰。
- 金鑰的承諾只涵蓋 `lkai` 自己寫出的文字：說明、輸入錯誤的訊息、警告，以及服務錯誤與寫入失敗的 `Error:`、`Details:` 行。swift-argument-parser 的錯誤訊息會原樣重複無法解析的引數：2026-11-23 實測 `lkai --provider openai -m x -p hi sk-fake-key-for-test` 的 stderr 第一行是 `Error: Unexpected argument 'sk-fake-key-for-test'`、退出碼 64，所以金鑰被誤當成多餘的引數時會出現在那則訊息中（實作複審 opus S4）。AI 的回答原樣寫出、不遮蔽，所以 prompt 含金鑰、回答又照抄時，金鑰會出現在 stdout。原本的 spec 寫「任何情況都不把金鑰寫到 stdout 或 stderr」，比實作寬；使用者 2026-11-23 選擇修改 spec 的文字，實作不變（實作審查 opus S7）。遮蔽 stream 的回答要處理金鑰被切在兩個片段之間的情況，所以不做。
- `LKAIAPIKey` 的 `///` 改寫成允許讀取原始值的用途：組 HTTP 請求、把金鑰交給 client、遮蔽輸出中的金鑰。不點名 `lkai`：`LKAICore` 的說明不寫上層的使用者，實際的位置由「完成後的狀態」的反向檢查把關。

### 輸入檢查依 spec 的順序，只回報第一個錯誤

- 順序照 cli-chat「Input validation failures」的表：供應商、模型、prompt 選項、檔案副檔名、讀檔、空白的 prompt、輸出上限、逾時、金鑰。
- 金鑰排最後：其他輸入有誤時，不必先設定金鑰就能看到真正的問題。
- 檔案副檔名以 `URL(filePath:).pathExtension` 不分大小寫比對 `txt`、`md`；內容以 `String(contentsOf:encoding: .utf8)` 讀取，找不到檔案、是資料夾或不是 UTF-8 都算讀檔失敗。
- 空白的 prompt：去掉 `whitespacesAndNewlines` 後為空。`blankPrompt` 帶著來源：來自 `--prompt` 時訊息寫 `--prompt`（key `error.cli.blankPrompt`），來自 `--prompt-file` 時寫檔案路徑（key `error.cli.blankPromptFile`，以 `%@` 代入）。兩句各用一個 key，文案才能自然。送出時不修剪，原樣送出。
- 模型只檢查是否為空字串，和 `LKAIChatRequest.validate()` 相同。

### 以 - 開頭的 prompt 維持解析器的行為，說明提示替代寫法

- `-p`/`--prompt` 維持預設的 parsing 策略：內容以 `-` 開頭、後面還有其他字元，作為下一個引數傳入時，swift-argument-parser 以 64 拒絕；只有一個 `-` 時被當成值接受（Context）。
- `--prompt` 的說明寫明這種內容改用 `--prompt=<text>` 或 `--prompt-file`；cli-chat「Prompt sources」把這個行為寫成情境。
- 理由：使用者 2026-11-23 選擇維持現狀。改成 `.unconditional` 只解決一或兩個 `-` 開頭的內容，`---` 開頭（例如 front matter）仍失敗，而且忘了給值時會把下一個選項當成 prompt 送出（Context）。

### client 以預設設定與 ephemeral 的 URLSession 建立

- 三家都用公開的 `init(apiKey:urlSession:)`，其他參數用預設值：Anthropic 不開拒答備援，OpenAI 與 Gemini 不保存回應。
- `URLSessionConfiguration.ephemeral`：CLI 每次只送一個請求，不需要磁碟快取與 cookie。設定由 `LKAIChatInput.makeSessionConfiguration()` 產生，見決策「--timeout 設定 URLSession 的閒置逾時，預設 60 秒」。
- `LKAICommand.run()` 是唯一讀 `ProcessInfo.processInfo.environment`、建立 `URLSession` 與建立寫到 `FileHandle` 的 `LKAICommandOutput` 的地方；它把這些交給 `execute(environment:makeClient:output:)`，測試直接呼叫 `execute` 注入替身。

### --timeout 設定 URLSession 的閒置逾時，預設 60 秒

- `--timeout <seconds>`，整數，預設 60，至少為 1；`LKAIChatInput` 保存檢查過的值。
- `LKAIChatInput.makeSessionConfiguration()` 回傳 `URLSessionConfiguration.ephemeral`，`timeoutIntervalForRequest` 設為這個值；`run()` 以它建立 `URLSession`。
- 語意是「多久沒有收到任何資料就放棄」：回應開始前與回答的兩段資料之間都適用，每收到資料就重新計時；不是整個請求的總時間（Context 的逾時實測）。
- 預設 60 秒，和 `URLSessionConfiguration` 的預設值相同，不加 `--timeout` 時的行為和沒有這個選項時一樣。
- 逾時以 `transport(underlying: URLError(.timedOut))` 回報，退出碼 1，細節是 `URLError -1001`。
- 理由：有思考的模型在開始輸出前可能有一段時間不送資料，各家在這段期間會不會送資料沒有查證。使用者 2026-11-23 選擇新增選項，讓 CI 依模型調整。
- 三家 client 不必修改：`URLRequest(url:)` 預設的 60 秒不會蓋掉 session 的設定（Context）。
- 考慮過的替代方案：沿用預設 60 秒並記成風險；把預設調高到 300 秒（估計值，沒有實測依據）。使用者選擇新增選項。

### 預設 invoke，--stream 才邊收邊寫

- 使用者 2026-11-23 選擇 `--stream`，預設 invoke。
- invoke：呼叫 `invoke(_:)`，完成後一次寫入。呼叫失敗時 stdout 是空的，CI 不會拿到半截的回答。
- stream：迭代 `stream(_:)`，每收到一段文字就寫入，寫完才讀下一個事件。
- stream 沒有收到結束事件、也沒有錯誤就結束時（例如來源被取消），比照 `LKAIChatClientProtocol.invoke(_:)` 的預設實作，當成 `invalidResponse(reason: "Stream ended before a finish event")`，走失敗的路徑、退出碼 1。兩種模式的結果因此一致。
- 兩種方式送出的請求相同：三家的非串流呼叫本來就以串流送出、由 `LKAICore` 彙整。
- 結尾的 LF：寫過文字、而且最後一個 UTF-8 位元組不是 LF 時，補一個 LF；stream 在失敗時也補。以位元組判斷，因為 CR LF 是一個 `Character`，`last == "\n"` 對 CRLF 結尾是 `false`（Context）。CI 讀 stdout 時，最後一行一定是完整的一行。
- stdout 與 stderr 以 `FileHandle.write(contentsOf:)` 寫入，不經過 `print` 的緩衝，stream 的文字才會即時出現在 pipe 的另一端。stderr 的寫入失敗以 `try?` 忽略，並在同一行註明理由：寫入失敗時已無處回報。stdout 的寫入失敗往上丟，見決策「寫回答到 stdout 失敗時以退出碼 1 結束」（第 9 組；實作複審 fable W1 指出這裡原本寫兩者都忽略）。改用會丟出 Objective-C 例外的 `write(_:)` 會讓行程崩潰。

### 退出碼：0 完成、1 服務錯誤、2 沒有正常完成、64 輸入錯誤

- `LKAICommand.execute` 把 `LKAIChatRunner.Outcome` 對應成退出碼：
  - 0：`completed`，結束原因是 `completed`。
  - 1：`failed`，包括 `LKAIError`、逾時、「沒有結束事件就結束」，以及寫回答到 stdout 失敗（決策「寫回答到 stdout 失敗時以退出碼 1 結束」）。和 swift-argument-parser 處理其他錯誤時的 `EXIT_FAILURE` 相同。
  - 2：`incomplete`，結束原因是 `maxOutputTokens` 或 `contextWindowExceeded`。回答照樣印出，stderr 印 `Warning: <訊息>`：`maxOutputTokens` 的訊息寫出 `--max-output-tokens`，`contextWindowExceeded` 的訊息寫出 context window。
  - 64：輸入錯誤，沿用 swift-argument-parser 的 `ExitCode.validationFailure`。
- 理由：使用者選擇截斷時以非 0 結束。和服務錯誤分開，CI 的腳本可以只在 2 的時候調高上限重試。
- 這四個退出碼寫在說明的 discussion，兩種語言都有。退出碼 1 的說明要涵蓋 AI 服務的錯誤、網路失敗或逾時、串流在結束前停止，以及回答無法寫到標準輸出，文字見 Implementation Contract 的「行為」（實作審查 opus S6：原本的說明沒有涵蓋網路失敗，中文的「連線逾時」也比英文窄）。

### 同一個 package 的 @nonexhaustive enum 一律窮舉

- CLI 對 `LKAIFinishReason`、`LKAIError`、`LKAIChatStreamEvent` 的 `switch` 都列出每個 case，不寫 `@unknown default`。
- 理由：
  - 同一個 package 的其他模組窮舉時沒有警告，既有的 live tests 也這樣寫（Context）。
  - 之後在 `LKAICore` 新增 case 時，CLI 會編譯失敗，一定會被處理；寫 `@unknown default` 的話，那個分支在測試中建立不出來，只會被「兩種語言都有值」的測試碰到。
- 和 `config.yaml` 的關係：「App 的 switch 必須寫 `@unknown default`」是給 package 外的 App 的規則。CLI 在同一個 package，編譯器把這些 enum 當成可以窮舉，新增 case 時 CLI 會編譯失敗，所以不寫；這不是違反該規則。
- 增減 case 時，cli-chat spec 的「detail lines」與「finish reasons」兩張表也要跟著更新；7.1 把這一點寫進 `docs/adding-a-provider.md` 第 3 章「共用型別與 API 演進」。
- 因此不需要「不認得的結束原因」的通用警告，String Catalog 只有兩個 `warning.cli.*` 的 key。

### 錯誤印通用說明加上 Details 行，細節中的金鑰換成 [REDACTED]

- 第一行是 `Error: ` 加上 `errorDescription(localization:)`。
- 有技術細節時，第二行是 `Details: ` 加上細節。細節的格式照 cli-chat「Service failure reporting」的表，由 `LKAIKitCLI` 對 `LKAIError` 的 internal extension 產生，不翻譯。`serviceUnavailable` 寫成 `status <n>`，不寫 HTTP：串流中途的錯誤沒有 HTTP 狀態碼，由供應商指定（`LKAIError` 的 `///`）。
- 細節中出現的金鑰一律換成 `[REDACTED]`。`docs/adding-a-provider.md` 第 7 章記錄過「供應商在錯誤訊息中回顯金鑰時，`.invalidRequest` 與 `.invalidResponse` 的說明會含金鑰」，library 留給之後處理；CLI 會把細節印到 CI 的 log，所以在 CLI 這一側先遮蔽。
- `Error: `、`Warning: `、`Details: ` 三個前綴固定是英文，和 swift-argument-parser 的 `Error: ` 一致，CI 用 `grep` 找得到。
- 服務錯誤不印用法：問題不在命令列的寫法。
- 細節除了遮蔽金鑰，照供應商給的原樣印出；細節含 LF 或 CR 時，stderr 會超過兩行。使用者 2026-11-23 選擇在 spec「Service failure reporting」寫明這一點，不改寫細節（實作審查 opus S2）。三家實際會不會回傳多行的訊息沒有查證。

### 寫回答到 stdout 失敗時以退出碼 1 結束

- 使用者 2026-11-23 選擇（實作審查 opus S1）。理由：CI 以退出碼判斷成功；把回答導向檔案時磁碟已滿，會留下沒寫完的回答，退出碼卻是 0（Context 的實測）。
- 做法：
  - `LKAICommandOutput.writeStandardOutput` 改成會丟出錯誤的 closure；寫到 `FileHandle` 時，stdout 的錯誤往上丟。
  - `LKAIChatRunner` 寫回答文字、stream 的片段或結尾的 LF 失敗時，停止寫回答；stream 模式不再讀下一個事件。接著在 stderr 寫 `Error: ` 加翻譯過的訊息，再寫 `Details: <domain> <code>`，例如 `Details: NSCocoaErrorDomain 640`，回傳 `.failed`。
  - 寫入失敗優先於結束原因：不寫 `Warning:`，退出碼是 1 而不是 2。
- `Details:` 的格式取 `NSError` 的 `domain` 與 `code`，和 `URLError <code>` 一樣只放代碼，不放系統的說明文字：系統的說明文字會隨系統語言改變，CI 不易比對。
- stderr 寫入失敗仍然忽略：已經沒有地方可以回報。
- SIGPIPE 不處理：接收端已結束的 pipe 不會讓寫入丟出錯誤，行程直接被終止，退出碼 141 也不是 0，CI 看得出失敗；這和 Non-Goals「處理 SIGINT、SIGPIPE」一致。
- 串流先以服務錯誤結束、補 LF 時又寫入失敗：只回報寫入失敗，服務錯誤不另外印出，cli-chat「Service failure reporting」寫明讓位給「Answer write failure」。
  - 理由：只有磁碟恰好在最後一段文字與 1 位元組的 LF 之間寫滿時才會發生。之前的寫入若已失敗，會在寫文字時回報；`write(contentsOf:)` 失敗時丟出錯誤，不會只寫一部分就算成功。兩種回報的退出碼都是 1。
  - 使用者 2026-11-23 選擇（實作複審 fable S2、opus S1 指出 spec 兩條 requirement 字面衝突）。

### --max-output-tokens 預設 4096

- 使用者 2026-11-23 選擇給預設值（提問時的例子是 4096）。Anthropic 與 OpenAI 的實際 API 測試都以 4096 通過（`LKAnthropicClientLiveTests`、`LKOpenAIClientLiveTests`）；Gemini 的實際 API 測試用的是 64，還沒有以 4096 執行過。8.1 以預設值跑三家，確認 4096 在三家都被接受。
- 有思考的模型會把思考的 token 算進輸出上限，複雜的 prompt 可能被截斷；這時以退出碼 2 結束，警告會提示調高 `--max-output-tokens`。

### prompt 只以一則使用者訊息送出，輸出語言不影響請求

- `messages` 只有一則 `.user` 訊息，`systemPrompt` 為 nil。
- `--output-language` 不進入 `LKAIChatInput`，請求與語言無關；cli-output-language「Answer language unaffected」以兩種語言建立的請求相等來驗證。

### process 測試清掉 LKAI_*_API_KEY

- 以行程執行 `lkai` 的 `runLKAI(arguments:environment:)`、`CommandOutput` 與 `BundleLocator`，從 `LKAICommandTests` 搬到 `Tests/LKAIKitCLITests/` 的「行程 helper」support 檔，給 process 測試與 `LKAICommandLiveTests` 共用。它和 4.1 放對話替身的 support 檔是兩個不同的檔案。
- 測試型別：in-process 為 `LKAICommandTests`，process 為 `LKAICommandProcessTests`。兩者以 `swift test --filter "LKAICommand(Process)?Tests"` 一起執行，不含 `LKAICommandLiveTests`。
- 搬移與拆分是行為不變的修改，獨立成一個任務先做（5.1），以既有測試把關；改寫命令列介面在下一個任務（5.2）。規劃審查第二輪兩位都建議拆開，搬移在 diff 裡是刪除加新增，和行為的修改混在一起時難以審查。
- `runLKAI` 預設使用目前的環境變數，但移除名稱以 `LKAI_` 開頭、以 `_API_KEY` 結尾的變數，並設定決策「說明文字的測試固定寬度」的 `COLUMNS`。
- 理由：owner 跑實際 API 測試時會設定這些變數；process 測試若沿用它們，原本應該在檢查階段失敗的情境可能會送出真的請求。

### 實際 API 測試以三家 × 兩種輸出方式執行，由 owner 手動跑

- `LKAICommandLiveTests` 以行程執行 `lkai`，只在對應的環境變數有設定時執行，金鑰經環境變數傳入，不出現在命令列。
- 模型與 library 的實際 API 測試相同：`claude-opus-5-5`、`gpt-6-luna`、`gemini-3.5-flash-lite`。prompt 為 `Reply with the single word OK.`，不給 `--max-output-tokens` 與 `--timeout`，以預設值執行。
- 檢查：退出碼 0、stderr 為空、stdout 去掉空白後不為空，而且以 LF 結尾。
- 8.1 另外以任一家加上 `--timeout 1` 手動送出一次，只記錄結果、不算通過與否：出現退出碼 1 與 `Details: URLError -1001`，證明 `--timeout` 確實接到連線上；在 1 秒內就收到資料時不會逾時，這不算失敗。三家的端點寫死，沒有辦法不連網做端到端的驗證，所以這一項以手動記錄補上反向檢查（規劃審查第二輪，fable）。
- 費用估計不到 0.01 美元：六個請求，每個輸出不超過 4096 個 token。這是估計值，沒有以帳單核對；執行後由用量確認。

### 新增供應商時 CLI 要跟著加 --provider 的值

- `docs/adding-a-provider.md` 第 3 章「新增供應商要動的既有檔案」加上：`LKAIChatProvider` 的 case、環境變數名稱與建立 client 的對應、它的測試、cli-chat spec 的兩張表，以及 `LKAICommandLiveTests` 的一列。String Catalog 不必修改，因為 discussion 的環境變數清單由 `LKAIChatProvider.allCases` 產生。
- 第 7 章「錯誤訊息回顯金鑰」一列補上：`lkai` 在 `Details:` 行把金鑰換成 `[REDACTED]`；library 的處理仍留給之後。

### 實作由 sonnet 在單一 worktree 依序進行

- 沿用 03、04 的做法：sonnet 在 `.worktrees/sonnet`（分支 `wt/cli-chat-sonnet`）依任務順序實作，主對話逐項驗證、執行 build 與 test、commit。
- 功能分支為 `feat/add-cli-chat-command`。第 1 到 7 組完成後合併回功能分支；owner 同意後，主對話在功能分支上執行 8.1，通過後再做 8.2。
- 8.1 沒有通過時，主對話查出原因，由 sonnet 在 worktree 修正並補上能重現問題的測試，合併後重跑 8.1。要改的是 spec 寫明的行為時，先以 `/spectra-ingest` 更新 spec 與 design。
- 任務大多修改 `LKAICommand.swift`、它的測試與 String Catalog，平行進行會衝突，所以依序進行。
- 第 9 組（實作審查後的修正）沿用同一個 worktree 與流程：9.1 到 9.5 由 sonnet 依序實作，主對話驗證、commit 並合併回功能分支，再由主對話做 9.6，之後送 fable 與 opus 複審修正的部分。

## Implementation Contract

**新增與修改的型別**（名稱依 `config.yaml` 的命名規則；實作時可調整，但要在任務回報中寫明）：

| 型別 | 位置 | 形狀 |
| --- | --- | --- |
| `LKAILocalization` | `Sources/LKAICore/LKAILocalization.swift`（新檔） | `package enum LKAILocalization`，`package static func string(forKey key: String, in bundle: Bundle, localization: String) -> String`：有 `<localization>.lproj` 時以它的 `localizedString(forKey:value:table:)` 查詢（`value`、`table` 傳 nil），沒有時改用 `bundle.localizedString(forKey:value:table:)`；查不到 key 時和 Foundation 一樣回傳 key |
| `LKAIError.errorDescription(localization:)` | `Sources/LKAICore/Chat/LKAIError.swift` | `package func errorDescription(localization: String) -> String`，以 `localizationKey` 查 `.module` |
| `LKAIOutputLanguage` | `Sources/LKAIKitCLI/LKAIOutputLanguage.swift`（新檔） | `enum LKAIOutputLanguage: String, CaseIterable, Sendable`（`ExpressibleByArgument` 寫在 `LKAICommand.swift`），`case enUS = "en-US"`、`case zhTW = "zh-TW"`；`var localization: String`（`en`、`zh-Hant`）；`@TaskLocal static var current: LKAIOutputLanguage = .enUS`；`static func scanned(from arguments: [String]) -> LKAIOutputLanguage`，規則見決策「輸出語言先掃描命令列，說明文字以 TaskLocal 取得」 |
| `LKAICLIText` | `Sources/LKAIKitCLI/LKAICLIText.swift`（新檔） | `enum LKAICLIText: String, CaseIterable`，raw value 是 String Catalog 的 key；`func string(in language: LKAIOutputLanguage, _ arguments: any CVarArg...) -> String` |
| `LKAIChatProvider` | `Sources/LKAIKitCLI/LKAIChatProvider.swift`（新檔） | `enum LKAIChatProvider: String, CaseIterable, Sendable`（`ExpressibleByArgument` 寫在 `LKAICommand.swift`），`case anthropic, openai, google`；`var apiKeyEnvironmentName: String`；`func makeClient(apiKey: String, urlSession: URLSession) -> any LKAIChatClientProtocol` |
| `LKAIChatInput` | `Sources/LKAIKitCLI/LKAIChatInput.swift`（新檔） | `struct LKAIChatInput: Sendable`：`provider`、`apiKey: LKAIAPIKey`、`request: LKAIChatRequest`、`timeout: Int`；`init(provider:model:prompt:promptFile:apiKey:maxOutputTokens:timeout:environment:) throws(LKAIChatInputError)`，`maxOutputTokens: Int`、`timeout: Int`、`environment: [String: String]` 以外的參數都是 Optional；`func makeSessionConfiguration() -> URLSessionConfiguration` |
| `LKAIChatInputError` | `Sources/LKAIKitCLI/LKAIChatInputError.swift`（新檔） | `enum LKAIChatInputError: Error, Equatable`：`missingProvider`、`missingModel`、`conflictingPrompts`、`missingPrompt`、`unsupportedPromptFile(path:)`、`unreadablePromptFile(path:)`、`blankPrompt(path: String?)`（nil 表示來自 `--prompt`，用 `error.cli.blankPrompt`；有路徑時用 `error.cli.blankPromptFile`）、`invalidMaxOutputTokens`、`invalidTimeout`、`missingAPIKey(environmentName:)`；`func message(in language: LKAIOutputLanguage) -> String` |
| `LKAICommandOutput` | `Sources/LKAIKitCLI/LKAICommandOutput.swift`（新檔） | `struct LKAICommandOutput: Sendable`，`let writeStandardOutput: @Sendable (String) throws -> Void`、`let writeStandardError: @Sendable (String) -> Void`；`init(standardOutput: FileHandle, standardError: FileHandle)` 以 `write(contentsOf:)` 寫入 UTF-8：stdout 的錯誤往上丟，stderr 的錯誤以 `try?` 忽略；另有收兩個 closure 的 `init` 給測試用；沒有 `static` 成員（第 9 組把 stdout 改成會丟出錯誤，見決策「寫回答到 stdout 失敗時以退出碼 1 結束」） |
| `LKAIChatRunner` | `Sources/LKAIKitCLI/LKAIChatRunner.swift`（新檔） | `struct LKAIChatRunner`：`client`、`output`、`language`、`apiKey: LKAIAPIKey`（只用來遮蔽）；巢狀 `enum OutputMode { case invoke, stream }`、`enum Outcome: Equatable { case completed, incomplete, failed }`；`func run(_ request: LKAIChatRequest, mode: OutputMode) async -> Outcome`；接住 stdout 的寫入錯誤，依 cli-chat「Answer write failure」回報並回傳 `.failed`；不 import ArgumentParser |
| `LKAIError` 的細節 | `Sources/LKAIKitCLI/LKAIError+Details.swift`（新檔） | internal extension，`var details: String?`，格式照 cli-chat「Service failure reporting」的表；`Duration` 以 `components.seconds` 轉成整數秒；`switch` 窮舉，不寫 `@unknown default` |
| `LKAICommand` | `Sources/LKAIKitCLI/LKAICommand.swift` | 下一段 |

**`LKAICommand` 的形狀**：

- 選項：
  - `@Option var provider: LKAIChatProvider?`
  - `@Option(name: [.short, .long]) var model: String?`
  - `@Option(name: [.short, .long]) var prompt: String?`
  - `@Option(name: [.customShort("f"), .long]) var promptFile: String?`，說明宣告 `valueName: "path"`
  - `@Option(name: .customLong("apiKey")) var apiKey: String?`
  - `@Option var maxOutputTokens: Int = 4096`
  - `@Option var timeout: Int = 60`
  - `@Flag var stream = false`
  - `@Option var outputLanguage: LKAIOutputLanguage = .enUS`
  - `@Flag(name: [.short, .long]) var version = false`
- 每個選項的 `help` 與 `configuration` 的 `abstract`、`discussion` 都讀 `LKAIOutputLanguage.current`。`discussion` 列出環境變數（由 `LKAIChatProvider.allCases` 產生）與四個退出碼；`--prompt` 的說明寫明以 `-` 開頭的內容改用 `--prompt=<text>` 或 `--prompt-file`；`--apiKey` 的說明寫明在 CI 中優先使用環境變數。
- `configuration`：`commandName: "lkai"`，自訂兩行的 `usage`，沒有 `version:`。
- 同一個檔案以空的 extension 宣告 `extension LKAIChatProvider: ExpressibleByArgument {}` 與 `extension LKAIOutputLanguage: ExpressibleByArgument {}`；`String` raw value 加上 `CaseIterable` 時，ArgumentParser 的預設實作就提供轉換與 `(values: …)`。
- `static func main() async`：取 `CommandLine.arguments.dropFirst()`，在 `LKAIOutputLanguage.$current.withValue(.scanned(from:))` 內呼叫 `parseAsRoot(_:)` 與 `run()`，錯誤交給 `exit(withError:)`。
- `validate()`：`version` 為 `true` 時丟出 `CleanExit.message(LKAIKitInfo.version)`。
- `run()`：呼叫 `execute(environment: ProcessInfo.processInfo.environment, makeClient: { input in input.provider.makeClient(apiKey: input.apiKey.unredactedValue, urlSession: URLSession(configuration: input.makeSessionConfiguration())) }, output: LKAICommandOutput(standardOutput: .standardOutput, standardError: .standardError))`。
- `execute(environment:makeClient:output:) async throws`，`makeClient` 的型別是 `(LKAIChatInput) -> any LKAIChatClientProtocol`：
  1. 四個對話選項都沒有時丟出 `CleanExit.helpRequest(self)`。
  2. 建立 `LKAIChatInput`；`LKAIChatInputError` 轉成 `ValidationError(error.message(in: outputLanguage))`。
  3. 以 `makeClient(input)` 建立 client 與 `LKAIChatRunner`，執行；`Outcome` 依決策「退出碼：0 完成、1 服務錯誤、2 沒有正常完成、64 輸入錯誤」對應成 `ExitCode`，不是 0 時丟出。

**行為**：照三份 spec。補充 spec 沒有寫死的部分：

- 輸入錯誤的訊息（兩種語言）一定含有 cli-chat「Input validation failures」表中的 token；其餘文字由實作決定，寫進 String Catalog。
- `Warning: ` 與 `Error: ` 各自是 stderr 的一行，結尾是 LF。
- stream 失敗時，先在 stdout 補 LF，再寫 stderr。
- 寫回答到 stdout 失敗時的訊息是新的 String Catalog key（`error.cli.*`，不帶參數），兩種語言都要有。
- discussion 的退出碼 1 改成（第 9 組）：
  - en：`1: The chat did not succeed: the AI service returned an error, the network failed or timed out, the stream stopped before it finished, or the answer could not be written to standard output.`
  - zh-Hant：`1：對話沒有成功：AI 服務回報錯誤、網路失敗或逾時、串流在結束前停止，或回答無法寫到標準輸出。`

**範圍**：

- 在範圍內：三份 spec、`LKAICore` 的兩個 `package` 宣告、`LKAIAPIKey` 的 `///`、`Package.swift` 的 `resources`、`docs/adding-a-provider.md`（第 1、3、5、7 章），以及 `docs/spectra/config.yaml` 中「什麼時候更新這份清單」的那一句（9.10）。
- 不在範圍內：Goals / Non-Goals 的 Non-Goals；三家 client 與 `LKAIChatClientProtocol` 的任何修改。

**完成後的狀態**：

- `LKAICommand` 的 `CommandConfiguration` 沒有 `version:`。
- `Sources/LKAIKitCLI/` 內沒有 `print(`、`@unknown default` 與 `HTTP status`；stdout 與 stderr 只經 `LKAICommandOutput` 寫入（swift-argument-parser 自己印的說明與錯誤除外）。
- `Sources/LKAIKitCLI/` 內只有 `LKAICommand.run()` 出現 `ProcessInfo.processInfo.environment`、`URLSession(` 與 `LKAICommandOutput(standardOutput:`；`URLSessionConfiguration` 與 `.ephemeral` 都只在 `LKAIChatInput.makeSessionConfiguration()` 出現，`.ephemeral` 在整個 `Sources/LKAIKitCLI/` 只出現一次；`run()` 的 `URLSession(` 那一行含有 `makeSessionConfiguration()`。
- `Sources/LKAIKitCLI/` 內只有 `LKAICommand.swift` 有 `import ArgumentParser`。
- `LKAICommandOutput` 沒有 `static` 成員；`Sources/LKAIKitCLI/` 內的 `try?` 只用在 `LKAICommandOutput` 寫 stderr 的那一處。
- `Sources/` 內不含 `///` 的行中，`unredactedValue` 只出現在 `LKAIAPIKey.swift`、三家的 `makeURLRequest(for:)`，以及 `LKAIKitCLI` 把金鑰交給 client 與遮蔽細節的兩處。
- `LKAICore` 的公開宣告沒有增減：`git diff` 中 `Sources/LKAICore/` 新增的宣告都是 `package` 層級。
- `Package.swift` 中 `LKAIKitCLI` 的依賴仍只有 `LKAIKit` 與 `ArgumentParser`。
- `LKAICLIText` 的每個 case，在 `en` 與 `zh-Hant` 都查得到不為空、也不等於 key 的字串；String Catalog 中沒有 `LKAI_` 開頭的環境變數名稱。

**驗收**：

- `swift package clean` 後，`swift build`、`swift build --build-tests` 與完整的 `swift test` 零警告。
- iOS 只驗證能建置（`LKAICore` 有修改）：以 XcodeBuildMCP 指定 `.swiftpm/xcode/package.xcworkspace`，對 iOS 26 模擬器建置 `LKAIKit` scheme；執行前先查 session defaults。
- 手動確認（主對話）：`lkai -h`、`lkai --output-language zh-TW -h`、`lkai -v` 的實際輸出貼在任務下方。
- 發佈的基準：把 `.build/debug/lkai` 單獨複製到 scratchpad 的暫存資料夾，執行 `lkai -v`，記錄結果（依 Context，預期因找不到 `LKAIKit_LKAIKitCLI.bundle` 而中止）；再把兩個 bundle 一起複製，確認 `-v` 正常。
- 測試數在驗收時記錄實際數字。

## Risks / Trade-offs

- [把 `lkai` 複製到其他地方而沒有帶上 bundle，每次執行都會 `fatalError`] → 發佈方式是 Non-Goal，之後做 release 時處理；proposal 的 Impact 記錄了要一起複製的兩個 bundle，8.2 記錄實際的結果作為基準。現在 CI 以 `swift run lkai` 或 `.build/<設定>/lkai` 執行，bundle 都在執行檔旁邊。實作審查後實測（2026-11-23）：只帶 `LKAIKit_LKAIKitCLI.bundle` 時，`-v`、`-h` 與輸入錯誤（64）都正常，服務回報錯誤時卻以 133 中止，stderr 只有 `LKAICore/resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named LKAIKit_LKAICore`，`Error:` 印不出來；封存後由 `docs/adding-a-provider.md` 第 7 章記錄（9.5）。
- [`--apiKey` 會留在 shell 的歷史紀錄、程序列表，以及 `set -x` 的 CI log] → 說明寫明優先使用環境變數；GitHub Actions 等平台也會遮蔽 secret。
- [掃描與解析器的結果在罕見的輸入下不同，例如 `-p --output-language zh-TW`] → 這類輸入會解析失敗，只影響說明文字的語言，不影響退出碼；5.2 的參數化測試確認能解析成功的輸入兩者相同。
- [以 `-` 開頭的 prompt 用 `-p` 傳入會失敗，CI 以 `-p "$BODY"` 傳入 PR 說明時可能遇到] → 說明提示 `--prompt=<text>` 與 `--prompt-file`；使用者選擇不改解析方式。
- [有思考的模型以預設 4096 被截斷] → 退出碼 2 與警告；使用者可以調高。
- [有思考的模型在開始輸出前超過 `--timeout` 沒有送資料] → 退出碼 1 與 `Details: URLError -1001`；使用者可以調高 `--timeout`。各家在思考期間會不會送資料沒有查證，遇到實例時記錄在 `docs/adding-a-provider.md`。
- [stream 中途失敗時，stdout 已有部分文字] → 退出碼 1；預設 invoke 沒有這個問題。
- [升級 swift-argument-parser 後，`validate()` 的時機、值的轉換時機或框架文字改變] → `Error: Unknown option '--bogus'`、`-v`、`USAGE: lkai ` 與不合法的值的 process 測試會失敗，升級時一併檢查。
- [`--apiKey` 的拼法和其他 kebab-case 的選項不同] → 使用者指定；拼錯成 `--api-key` 時會被提示。
- [之後加第三種輸出語言時，CLI 的 String Catalog 有、`LKAICore` 的沒有，錯誤說明會靜默變成英文] → 9.3 加了防護：每個 `LKAICLIText` 與每個 `LKAIError` 的說明，在 `LKAIOutputLanguage.allCases` 之間都要兩兩不同；加語言而漏了任一個 bundle 的翻譯，或整個語言資料夾改名時，測試會失敗（實作審查 opus W1、fable S5：原本的測試以同一條查詢算期望值，整個 `zh-Hant.lproj` 不見時仍會通過）。
- [替身 client 在 `LKAICoreTests`（`ScriptedChatClient`）與 CLI 測試各有一份] → CLI 測試只用公開的 `LKAIChatStream(_:)`，等於從 App 的角度驗證這個接縫，保留；出現第三份時再收進 `LKAITestSupport`。
- [寫回答到 stdout 失敗時，stdout 可能已有部分回答] → 退出碼 1，stderr 的 `Error:` 與 `Details:` 說明原因；寫入失敗前寫出的內容不會收回。
- [中文說明在一般寬度的終端機上超出畫面] → swift-argument-parser 以字元數計算寬度，只在半形空格處折行，但中文字在終端機上佔兩欄。2026-11-23 以 `COLUMNS=80` 實測，`lkai --output-language zh-TW -h` 共 37 行，其中 11 行的顯示寬度超過 80 欄，最寬 120 欄；英文說明只有固定的 `USAGE:` 那一行是 104 欄。CI 只看退出碼與 stdout，不受影響。記在 `docs/adding-a-provider.md` 第 7 章，留給之後（封存前最終審查：`/spectra-review`）。
