## Why

三家供應商（Anthropic、OpenAI、Gemini）已經實作完成，但 `lkai` 目前只能查版號，CI/CD 流程還無法透過它呼叫 AI。這個 change 讓 `lkai` 在根指令上直接送出一次對話請求，並以 CI 讀得懂的 stdout、stderr 與退出碼回報結果。

## What Changes

- **`lkai` 根指令新增對話選項**（不新增子指令）：
  - `--provider <anthropic|openai|google>`：選擇供應商，分別對應 `LKAnthropicClient`、`LKOpenAIClient`、`LKGeminiClient`。
  - `-m, --model <model>`：本次使用的模型，必填，沒有預設值。
  - `-p, --prompt <text>` 與 `-f, --prompt-file <path>`：兩者必須且只能給一個；檔案只接受副檔名 `.txt` 與 `.md`（不分大小寫），內容以 UTF-8 讀取。prompt 以一則使用者訊息送出，不加系統指示。內容以 `-` 開頭、後面還有其他字元時，`-p <text>` 會被 swift-argument-parser 當成選項而失敗（只有一個 `-` 時會被接受），說明會提示改用 `--prompt=<text>` 或 `--prompt-file`。
  - `--apiKey <key>`：API 金鑰（使用者指定的拼法）；沒有給時依供應商讀環境變數 `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`。
  - `--max-output-tokens <n>`：輸出上限，預設 4096，必須至少為 1。
  - `--timeout <seconds>`：多久沒有收到 AI 服務的任何資料就放棄，包括回應開始前與回答的兩段資料之間；預設 60，必須至少為 1。
  - `--stream`：邊收邊寫入 stdout；沒有給時等整段回答完成才寫入（invoke）。
  - `--output-language <en-US|zh-TW>`：CLI 自己的訊息用的語言，預設 `en-US`。
- **`-v` 與 `--version` 都能查版號**：改用自己宣告的版本旗標，取代 swift-argument-parser 內建、只有 `--version` 的版本旗標。和內建的 `--version` 一樣，與未定義的輸入一起給時仍印出版本，與 `-h` 一起給時印出說明。
- **輸出與退出碼**：
  - stdout 只放回答的文字；錯誤、警告都寫到 stderr。
  - 退出碼：0 為完整回答；1 為 AI 服務回報錯誤、網路失敗或逾時、串流在結束前就停止，或回答無法寫到 stdout（例如導向檔案時磁碟已滿）；2 為回答沒有正常完成（例如達到輸出上限而被截斷），此時回答仍會印出，stderr 另有警告；64 為輸入有問題（沿用 swift-argument-parser 的驗證失敗退出碼）。
  - AI 服務的錯誤印出依語言翻譯的通用說明；錯誤帶有技術細節（例如供應商的錯誤訊息）時，下一行附上原文，原文中出現的 API 金鑰換成 `[REDACTED]`；原文含 LF 或 CR 時照樣印出，會跨多行。`lkai` 自己寫出的說明、錯誤與警告不含 API 金鑰；swift-argument-parser 的錯誤訊息會原樣重複無法解析的引數，AI 的回答也原樣輸出，兩者都不遮蔽。
  - 寫回答到 stdout 失敗時，停止輸出，stderr 印出翻譯過的說明與錯誤代碼，以 1 結束。
  - 沒有給任何對話選項（`--provider`、`--model`、`--prompt`、`--prompt-file`）時，照舊印出說明並以 0 結束。
- **輸出語言**：簡介、各選項說明、CLI 自己的錯誤與警告，以及 `LKAIError` 的說明，依 `--output-language` 顯示英文或正體中文。swift-argument-parser 自己產生的文字（`USAGE:`、`OPTIONS:`、`Error:` 前綴、`-h` 的說明與解析錯誤）維持英文。AI 回答的語言不受影響。
- **`LKAICore`**：新增 `package` 層級、可以指定語言查 String Catalog 的方法，並讓 `LKAIError` 能以指定的語言取得說明。公開的 `errorDescription` 與其他公開 API 都不變。
- **`LKAIKitCLI`**：新增自己的 String Catalog（`en`、`zh-Hant`），`Package.swift` 為它宣告資源。

