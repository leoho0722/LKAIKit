## Context

LKAIKit 目前只有 `LICENSE` 與 Spectra 設定，沒有任何 Swift 程式碼。本 change 建立 Swift Package 骨架，讓 BuyLedger 等 iOS App 能以 library 引用，CI/CD 能執行命令列工具；之後各 AI 供應商（OpenAI GPT、Anthropic Claude、Google Gemini）會在這個骨架上逐一加入。

限制與既有規範：

- Swift 6、以 Swift Package 發佈，平台為 iOS 26.0+ 與 macOS 26.0+；專案說明規定固定前綴字為 `LK`，完整的命名規則已在規劃階段寫入 `docs/spectra/config.yaml` 的專案說明。
- 程式碼遵循使用者的 ios-dev-kit 規範：`Package.swift` 固定 `swift-tools-version: 6.0`（本 change 經使用者決定改用 6.2，見 Decisions）加 `swiftLanguageModes: [.v6]`、單元測試一律 Swift Testing、所有宣告都有 `///`、有對應樣板的檔案從 ios-dev-kit 樣板複製、`static` 只用於字面值常數等允許情境。
- 使用者已決定：採多 target 分層、CLI 以 swift-argument-parser 建立根指令、CLI 與 library 維持在同一個 package、本 change 只建骨架不含供應商共用抽象；未採用的替代方案記錄在各 Decisions。
- 使用者的另一個 library LeoKit 已有 47 個公開的 `LK<名稱>` 頂層型別（例如 `LKAvatar`、`LKBadge`、`LKBanner`），沒有任何一個以 `LKAI`、`LKOpenAI`、`LKAnthropic` 或 `LKGemini` 開頭（2026-11-21 於本機 LeoKit repo 搜尋確認）。

以下技術事實已於 2026-11-21 在 scratchpad 原型以 Swift 6.4.2（Xcode 27.2）實測確認：

- `swift-tools-version: 6.0` 使用 `.iOS(.v26)` 會出現 `'v26' is unavailable`；改用字串形式 `.iOS("26.0")`、`.macOS("26.0")` 可正常解析。
- 只有 `@_exported import LKAICore` 能讓只寫 `import LKAIKit` 的程式碼使用 `LKAICore` 的型別；`public import` 與一般 `import` 都會出現 `cannot find 'LKAIKitInfo' in scope`。
- Swift Testing 可對 executable target 使用 `@testable import`（macOS）。
- `Sources/` 目錄已存在時，manifest 宣告的 target 只要有一個缺少來源目錄，`swift build` 與 `swift test` 就會在載入 package 時失敗（`Source files for target LKAIKit should be located under 'Sources/LKAIKit'`）；`swift package dump-package` 與 `swift package resolve` 只讀 manifest，不受影響。`Sources/` 完全不存在時的例外見下方 apply 期間的補充。
- 只依賴 `LKAIKit` library product 的使用端 package（以 URL 加版本引用）執行 `swift package resolve` 時，仍會下載 swift-argument-parser，並把它以 1.8.2 寫進使用端的 `Package.resolved`；`swift build` 的輸出中沒有 ArgumentParser 的編譯步驟。
- swift-argument-parser 1.8.2 的根指令未實作 `run()` 時：
  - 不帶參數、`--help`、`-h` 都在 stdout 印出說明（含 `USAGE: lkai` 與 `--version`），stderr 無輸出，以 0 結束。
  - `--version` 在 stdout 印出版本，以 0 結束。
  - 未知選項 `--bogus` 在 stderr 印出 `Error: Unknown option '--bogus'`，多餘引數 `foo` 印出 `Error: Unexpected argument 'foo'`；兩者 stdout 都無輸出，都以 64 結束。
  - `ParsableCommand` 與 `AsyncParsableCommand` 行為相同；以 `parseAsRoot([])` 取得的 `AsyncParsableCommand` 執行 `run()` 會拋出說明請求，`fullMessage(for:)` 含 `USAGE: lkai`，`exitCode(for:)` 為 `.success`。
- XcodeBuildMCP 只接受 `.xcodeproj` 或 `.xcworkspace` 路徑。純 package 需要 `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`（內容為指向 `self:` 的 `FileRef`）。有了這個檔案後，`list_schemes` 列出 `lkai`、`LKAIKit`、`LKAIKit-Package` 三個 scheme，`build_sim` 對 `LKAIKit` scheme 與 iPhone 17 模擬器建置成功；建置後 `.swiftpm/` 底下仍只有這一個檔案。

以下為 2026-11-21 apply 期間以 Swift 6.4.2 實測，或讀 swift-argument-parser 1.8.2 原始碼確認的補充：

