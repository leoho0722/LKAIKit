# LKAIKit

LKAIKit 是 Leo Ho 個人專案使用的 AI 服務套件，以一組和供應商無關的 Swift 對話介面整合 Anthropic Claude、OpenAI GPT 與 Google Gemini。App 只要依賴 `LKAICore` 的介面撰寫呼叫端，換供應商時只改建立 client 的那一行。

- **`LKAIKit` library**：給 iOS／macOS App 整合，`import LKAIKit` 一個模組就能使用所有供應商。
- **`lkai` 命令列工具**：給 CI/CD 使用，送出一次對話請求，把回答印到 stdout，並以退出碼回報結果。
- **Setup lkai GitHub Action**：在 macOS runner 上建置 `lkai` 並加進 `PATH`。

## 需求

- iOS 26.0+、macOS 26.0+
- Swift 6.2 以上的工具鏈（Swift 6 語言模式）
- 只支援 Apple 平台：網路層使用 Linux 沒有的 `URLSession.bytes(for:)`

## 支援的供應商

| 供應商 | Client | 使用的 API | `lkai --provider` | 金鑰的環境變數（`lkai` 與實際 API 測試） |
| --- | --- | --- | --- | --- |
| Anthropic | `LKAnthropicClient` | Messages API | `anthropic` | `LKAI_ANTHROPIC_API_KEY` |
| OpenAI | `LKOpenAIClient` | Responses API | `openai` | `LKAI_OPENAI_API_KEY` |
| Google Gemini | `LKGeminiClient` | Interactions API | `google` | `LKAI_GEMINI_API_KEY` |

三家都以 SSE 串流接收回答；端點固定為各家的官方網址，思考深度與取樣參數一律使用 API 的預設值。

## 安裝

在 `Package.swift` 加入依賴：

```swift
dependencies: [
    .package(url: "https://github.com/leoho0722/LKAIKit.git", .upToNextMinor(from: "0.1.0")),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "LKAIKit", package: "LKAIKit"),
    ]),
]
```

也可以在 Xcode 的 File → Add Package Dependencies… 輸入同一個網址。

版號沒有 `v` 前綴。0.x 期間，破壞公開介面的變更升 MINOR，其他變更升 PATCH，所以用 `.upToNextMinor(from:)` 只會自動拿到不破壞的更新。

## 使用方式

```swift
import Foundation
import LKAIKit

// 依設定建立具體的 client，存成 any LKAIChatClientProtocol 使用；換供應商時只改這一行
let client: any LKAIChatClientProtocol = LKAnthropicClient(
    apiKey: apiKey,
    urlSession: .shared
)

let request = LKAIChatRequest(
    model: "claude-opus-5-5",
    messages: [LKAIMessage(role: .user, text: "用一句話介紹 Swift Concurrency")],
    systemPrompt: "請以正體中文回答",
    maxOutputTokens: 1024
)

// 等整段回答完成
do {
    let response = try await client.invoke(request)
    print(response.text)
    print(response.completion.finishReason, response.completion.usage as Any)
} catch {
    // invoke 以 typed throws 丟出 LKAIError
    print(error)
}

// 邊收邊顯示
do {
    for try await event in client.stream(request) {
        switch event {
        case .textDelta(let text):
            print(text, terminator: "")

        case .finished(let completion):
            print("\n結束原因：\(completion.finishReason)")

        @unknown default:
            break
        }
    }
} catch {
    print(error)
}
```

- `LKAIError`、`LKAIFinishReason` 與 `LKAIChatStreamEvent` 是 `@nonexhaustive` enum，之後可能新增 case，`switch` 要寫 `@unknown default`。
- 釋放串流才會取消底層請求；只用 `break` 離開迴圈而仍持有串流時，請求會繼續進行並計費。
- 逾時與連線設定由傳入的 `URLSession` 決定。
- 供應商專屬的設定在建立 client 時傳入，預設值都是關閉：
  - `LKAnthropicClient(apiKey:urlSession:refusalFallback:)`：拒答時的備援設定。
  - `LKOpenAIClient(apiKey:urlSession:shouldStoreResponses:)`、`LKGeminiClient(apiKey:urlSession:shouldStoreResponses:)`：是否讓供應商保存回應。
- API 金鑰不會出現在 client 的 `description`、`debugDescription`、`dump(_:)` 與回報的錯誤裡。
- 寫測試替身時，只要實作 `stream(_:)`（可以用 `LKAIChatStream(_:)` 包一個 `AsyncThrowingStream`），`invoke(_:)` 使用預設實作。

## `lkai` 命令列工具

