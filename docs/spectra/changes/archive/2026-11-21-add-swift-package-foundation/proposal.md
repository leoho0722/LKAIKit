## Why

LKAIKit 目前只有授權檔與 Spectra 設定，沒有可編譯的 Swift Package：BuyLedger 等 iOS App 無法引用，CI/CD 也沒有可執行的工具入口。之後 OpenAI GPT、Anthropic Claude、Google Gemini 等供應商會逐一加入，必須先定好模組結構、依賴方向與命名規則，才能讓各供應商的實作互不耦合、長期可維護。

## What Changes

- 新增 `Package.swift`：`swift-tools-version: 6.2`、Swift 6 語言模式，支援平台以 `.iOS(.v26)`、`.macOS(.v26)` 宣告為 iOS 26.0+ 與 macOS 26.0+。
- 新增 `LKAICore` target：放各供應商共用的抽象；本次只提供套件版本資訊 `LKAIKitInfo.version`，供 CLI 與日後的 HTTP 請求共用同一個版本來源。
- 新增 `LKAIKit` target 與同名 library product：App 專案唯一的引用入口，重新匯出它依賴的所有 library target，App 只需 `import LKAIKit`。
- 新增 `LKAIKitCLI` executableTarget 與 `lkai` executable product：以 swift-argument-parser 建立根指令，提供 `--version`、`--help` 與 `-h`；子指令留待之後的 change。
- 新增 `LKAICoreTests`、`LKAIKitTests`、`LKAIKitCLITests` 三個以 Swift Testing 撰寫的測試 target。
- 新增外部依賴 swift-argument-parser，只有 `LKAIKitCLI` 與其測試使用；library product 的建置範圍不含任何外部套件。
- 確立之後新增供應商時的固定規範：模組依賴方向寫進 spec；命名規則（非供應商型別 `LKAI<名稱>`、供應商型別 `LK<供應商><名稱>`）寫進 `docs/spectra/config.yaml` 的專案說明。
- 提交 package workspace 檔，讓 XcodeBuildMCP 能在任何 clone 上對 iOS 模擬器建置 library。

## Capabilities

### New Capabilities

- `package-distribution`：`LKAIKit` library product 的平台支援、單一 import 入口、版本資訊、模組依賴方向，以及 library 建置範圍不含外部套件的保證
- `cli-root-command`：`lkai` executable 根指令的行為，包含說明輸出、版本輸出與無效輸入的錯誤處理

### Modified Capabilities

無

## Impact

- 新增檔案：`Package.swift`、`Package.resolved`、`.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`、`Sources/LKAICore/`、`Sources/LKAIKit/`、`Sources/LKAIKitCLI/`、`Tests/LKAICoreTests/`、`Tests/LKAIKitTests/`、`Tests/LKAIKitCLITests/`
- 新增依賴：swift-argument-parser（`from: "1.8.2"`，即 1.8.2 以上、2.0.0 以下）
- 使用端：BuyLedger 等 App 之後可依賴 `LKAIKit` library product，建置時不會編譯 swift-argument-parser；但依賴解析時仍會下載它、寫進 App 的 `Package.resolved`，並受上述版本範圍限制；manifest 宣告 `swift-tools-version: 6.2`，解析時需要 Swift 6.2 以上的工具
- CI/CD：可透過 `lkai` executable 執行工具指令
- 既有檔案：實作階段無變更；`.gitignore` 已排除 `.build/` 與 `xcuserdata/`，不排除 `.swiftpm/`。`docs/spectra/config.yaml` 已在規劃階段加入命名規則，隨本 change 一起提交