- repo 還沒有任何 `Sources/` 目錄時（本 change 宣告第一個 target `LKAICore` 的情況），缺少來源目錄的 target 在載入 package 時只出現警告，訊息會多列出 `'Sources'` 作為可能位置；要到編譯依賴它的 target 時才失敗（`unable to resolve module dependency: 'LKAICore'`）。只要 `Sources/` 已存在，任何 target 缺少來源目錄都在載入時失敗，與該 target 是否被 product 引用無關。
- `parseAsRoot(["--help"])` 與 `parseAsRoot(["-h"])` 不會拋出錯誤，而是回傳 `HelpCommand`（`CommandParser` 攔下 `HelpRequested` 後回傳），執行它的 `run()` 才拋出說明請求，與 `main()` 先解析、再執行的流程相同。`--version` 與未定義的輸入則在 `parseAsRoot` 時就拋出。
- 未知選項、多餘引數這類驗證錯誤的 `fullMessage(for:)`，第一行帶有 `Error: ` 前綴，與實際 stderr 的第一行相同。
- 未設定 `commandName` 時，指令名稱由型別名轉成 kebab-case，`LKAICommand` 會成為 `lkai-command`，usage 行變成 `USAGE: lkai-command`；這行仍包含子字串 `USAGE: lkai`，所以測試改以「有一行剛好是 `USAGE: lkai`」驗證。
- SwiftPM 不檢查 target 是否只 import 自己宣告的依賴：讓 `LKAIKitCLI` 直接 `import LKAICore`（只經 `LKAIKit` 間接依賴）時，預設建置與加上 `--explicit-target-dependency-import-check error` 都建置成功。測試 target 的情況未實測。
- 清除建置產物後只執行 `swift test --filter LKAIKitCLITests`，也會建置出 `lkai` 執行檔，位置是 `.build/out/Products/Debug/lkai`，與 `LKAIKitCLITests.xctest` 在同一個資料夾；`.build/debug` 是指向該資料夾的符號連結。
- `swift-tools-version: 6.2` 可直接使用 `.iOS(.v26)`、`.macOS(.v26)`：`swift package dump-package` 的 toolsVersion 為 6.2.0，平台為 iOS 26.0 與 macOS 26.0；清除建置產物後的 `swift build`、完整 `swift test`、`lkai` 六種輸入，以及 XcodeBuildMCP 對 iOS 26.5 模擬器建置 `LKAIKit` scheme 都通過，沒有警告。

## Goals / Non-Goals

**Goals:**

- 建立可編譯、可測試的 package：App 能依賴 `LKAIKit` library product，CI/CD 能執行 `lkai` executable。
- 確立模組依賴方向，並寫成 spec 需求：之後新增供應商時只需新增一個 target，並在 `LKAIKit` 總成加入依賴與重新匯出，不需更動 `LKAICore` 與其他供應商。
- library product 的建置範圍（從 `LKAIKit` target 出發可達的所有 target）不含任何外部套件，App 建置時不會編譯 CLI 專用的依賴。
- 套件版本只有一個來源，CLI 與日後的網路請求共用。
- 確立命名規則並寫進專案說明，避免日後各供應商的公開名稱在 `import LKAIKit` 時互相衝突，也避免與 LeoKit 的公開型別衝突。

**Non-Goals:**

- 各供應商共用的抽象（protocol、訊息模型、錯誤型別）：另開 change 設計。
- 任何供應商的實作（`LKAIOpenAI`、`LKAIAnthropic`、`LKAIGemini` target）。
- CLI 子指令與任何實際的 CI/CD 工作流程。
- 版本號與 git tag 自動同步、release 流程。
- CI 設定檔（例如 GitHub Actions workflow）。
- 為 `LKAICore` 或各供應商提供獨立的 library product。
- 常駐於 repo 的外部使用端 fixture package（見 Risks / Trade-offs）。
- README 與 DocC 文件。

## Decisions

### 採用多 target 分層：LKAICore、LKAIKit 總成與 LKAIKitCLI

依賴方向固定單向，箭頭指向被依賴者：

```text
LKAIKitCLI ──▶ LKAIKit ──▶ LKAICore
                  │            ▲
                  └──▶ LKAIOpenAI / LKAIAnthropic / LKAIGemini（之後的 change 加入）
```