```bash
swift build -c release --product lkai
LKAI="$(swift build -c release --product lkai --show-bin-path)/lkai"

export LKAI_ANTHROPIC_API_KEY=...   # 依 --provider 讀取對應的環境變數，也可以用 --apiKey
"$LKAI" --provider anthropic --model claude-opus-5-5 --prompt "Hello"
"$LKAI" --provider openai --model <模型> --prompt-file prompt.md --stream
"$LKAI" --version
```

`lkai` 執行時要讀建置資料夾裡、它旁邊的 resource bundle，請直接從建置資料夾執行，不要把執行檔單獨複製到別處。

| 選項 | 說明 |
| --- | --- |
| `--provider <provider>` | `anthropic`、`openai` 或 `google` |
| `-m`、`--model <model>` | 模型識別碼 |
| `-p`、`--prompt <prompt>` | 提示詞；以 `-` 開頭的文字請改用 `--prompt=<text>` 或 `--prompt-file` |
| `-f`、`--prompt-file <path>` | 從 `.txt` 或 `.md` 檔讀取提示詞（UTF-8）；和 `--prompt` 二選一 |
| `--apiKey <key>` | API 金鑰；沒給時讀所選供應商的環境變數 |
| `--max-output-tokens <n>` | 回答最多使用的 token 數，預設 4096 |
| `--timeout <seconds>` | 多久沒有收到任何資料就放棄，預設 60 秒 |
| `--stream` | 邊收邊印出回答 |
| `--output-language <language>` | `lkai` 自己的訊息使用的語言：`en-US`（預設）或 `zh-TW`；不影響回答的語言 |
| `-v`、`--version` | 印出版本號 |

回答寫到 stdout，其他訊息寫到 stderr。退出碼：

| 退出碼 | 意義 |
| --- | --- |
| 0 | 成功 |
| 1 | 服務回報錯誤、逾時、回應無法解讀，或寫出回答失敗 |
| 2 | 回答不完整，例如達到輸出上限 |
| 64 | 命令列的輸入不合法 |

## GitHub Action：Setup lkai

在 macOS runner 上，從 action 自己的原始碼建置 `lkai`，加進後續 step 的 `PATH`：

```yaml
jobs:
  ask:
    runs-on: xcode-27   # 需要 macOS 26 以上、Swift 6.2 以上的 runner
    steps:
      - uses: leoho0722/LKAIKit@<ref>
        id: lkai
      - run: lkai --provider anthropic --model claude-opus-5-5 --prompt "Hello"
        env:
          LKAI_ANTHROPIC_API_KEY: ${{ secrets.LKAI_ANTHROPIC_API_KEY }}
```

- 建置的是 `<ref>` 那個版本的程式碼，不是呼叫端 repo 的程式碼。
- 輸出：`path`（`lkai` 執行檔的絕對路徑）、`version`（`lkai -v` 印出的版號）。
- 不是 macOS runner 時，在建置之前就失敗。

## 開發

```bash
swift build                                       # 建置
swift test                                        # 單元測試
swift test --filter LKAIOpenAITests               # 只跑一個測試 target 或 suite
bash .github/scripts/release/tests/run-tests.sh   # 發版 script 的測試
```

- 實際呼叫 API 的測試只在設定對應的金鑰環境變數時執行，會產生費用；沒有設定時顯示為略過。CI 不提供任何金鑰。
- 開發流程採用 Spectra 的 Spec-Driven Development：系統的行為以 `docs/spectra/specs/` 的 spec 為準，每次變更都在 `docs/spectra/changes/` 提案，完成後封存到 `docs/spectra/changes/archive/`。
- 給 coding agent 的說明在 `AGENTS.md`，`CLAUDE.md` 匯入同一份內容。

## 發版

合併到 `main` 之後，release workflow 會自動判斷要不要發版：版號的唯一來源是 `LKAIKitInfo.version`，由 `lkai` 請 AI 判斷升級等級並撰寫 Release Notes，再由 script 算出新版號、建立 commit、tag 與 GitHub Release。只改不發版的檔案（清單見 `docs/releasing.md` 3.1）的合併不會發版。觸發、試跑、切換供應商與模型、失敗時怎麼接手，見 [`docs/releasing.md`](docs/releasing.md)。

## 文件

- [`docs/adding-a-provider.md`](docs/adding-a-provider.md)：新增供應商時要讀的清單，包含必須遵守的規則與供應商對照表。
- [`docs/releasing.md`](docs/releasing.md)：發版操作手冊。
- [`docs/spectra/specs/`](docs/spectra/specs/)：各項功能的 spec。

## 授權

[MIT License](LICENSE)