## Non-Goals (optional)

見 design.md 的 Goals / Non-Goals。

## Capabilities

### New Capabilities

- `cli-chat`: `lkai` 如何把命令列輸入組成一次對話請求並送出：供應商與模型的選擇、prompt 的來源、API 金鑰的來源、輸出上限、連線的逾時、stream 與 invoke 兩種輸出方式，以及完成、截斷與失敗時的 stdout、stderr 與退出碼。
- `cli-output-language`: `--output-language` 如何決定 `lkai` 自己的說明、錯誤與警告的語言，哪些文字會翻譯、哪些維持英文，以及它不影響 AI 回答的語言。

### Modified Capabilities

- `cli-root-command`: 「Version output」改為 `--version` 與 `-v` 都印出版號，並寫明說明與版本旗標的優先順序；「Invalid input rejection」寫明給了說明旗標或版本旗標時的例外。

## Impact

- 修改的程式碼：
  - `Sources/LKAIKitCLI/LKAICommand.swift`：新增選項、自訂 `main()` 以先決定輸出語言、`-v` 版本旗標，以及對話的執行流程。
  - `Package.swift`：`LKAIKitCLI` 宣告 `resources`。
  - `Sources/LKAICore/Chat/LKAIError.swift`：新增 `package` 層級、指定語言的說明。
  - `Sources/LKAICore/Networking/LKAIAPIKey.swift`：只改 `///`，把允許讀取原始金鑰的用途寫成「組 HTTP 請求、把金鑰交給 client、遮蔽輸出中的金鑰」，不點名使用的模組。
  - `Tests/LKAIKitCLITests/LKAICommandTests.swift`：既有測試保留；說明輸出的檢查從「有一行剛好是 `USAGE: lkai`」改成「有一行以 `USAGE: lkai `（含結尾空格）開頭」，因為加了選項之後用法那一行會變長。以行程執行 `lkai` 的 helper 搬到同一個資料夾的 support 檔。另外新增 `-v` 與對話選項的測試。
- 新增的程式碼：`Sources/LKAIKitCLI/` 中對話流程、輸出語言與字串查詢的檔案，`Sources/LKAIKitCLI/Resources/Localizable.xcstrings`，`Sources/LKAICore/` 中指定語言查字串的檔案，以及它們在 `Tests/LKAIKitCLITests/`、`Tests/LKAICoreTests/` 的測試，其中包括 `Tests/LKAIKitCLITests/LKAICommandOutputTests.swift`。
- 文件：`docs/adding-a-provider.md` 的「新增供應商要動的既有檔案」加上 CLI 的部分，之後新增供應商時，`--provider` 要跟著加一個值與環境變數；第 7 章「錯誤訊息回顯金鑰」一列補上 `lkai` 的處理方式，並加上這個 change 留給之後的項目（要和兩個 bundle 一起發佈、重複的錯誤文字、思考期間的逾時、替身 client）。
- 公開 API：不變。`LKAICore` 只新增 `package` 層級的宣告。
- 外部依賴：沒有新增，仍只有 `LKAIKitCLI` 依賴 swift-argument-parser。
- 發佈：`lkai` 每次執行都會讀 `LKAIKit_LKAIKitCLI.bundle`，因為 swift-argument-parser 每次解析時都會產生選項說明。印出 AI 服務的錯誤說明時，另外讀 `LKAIKit_LKAICore.bundle`。SwiftPM 產生的 `Bundle.module` 只在執行檔旁（以及 App、framework 的資源位置）尋找，找不到時會 `fatalError`。所以把 `lkai` 複製到建置目錄以外的地方時，要連同這兩個 bundle 一起複製。