- `LKAICore` 不依賴 package 內任何其他 target，也不依賴外部套件。
- 供應商 target 只依賴 `LKAICore`，供應商之間互不依賴。
- `LKAIKit` 是總成：依賴 `LKAICore` 與所有供應商 target，只負責重新匯出，不放實作。
- `LKAIKitCLI` 在 package 內只依賴 `LKAIKit`（外加 swift-argument-parser），透過與 App 相同的公開 API 使用功能。
- 存取層級：給 App 使用的 API 標 `public`；package 內跨 target 共用、但不給 App 使用的成員標 `package`。
- 上述依賴方向寫進 package-distribution spec 的「Module dependency direction」需求，以 `swift package dump-package` 驗證，archive 後仍有規範性來源。該需求中的「library target」指 manifest 以 `.target` 宣告的 target，不含 `.executableTarget` 與 `.testTarget`。

這個決定刻意偏離 ios-dev-kit「一個 package 一個 library target」的規則。該規則針對 App 的 local package；LKAIKit 是多供應商 SDK，供應商之間不得耦合的邊界需要由編譯器強制，才能長期維持。

考慮過的替代方案：

- 單一 library target、以資料夾分 Core 與 Providers：結構最簡單、符合 ios-dev-kit 規則，但邊界只能靠慣例與 review 維持，使用者未採用。
- 每個供應商一個獨立 package 或 repo：版本同步與發佈成本高，對個人專案沒有對應的收益。

### CLI 與 library 維持在同一個 package

`lkai` 與 `LKAIKit` 宣告在同一個 `Package.swift`。使用者已決定維持單一 package，並接受以下實測確認的代價：App 只依賴 `LKAIKit` 時，依賴解析仍會下載 swift-argument-parser、寫進 App 的 `Package.resolved`，並受 `from: "1.8.2"` 的版本範圍限制；App 建置時不會編譯它。

考慮過的替代方案：

- 把 CLI 拆成 repo 內的獨立 package（例如 `Tools/lkai/`，以 path 依賴根 package）：根 package 完全沒有外部依賴、所有測試都能在 iOS 執行，CLI 也只能使用公開 API；代價是兩份 manifest 與 `Package.resolved`、測試分兩處執行。使用者未採用；日後 App 端若出現版本衝突，再以這個方案另開 change。
- 把 CLI 延到第一個子指令的 change 才建立：可延後外部依賴，但無法先定下 product 名稱與入口，使用者未採用。

### 對外只提供 LKAIKit 一個 library product

App 只依賴 `LKAIKit` product；`LKAICore` 與之後的供應商 target 不單獨提供 product。日後若有 App 只需要單一供應商，再新增該供應商的 product；新增 product 不會破壞既有使用端，因此不必預先開放。

考慮過的替代方案：現在就為每個 target 提供 product。這會讓尚未存在的需求提早變成公開承諾，否決。

### 以 @_exported import 讓 App 只需 import LKAIKit

- `Sources/LKAIKit/` 只有一個重新匯出檔 `Exports.swift`，內容只有 `@_exported import LKAICore`；之後每加入一個供應商，就在同一檔案加一行。
- 重新匯出的行為由 `LKAIKitTests` 的 `ExportsTests` 把關：測試檔只寫 `import LKAIKit`，不使用 `@testable`，刪掉重新匯出時會編譯失敗。
- `ExportsTests` 不得 import `LKAICore` 或任何供應商模組，這條規則寫在 `ExportsTests` 的 `///` 說明裡。SwiftPM 不會擋下 import 間接依賴模組的寫法（見 Context 的 apply 期間補充），所以這條防線只靠該檔案本身與 review 維持。
- 每加入一個供應商，`ExportsTests` 也要新增一個只透過 `import LKAIKit` 引用該供應商公開型別的測試。

考慮過的替代方案：

- `public import LKAICore`：實測無法讓使用端看到 `LKAICore` 的型別，不可行。
- 要求 App 分別 import 各模組：使用端需要知道內部模組切分，之後調整切分會影響所有 App，否決。

### 非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭

- 適用範圍：source target 宣告的頂層型別。巢狀型別與測試 target 的型別不受前綴限制；測試型別跟隨受測型別命名（例如 `LKAIKitInfoTests`、`LKAICommandTests`），沒有受測型別的 `ExportsTests` 跟隨來源檔 `Exports.swift` 命名。
- 模組名稱為 `LKAI<名稱>`（`LKAICore`、`LKAIKit`，之後的 `LKAIOpenAI` 等）。
- 非供應商 target（`LKAICore`、`LKAIKit`、`LKAIKitCLI`）的頂層型別用 `LKAI<名稱>`；供應商 target 的頂層型別用 `LK<供應商><名稱>`，例如 `LKOpenAIClient`、`LKAnthropicClient`、`LKGeminiClient`。
- 不得宣告與任何模組同名的型別（例如 `LKAIKit`、`LKAICore`、`LKAIOpenAI`），否則以模組名稱限定的寫法會失效。
- 不在 `public` 層級擴充非本 package 的型別（例如對 `Data`、`String`、`URLRequest` 加 extension）；`package` 層級的這類擴充只允許寫在 `LKAICore`。
- 不宣告 `public` 或 `package` 層級的頂層函式；需要共用的函式依 ios-dev-kit 收進不含 case 的 enum。
- 本 change 的 `LKAIKitInfo` 與 `LKAICommand` 符合以上規則。
- 以上規則已寫入 `docs/spectra/config.yaml` 專案說明的「命名規則」，之後每個 change 產生文件時都會讀到；本決定記錄規則的理由。

