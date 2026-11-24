<!-- SPECTRA:START v1.5.0 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `docs/spectra/specs/`, change proposals in `docs/spectra/changes/`.

## Use `$spectra-*` skills when:

- An explicitly requested Spectra decision needs structure → `$spectra-discuss`
- User explicitly requests a Spectra change proposal → `$spectra-propose`
- Continue tasks for an identified change → `$spectra-apply`
- Update requirements or plans for an identified change → `$spectra-ingest`
- Check implementation matches artifacts → `$spectra-verify`
- An identified change has implementation ready for code-quality review → `$spectra-review`
- Analyze artifact consistency before coding → `$spectra-analyze`
- A security audit of changed code is explicitly requested → `$spectra-audit`
- Check stale changes before resuming → `$spectra-drift`
- Systematic debugging is explicitly requested, or a failure persists after two focused attempts → `$spectra-debug`
- An identified change has every task done and verified → `$spectra-archive`
- Commit only files related to a specific change → `$spectra-commit`

Explicit skill invocation takes precedence. Apply existing authorization within its unchanged scope.

## Workflow

discuss? → propose → apply ⇄ ingest → verify / review → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? `ingest` → resume `apply`. When the user drafted the change in plan mode (`/plan`), that plan is the `ingest` source.

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `docs/spectra/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `$spectra-apply` and `$spectra-ingest` skills disclose parking and restore when the named operation is already explicitly requested; respect a known refusal, otherwise ask for missing authorization.

<!-- SPECTRA:END -->

# AGENTS.md

這份檔案給在這個 repo 工作的 coding agent 參考；Claude Code 經由 `CLAUDE.md` 匯入同一份內容。最上方的 Spectra 區塊由 Spectra 產生，不要手動修改。

## 專案說明

LKAIKit 是 Leo Ho 個人專案使用的 Swift Package，以一組和供應商無關的對話介面整合 Anthropic、OpenAI 與 Google Gemini。使用 Swift 6（swift-tools-version 6.2），支援 iOS 26.0+ 與 macOS 26.0+。

- `LKAIKit` library：給 iOS App 整合，App 只要 `import LKAIKit`。
- `lkai` executable（`LKAIKitCLI` target）：給 CI/CD 使用；這個 repo 的發版流程用它請 AI 判斷升級等級、撰寫 Release Notes。

只能在 macOS 上建置與測試：網路層依賴 Linux 沒有的 `URLSession.bytes(for:)`。

## 常用指令

```bash
swift build
swift test                                        # 沒有設定金鑰時，實際 API 測試顯示為略過
swift test --filter LKAIOpenAITests               # 只跑一個測試 target
swift test --filter LKOpenAIClientStreamTests     # 只跑一個 suite；也可以直接給測試函式的名稱
bash .github/scripts/release/tests/run-tests.sh   # 發版 script 的 bash 測試（一次跑全部）
```

- 測試使用 Swift Testing，測試函式以中文命名（「受測對象_情境_預期結果」），`--filter` 可以直接給這個名稱。
- 實際 API 測試只在設定 `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY` 或 `LKAI_GEMINI_API_KEY` 時執行，會產生費用。金鑰存在 Keychain，service 名稱是 `lkai-anthropic-api-key`、`lkai-openai-api-key`、`lkai-gemini-api-key`：

  ```bash
  LKAI_GEMINI_API_KEY="$(security find-generic-password -s lkai-gemini-api-key -w)" swift test --filter LKGeminiClientLiveTests
  ```

- 執行 `lkai`：兩個 `swift build` 都要加 `-c release`；`lkai` 執行時讀旁邊的 resource bundle，要留在建置資料夾執行。

  ```bash
  swift build -c release --product lkai
  "$(swift build -c release --product lkai --show-bin-path)/lkai" --provider anthropic -m <模型> -p "<提示詞>"
  ```

- iOS 模擬器建置：`.swiftpm/xcode/package.xcworkspace` 的 `LKAIKit` scheme。
- 改了 workflow 或 shell script 之後，執行 `actionlint` 與 `shellcheck -x -s bash`。

## 架構

```
LKAICore ← LKAIAnthropic / LKAIOpenAI / LKAIGemini ← LKAIKit（總成）← LKAIKitCLI（lkai）
LKAICore ← LKAITestSupport（測試共用，不屬於任何 product）
```

- 供應商 target 只依賴 `LKAICore`，彼此不互相依賴。`LKAIKit` 只有 `Exports.swift`，以 `@_exported import` 重新匯出所有 library target。library 這一側不依賴外部套件，`swift-argument-parser` 只有 `LKAICommand.swift` 匯入。
- **對話的共同流程**：App 只面對 `LKAIChatClientProtocol`。`stream(_:)` 依序交出 `.textDelta`，最後交出一次 `.finished`；`invoke(_:)` 是把串流彙整起來的預設實作。供應商的 client 遵循 `LKAIServerSentEventChatStreaming`，只提供 `httpClient`、`makeURLRequest(for:)`、`httpError(statusCode:headers:body:)`、`makeEventMapper()` 四項，`stream(_:)` 只寫 `makeStream(for: request)` 一行。請求驗證、送出、錯誤分類與 SSE 解析都在 `LKAICore` 的 `makeStream(for:)`；每條串流的事件狀態與結束判斷，由供應商的 mapper（遵循 `LKAIServerSentEventMapping`）持有。
- 整個 package 只有 `LKAIChatStream.init(producing:)` 建立 `Task`，供應商不可以自己建立。錯誤一律以 typed throws 丟出 `LKAIError`。
- 測試以各家 client 的 `package init(apiKey:httpClient:…)` 注入 `LKAITestSupport` 的 `LKAIMockHTTPClient`，不連網。
- 金鑰一律以 `LKAIAPIKey` 保存，不用 `String`；能讀原始值 `unredactedValue` 的位置有限定，見 `docs/adding-a-provider.md` 第 3 章。
- **`lkai`**：`LKAICommand.run()` 是唯一讀環境變數、建立 `URLSession` 與標準輸出入的地方，其餘流程在 `execute(environment:makeClient:output:)`，測試從參數注入替身。`lkai` 對 `LKAICore` 的 enum 刻意列出每個 case、不寫 `@unknown default`，在 `LKAICore` 增減 case 時它會編譯失敗。
- **CI**：每個 PR 在 `xcode-27` runner 上試跑本 repo 的 setup action（`action.yml`），再執行 `swift test` 與發版 script 的測試；不提供任何真實金鑰。
- **發版**：push 到 `main` 時，`release.yml` 執行 `.github/scripts/release/release.sh`，依 `LKAIKitInfo.version`（`Sources/LKAICore/LKAIKitInfo.swift`，版號的唯一來源）與 tag 決定要不要發版。push 改動的檔案全部是不發版的檔案時不發版，清單見 `docs/releasing.md` 3.1；只要有一個其他檔案就會發版。

## 規則

完整的規則寫在 `docs/spectra/config.yaml` 的 `context`，以下是改任何程式都會用到的部分：

- **命名**：模組是 `LKAI<名稱>`；非供應商 target 的頂層型別是 `LKAI<名稱>`，供應商 target 的是 `LK<供應商><名稱>`（例如 `LKOpenAIClient`）；型別不可以和任何模組同名。
- **不可以**：在 public 層級擴充本 package 以外的型別；宣告 public 或 package 層級的頂層函式；在 `LKAICore` 以外讓外部型別遵循本 package 的 public protocol。
- **API 演進**：預期會新增 case 的公開 enum 標 `@nonexhaustive`；公開 struct 新增欄位時，`public init` 的新參數給預設值；`0.1.0` 已經發佈，之後要替公開 enum 的 case 加資料時改用 struct。供應商的 change 不可以為了自己的格式修改 `LKAICore` 的共用公開型別。
- **Swift 寫法**：依 ios-dev-kit skill 的規範。
- **測試**：每個測試上方依 spec 加 `// spectra-scenario: <capability> / <情境>`。
- **shell 與 workflow**：寫法的限制（相容 bash 3.2 等）寫在每支 script 開頭的註解，`test-script-style.sh` 會檢查其中一部分；workflow 的第三方 action 以完整的 commit SHA 固定，`${{ }}` 先以 `env` 傳入再使用。
- **Spectra 文件**：proposal、design、tasks 以正體中文撰寫；spec 的 Scenario 依序用 `- **GIVEN**`、`- **WHEN**`、`- **THEN**`，額外的條件或結果用 `- **AND**`。

## 改之前先讀

- 新增供應商，或修改 chat-client spec、任一供應商 spec、`LKAICore` 的共同流程、`lkai`：開始前讀 `docs/adding-a-provider.md`，封存前把新的查證結果與決定更新回去。
- 修改 release-automation spec、`release.yml` 或 `.github/scripts/release/`：開始前讀 `docs/releasing.md`，封存前更新它。
- 權威順序：spec（`docs/spectra/specs/`）優先於這兩份手冊，手冊優先於封存的 design（`docs/spectra/changes/archive/`）。