理由：

- `@_exported` 會把所有供應商的公開名稱併進 `import LKAIKit` 的同一個命名空間。兩家供應商各自宣告同名的公開型別或 `public` extension 時，package 內全部編得過（供應商互不 import、總成沒有程式碼），要到 App 使用該名稱時才出現 ambiguous 錯誤；target 依賴只能隔離依賴，隔離不了名稱。
- `package` 成員 App 看不到，撞名只會發生在 package 內，而且是當場的編譯錯誤，不會漏到使用端；所以 `package` 層級不全面禁止，只限定寫在 `LKAICore` 這個單一定義點，避免各供應商重複定義相同的 helper。之後共用的 HTTP 傳輸與 SSE 解析可以寫成 `LKAICore` 裡對 `URLRequest`、`Data` 的 `package` extension。
- LeoKit 已有 47 個 `LK<名稱>` 公開型別。App 同時引用 LeoKit 與 LKAIKit 時，`LKAI` 與 `LK<供應商>` 前綴都與 LeoKit 現有名稱不重疊；若共用型別也用 `LK<一般名詞>`，就只能靠人工對照避免撞名。
- 使用者在「全部用 `LKAI` 開頭」與「共用 `LKAI`、供應商 `LK<供應商>`」之間選擇後者：供應商型別名稱較短，代價是兩層前綴不一致。

這個決定偏離 ios-dev-kit `coding-style.md`「避免型別名前綴」的規則，依據是專案說明規定的 `LK` 固定前綴。

考慮過的替代方案：

- 全部用 `LKAI` 開頭（供應商型別為 `LKAI<供應商><名稱>`）：前綴一致，但名稱較長，使用者未採用。
- 維持 `LK<名稱>`，新增型別時人工對照 LeoKit：名稱最短，但無法機械式避免撞名，使用者未採用。

### 宣告 swift-tools-version 6.2 並以 .v26 指定 iOS 26 與 macOS 26

- Supersedes：原決策「宣告 swift-tools-version 6.0 並以字串指定 iOS 26.0 與 macOS 26.0」。任務 1.1 依原決策以 6.0 加字串平台完成；2026-11-21 apply 後期，使用者直接把 `Package.swift` 改為 `swift-tools-version: 6.2` 與 `.iOS(.v26)`、`.macOS(.v26)`，經詢問後決定保留，由任務 6.1 記錄這次取代並重跑受影響的驗收。
- `Package.swift` 宣告 `// swift-tools-version: 6.2` 與 `swiftLanguageModes: [.v6]`，平台寫成 `platforms: [.iOS(.v26), .macOS(.v26)]`；只適用於 6.0 的字串平台說明註解一併刪除。
- `.v26` 是 PackageDescription 的列舉值，打錯時 manifest 編譯就會失敗，取代了原本「字串形式的平台版本打錯時，編譯期不會報錯」的風險。
- 代價：解析這個 package 需要 Swift 6.2 以上的工具。支援 iOS 26 的 App 本來就要用 Xcode 26，而 Xcode 26 內建 Swift 6.2，所以預期不會對使用端增加限制；這是推論，BuyLedger 開始整合時確認。
- 這個決定偏離 ios-dev-kit `project-structure.md`「`Package.swift` 固定 `swift-tools-version: 6.0`」，經使用者同意，列入 Risks 的偏離清單。

考慮過的替代方案：維持 `swift-tools-version: 6.0`，並以 `.iOS("26.0")`、`.macOS("26.0")` 字串宣告（原決策）。這符合 ios-dev-kit，但平台值打錯時只能靠 `dump-package` 驗收發現；使用者選擇保留 6.2。

### 每個 target 與其來源、測試在同一步加入 manifest

manifest 隨 target 逐步長大：宣告一個 target 時，同一步建立它的來源檔與對應的測試 target，不預先宣告還沒有來源目錄的 target（`Sources/` 已存在時，實測會讓 `swift build` / `swift test` 在載入 package 時失敗；`Sources/` 不存在時的例外見 Context）。本 change 依序加入 `LKAICore`、`LKAIKit`、`LKAIKitCLI`，各自連同測試 target；之後新增供應商也照這個順序：先建 target 與測試，再接進 `LKAIKit` 總成與 `Exports.swift`。

考慮過的替代方案：一開始就宣告全部 target，再補佔位檔。佔位檔不符樣板與 `///` 規則，且容易殘留，否決。

### CLI 以 swift-argument-parser 建立 lkai 根指令

- executable product 名稱 `lkai`，target 名稱 `LKAIKitCLI`，根指令型別 `LKAICommand`，標 `@main`。
- `LKAICommand` 採用 `AsyncParsableCommand`：async/await 是唯一的非同步模型，之後的子指令會呼叫網路 API；根指令先用 async 版本，加入 async 子指令時就不必更換根指令的協定。
- 本 change 不實作 `run()`，沿用 swift-argument-parser 的預設行為（印出說明）。
- 依賴宣告為 `.package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")`，允許 1.x 的更新、不自動升到 2.0。

考慮過的替代方案：手寫參數解析、不引入外部依賴。加入子指令時多半要改用 ArgumentParser 重寫入口，使用者未採用。

### 版本資訊集中於 LKAICore 的 LKAIKitInfo.version

- 在 `LKAICore` 宣告 `public enum LKAIKitInfo`（不含 case 的命名空間），提供 `public static let version: String`，初始值 `"0.1.0"`。這屬於 ios-dev-kit 允許 `static` 的字面值常數。
- 放在 `LKAICore`，是因為所有供應商都依賴它，之後送出的 HTTP 請求（例如 User-Agent）可直接引用同一個值。
- `LKAICommand` 的 `--version` 直接讀取 `LKAIKitInfo.version`，不另存版本字串。
- 版本格式固定為 `MAJOR.MINOR.PATCH`，三段皆為不含前導零的非負整數，不加 `v` 前綴。
- 發佈時手動更新此值。手動同步 git tag 的做法，最晚要在打第一個 release tag 之前另開 change 處理。

考慮過的替代方案：

- 只在 CLI 的指令設定中寫版本：供應商 target 無法取用，日後會出現第二個版本來源，否決。
- 以 build plugin 從 git tag 產生版本：增加建置複雜度，且 tag 同步屬於 release 流程，否決。

### 測試採 Swift Testing 並依受測 target 分成三個測試 target

| 測試 target | 依賴 | 驗證內容 |
| --- | --- | --- |
| `LKAICoreTests` | `LKAICore` | `LKAIKitInfo.version` 符合 `MAJOR.MINOR.PATCH` 格式 |
| `LKAIKitTests` | `LKAIKit` | 只寫 `import LKAIKit` 就能使用 `LKAIKitInfo`（重新匯出） |
| `LKAIKitCLITests` | `LKAIKitCLI`、`LKAIKit`、`ArgumentParser` | 以 `@testable import LKAIKitCLI` 呼叫 `LKAICommand.parseAsRoot(_:)`；不帶參數與說明類輸入再執行解析出的指令的 `run()`。以 `fullMessage(for:)`、`exitCode(for:)` 驗證不帶參數、說明、版本與錯誤輸入：usage 以整行比對，錯誤輸入比對訊息第一行；另以 `Process` 執行建置出的 `lkai`，分開比對 stdout、stderr 與退出碼 |

- 測試檔直接 import 的模組都要列為該測試 target 的依賴，不依賴遞移依賴碰巧可見。
- 三個測試 target 都以 `swift test` 在 macOS 執行；CLI 測試只能在 macOS 執行。
- iOS 只驗證能建置：以 XcodeBuildMCP 指定 `.swiftpm/xcode/package.xcworkspace`，對 iOS 26 模擬器建置 `LKAIKit` scheme；執行前先查 session defaults。

### 以行程層級測試驗證 lkai 的輸出分流

- CLI 的 stdout、stderr 與退出碼是給 CI 讀的輸出，屬於要寫測試的範圍。`fullMessage(for:)` 與 `exitCode(for:)` 分辨不出輸出印到哪一條串流，也不含結尾換行，所以在 `LKAICommandTests` 另加以 `Process` 執行建置出的 `lkai` 的測試。
- 執行檔從測試 bundle（`LKAIKitCLITests.xctest`）所在的資料夾取得，`swift test` 會把 `lkai` 建置在同一個資料夾（見 Context 的 apply 期間補充）。找不到執行檔時測試要失敗並說明原因，不得略過。
- stdout 與 stderr 各接一條 `Pipe` 分開讀取；輸出只有幾行，執行結束後循序讀取即可，不使用 GCD。
- 比對六種輸入：
  - 不帶參數、`--help`、`-h`：stdout 有一行剛好是 `USAGE: lkai`，且含 `--version`；stderr 為空；退出碼 0。
  - `--version`：stdout 剛好是 `LKAIKitInfo.version` 加一個換行；stderr 為空；退出碼 0。
  - `--bogus`、`foo`：stderr 第一行為 spec Example 的值；stdout 為空；退出碼 64。
- 測試放在既有的 `LKAICommandTests.swift`：受測的仍是 `LKAICommand` 的行為，依命名規則跟隨受測型別，不另開檔案。
- `LKAIKitCLITests` 只在 macOS 執行（`Process` 在 iOS 不可用），不加 `#if os(macOS)`。

考慮過的替代方案：

- 維持只在端對端驗收時人工確認：verify 指出 CLI 輸出給 CI 讀，依測試範圍的規則仍該有測試，使用者選擇補測試。
- 以 `#filePath` 推出 package 根目錄，再找 `.build/debug/lkai`：以 `--build-path` 或 `--scratch-path` 改變建置位置時會找錯檔案，否決。

### 只有測試檔使用 ios-dev-kit 樣板

ios-dev-kit 的樣板選擇表中，本 change 只有單元測試對得上樣板。`file-templates.md` 規定「表中沒有的型別先不建樣板，等實際專案出現該型別再補」；依這條規則，現在正是應該為「不含 case 的命名空間 enum」與 CLI 指令補樣板的時候。但補樣板要修改使用者的 ios-dev-kit，不在本 change 範圍。經使用者同意，本 change 依下表手寫沒有樣板的檔案，並記為偏離 ios-dev-kit 鐵則 1（新檔案一律從樣板複製、不得手寫骨架）：

| 檔案 | 建立方式 |
| --- | --- |
| `Tests/LKAICoreTests/LKAIKitInfoTests.swift` | `tests/Tests.swift` 樣板 |
| `Tests/LKAIKitCLITests/LKAICommandTests.swift` | `tests/Tests.swift` 樣板 |
| `Tests/LKAIKitTests/ExportsTests.swift` | `tests/Tests.swift` 樣板，但移除樣板的 `@testable import`；沒有受測型別，檔名對應來源檔 `Exports.swift` |
| `Sources/LKAICore/LKAIKitInfo.swift` | 無樣板（`domain/Enum.swift` 是含 case 與 raw value 的列舉，不適用），依 `file-templates.md` 檔頭規則、`formatting.md` 與 `coding-style.md` 手寫 |
| `Sources/LKAIKit/Exports.swift` | 無樣板，依檔頭規則手寫，只含重新匯出與說明註解 |
| `Sources/LKAIKitCLI/LKAICommand.swift` | 無樣板，依檔頭規則、`formatting.md` 與 `coding-style.md` 手寫 |
| `Package.swift` | 無樣板，依 ios-dev-kit `project-structure.md` 的 package 規則手寫 |

檔頭的 target 名稱寫該檔所屬的 target（例如 `LKAICore`、`LKAICoreTests`）。是否回頭為 ios-dev-kit 補上「不含 case 的命名空間 enum」與 CLI 指令的樣板，由使用者另行決定。

### 提交 package workspace 檔與 Package.resolved

- 提交 `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`，內容與 Xcode 開啟 package 時產生的相同（一個指向 `self:` 的 `FileRef`）。XcodeBuildMCP 需要這個檔案才能對純 package 建置，提交後任何 clone 都能直接驗證 iOS 建置。
- `.gitignore` 不新增 `.swiftpm/` 的排除規則：使用者資料已由既有的 `xcuserdata/` 規則排除；之後需要提交共用 scheme（`.swiftpm/xcode/xcshareddata/xcschemes/`）時，也不必另外放行。
- 提交 `Package.resolved`，固定 CI 建置時的 swift-argument-parser 版本。SwiftPM 解析依賴時只採用根 package 的 `Package.resolved`，App 引用 LKAIKit 時不受這個檔案影響。

考慮過的替代方案：`.gitignore` 排除 `.swiftpm/`，需要時再在本機產生 workspace 檔。每個 clone 都要手動產生才能驗證 iOS 建置，否決。

## Implementation Contract

**行為（使用端可觀察）：**

- App 依賴 `LKAIKit` product 並 `import LKAIKit` 後，可讀取 `LKAIKitInfo.version`，取得 `"0.1.0"`。
- `lkai` 不帶參數、帶 `--help` 或帶 `-h`：stdout 印出說明，內容包含 `USAGE: lkai` 與 `--version` 選項，stderr 無輸出，以 0 結束。
- `lkai --version`：stdout 只印出 `0.1.0` 一行，以 0 結束。
- `lkai` 帶未定義的輸入：stderr 印出點名該輸入的錯誤與使用提示，stdout 無輸出，以 64 結束。未知選項 `--bogus` 的第一行為 `Error: Unknown option '--bogus'`，多餘引數 `foo` 的第一行為 `Error: Unexpected argument 'foo'`。

**介面與資料形狀：**

- package 名稱 `LKAIKit`；`swift-tools-version: 6.2`；平台 `.iOS(.v26)`、`.macOS(.v26)`；`swiftLanguageModes: [.v6]`。
- products：`.library(name: "LKAIKit", targets: ["LKAIKit"])`、`.executable(name: "lkai", targets: ["LKAIKitCLI"])`。
- targets 與依賴：

  | target | 類型 | 依賴 |
  | --- | --- | --- |
  | `LKAICore` | target | 無 |
  | `LKAIKit` | target | `LKAICore` |
  | `LKAIKitCLI` | executableTarget | `LKAIKit`、`ArgumentParser`（swift-argument-parser） |
  | `LKAICoreTests` | testTarget | `LKAICore` |
  | `LKAIKitTests` | testTarget | `LKAIKit` |
  | `LKAIKitCLITests` | testTarget | `LKAIKitCLI`、`LKAIKit`、`ArgumentParser`（swift-argument-parser） |

- `public enum LKAIKitInfo { public static let version: String }`。
- `struct LKAICommand: AsyncParsableCommand`，`configuration` 為 `CommandConfiguration(commandName: "lkai", abstract: "LKAIKit command-line tool for CI/CD workflows.", version: LKAIKitInfo.version)`。遵循可寫在獨立的 extension，`configuration` 以唯讀的 `static var` 計算屬性提供，語意與寫在型別宣告上相同；依據是 ios-dev-kit `formatting.md`「需要手寫實作的 protocol 在 extension 宣告遵循」與「static stored property 不放進 extension」。
- `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`：`Workspace version = "1.0"`，內含一個 `FileRef location = "self:"`。

**錯誤處理：** 參數錯誤全部交由 swift-argument-parser 處理（stderr 訊息、退出碼 64）；本 change 不定義自訂錯誤型別。

**驗收方式：**

- 先以 `swift package clean` 清除建置產物，再執行 `swift build` 與 `swift test`：在 macOS 建置成功、三個測試 target 全部通過，且這次完整重新編譯中 LKAIKit 自身的 target 沒有編譯警告。
- XcodeBuildMCP 以 `.swiftpm/xcode/package.xcworkspace` 執行 `list_schemes`，清單包含 `LKAIKit`；再對 iOS 26 模擬器建置 `LKAIKit` scheme 成功。
- 建置出的 `lkai` 執行不帶參數、`--help`、`-h`、`--version`、`--bogus`、`foo` 六種情況，stdout、stderr 與退出碼符合上方行為；`LKAICommandTests` 的行程層級測試在每次 `swift test` 自動驗證同樣六種情況。
- `swift package dump-package` 的輸出：平台為 iOS 26.0 與 macOS 26.0；各 target 依賴與上表一致；`LKAIKit` 與它可達的每個 target，每一個依賴都是本 package 宣告的 target。
- Swift 檔案符合 ios-dev-kit 鐵則（所有宣告有 `///`、無 `!` / `try!` / `as!`、MARK 分區正確），依「只有測試檔使用 ios-dev-kit 樣板」的表格建立，頂層型別名稱符合「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」。

**範圍：**

- 範圍內：`Package.swift`、`Package.resolved`、`.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`、上述三個 source target 與三個測試 target 的檔案。
- 範圍內：`docs/spectra/config.yaml`，已於規劃階段加入「命名規則」，隨本 change 一起提交。
- 範圍外：Non-Goals 列出的所有項目；`.gitignore` 不修改；CLI 不新增任何子指令或自訂選項。

## Risks / Trade-offs

- [`@_exported` 是底線開頭、未正式公開的屬性，未來 Swift 版本可能改變] → 只集中在 `LKAIKit/Exports.swift` 一個檔案，若 Swift 推出正式的重新匯出語法，只需替換這個檔案；`ExportsTests` 會在行為改變時編譯失敗。
- [App 解析依賴時仍會下載並鎖定 swift-argument-parser，且受 `from: "1.8.2"` 限制；1.8.2 是目前最新版，App 的其他依賴若把它限制在較舊版本就會解析衝突] → 已實測確認並由使用者接受。出現衝突時，先把下限調到實測可用的最低版本；仍無法解決時，改採獨立 CLI package 的方案另開 change。
- [package 內驗不到存取層級：測試 target 與 CLI 跟 library 同屬一個 package，看得到 `package` 成員。該 `public` 卻標成 `package` 時 package 內全部通過、只有 App 壞；多標 `public` 則沒有機制發現] → 公開 API 以 review 把關；BuyLedger 開始整合或第一個供應商加入時，再決定是否在 repo 放常駐的外部使用端 fixture package。
- [`swift-tools-version: 6.2` 要求使用端以 Swift 6.2 以上的工具解析 package] → 支援 iOS 26 的 App 本來就要用內建 Swift 6.2 的 Xcode 26，預期不增加限制（推論，未在使用端實測），BuyLedger 開始整合時確認。平台改用 `.v26` 列舉，打錯會在 manifest 編譯時失敗；驗收仍以 `swift package dump-package` 確認平台為 iOS 26.0 與 macOS 26.0。
- [CLI 測試無法在 iOS 執行，對 iOS 測試整個 `LKAIKit-Package` scheme 可能失敗] → 測試一律以 `swift test` 在 macOS 執行，iOS 只建置 `LKAIKit` scheme。之後要在 iOS 跑 `LKAICoreTests` 或供應商測試時（出現平台差異程式碼），再於 `.swiftpm/xcode/xcshareddata/xcschemes/` 建立排除 `LKAIKitCLITests` 的共用 scheme。
- [spec 的 Example、tasks 的驗收與 CLI 測試都逐字比對 swift-argument-parser 的錯誤措辭] → 升級 swift-argument-parser 的 minor 版時，三處一起檢查。stdout 與 stderr 的分流由 `LKAICommandTests` 的行程層級測試自動驗證。
- [import 層級的依賴方向沒有機械把關：SwiftPM 允許 target import 只經間接依賴可見的模組，`swift package dump-package` 也只驗得到 manifest。實測 `LKAIKitCLI` 直接 import `LKAICore` 能建置成功；`ExportsTests` 補上 `import LKAICore` 也可能編得過（未實測），這時它就測不到漏寫的重新匯出] → review 時逐檔檢查 import；`ExportsTests` 的 `///` 寫明不得 import `LKAICore` 或供應商模組。SwiftPM 日後提供能擋下這種 import 的檢查時，再加入驗收。
- [多 target 讓存取控制變複雜，可能誤把內部成員標成 `public`] → 給 App 使用的 API 才標 `public`，package 內共用標 `package`；之後供應商的 change 在 review 時檢查公開介面。
- [模組切分尚未經供應商實際驗證：「新增供應商不需更動 LKAICore」目前是設計意圖，不是已驗證的結果] → 共用抽象與第一個供應商落地前，不打 release tag 讓 App 釘版本。
- [版本號需手動與 git tag 同步，可能忘記更新] → 列入 Non-Goals，最晚在第一個 release tag 之前另開 change 處理。
- [偏離 ios-dev-kit 的四條規則：「一個 package 一個 library target」、「避免型別名前綴」、鐵則 1「新檔案一律從樣板複製」與「`Package.swift` 固定 `swift-tools-version: 6.0`」] → 四者都經使用者同意，理由分別記錄在「採用多 target 分層：LKAICore、LKAIKit 總成與 LKAIKitCLI」、「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」、「只有測試檔使用 ios-dev-kit 樣板」與「宣告 swift-tools-version 6.2 並以 .v26 指定 iOS 26 與 macOS 26」；之後以 ios-dev-kit 做 code review 時，這四點不列為違規。

## Open Questions

以下問題不影響本 change，留給設計供應商共用抽象的 change 決定：

- 需要同時認識多家供應商的組裝邏輯（依設定選擇供應商、跨供應商 fallback），在目前的依賴方向下只有總成放得下，但總成定為不放實作。屆時要決定放寬總成，或新增一個組裝 target；不得用字串 key 或讓供應商互相依賴來繞過。兩個選項的成本不同：新增組裝 target 違反 spec「Module dependency direction」的「其餘 library target 只依賴 `LKAICore`」，需要 MODIFY 該需求；放寬總成只需修改本 design，因為「總成不放實作」沒有寫進 spec。
- 供應商只能依賴 `LKAICore`，所以共用的 HTTP 傳輸與 SSE 解析只能放進 `LKAICore`（標 `package`），`LKAICore` 會同時是給 App 的公開模型與內部基礎設施；各供應商的測試 target 要共用測試替身時，也需要一個不對外的支援 target。兩者要一併決定。
- 讓外部型別遵循本 package 自己定義的 `public` protocol（例如 `extension String: LKAIMessageContent`）算不算命名規則禁止的「在 `public` 層級擴充非本 package 的型別」。protocol 是本 package 的，不會與其他套件撞名，但遵循本身對 App 可見；屆時依實際的 protocol 決定是否允許，以及只能寫在哪個 target，再同步更新 `docs/spectra/config.yaml` 的命名規則。
