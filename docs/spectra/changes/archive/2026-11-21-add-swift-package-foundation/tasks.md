## 1. LKAICore 與 package manifest

- [x] 1.1 交付 Package version information 與 manifest 基礎：依「每個 target 與其來源、測試在同一步加入 manifest」建立 `Package.swift`，依「宣告 swift-tools-version 6.0 並以字串指定 iOS 26.0 與 macOS 26.0」設定工具版本、`swiftLanguageModes: [.v6]` 與平台，這一步只宣告 `LKAICore` 與 `LKAICoreTests`。先依「只有測試檔使用 ios-dev-kit 樣板」以 `tests/Tests.swift` 樣板建立 `Tests/LKAICoreTests/LKAIKitInfoTests.swift`，以 Swift Testing 驗證 `LKAIKitInfo.version` 符合 `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`，確認測試在實作前因 `Sources/LKAICore` 不存在、package 載入失敗而無法通過；再依「版本資訊集中於 LKAICore 的 LKAIKitInfo.version」手寫 `Sources/LKAICore/LKAIKitInfo.swift`，宣告 `public enum LKAIKitInfo` 與 `public static let version: String = "0.1.0"`。驗證：`swift test --filter LKAICoreTests` 通過，且這次編譯 `LKAICore` 與 `LKAICoreTests` 沒有警告；`swift package dump-package` 的平台為 iOS 26.0 與 macOS 26.0（Library product for app integration 的平台宣告）；對照 ios-dev-kit 鐵則與「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」自檢程式碼與檔頭。
  - 實測紀錄：實作前的失敗為 `LKAIKitInfoTests.swift` 編譯時出現 `unable to resolve module dependency: 'LKAICore'`；當時 repo 還沒有 `Sources/` 目錄，缺少來源目錄只出現警告，而不是在載入 package 時失敗（見 design Context 的 apply 期間補充）。
- [x] 1.2 [after: 1.1] 依「提交 package workspace 檔與 Package.resolved」建立 `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`，內容為 design「Implementation Contract」所列、指向 `self:` 的 workspace，讓 XcodeBuildMCP 能辨識這個純 package。驗證：檔案內容與 design 所列一致（`Workspace version = "1.0"`，內含一個 `FileRef location = "self:"`）；`git check-ignore -q .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata` 回傳非 0（未被忽略）。

## 2. LKAIKit 總成與單一 import 入口

- [x] 2.1 [after: 1.2] 交付 Single import entry point：依「對外只提供 LKAIKit 一個 library product」在 manifest 加入 `LKAIKit` target、`LKAIKit` library product 與 `LKAIKitTests`。先以 `tests/Tests.swift` 樣板建立 `Tests/LKAIKitTests/ExportsTests.swift`：移除樣板的 `@testable import`，只寫 `import LKAIKit`、不 import `LKAICore`，並讀取 `LKAIKitInfo.version`；同時建立只有檔頭與說明註解、尚未加入重新匯出的 `Sources/LKAIKit/Exports.swift`，確認 `swift test --filter LKAIKitTests` 因 `cannot find 'LKAIKitInfo' in scope` 編譯失敗，證明測試擋得住漏寫重新匯出。再依「以 @_exported import 讓 App 只需 import LKAIKit」在 `Exports.swift` 加入 `@_exported import LKAICore`。驗證：`swift test --filter LKAIKitTests` 通過，且這次編譯 `LKAIKit` 與 `LKAIKitTests` 沒有警告；`swift package dump-package` 中 `LKAIKit` 只依賴 `LKAICore`；對照 ios-dev-kit 鐵則與「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」自檢程式碼與檔頭。

## 3. lkai 根指令

- [x] 3.1 [after: 2.1] 交付 Executable product for CI/CD 的不帶參數行為、Help output、Version output 與 Invalid input rejection：依「CLI 與 library 維持在同一個 package」在同一個 manifest 加入 swift-argument-parser 依賴（`from: "1.8.2"`）、`LKAIKitCLI` executableTarget、`lkai` executable product，以及依賴 `LKAIKitCLI`、`LKAIKit`、`ArgumentParser` 的 `LKAIKitCLITests`。先以 `tests/Tests.swift` 樣板建立 `Tests/LKAIKitCLITests/LKAICommandTests.swift`，以 `@testable import LKAIKitCLI` 呼叫 `LKAICommand.parseAsRoot(_:)`，再用 `fullMessage(for:)` 與 `exitCode(for:)` 驗證五件事：
  - 不帶參數時，`parseAsRoot([])` 取得的指令執行 `run()` 會拋出說明請求，訊息包含 `USAGE: lkai`，退出碼為 `.success`。
  - `--help` 與 `-h` 的訊息包含 `USAGE: lkai` 與 `--version`，退出碼為 `.success`。
  - `--version` 的訊息等於 `LKAIKitInfo.version`，退出碼為 `.success`。
  - `--bogus` 的訊息包含 `Unknown option '--bogus'`，退出碼為 `.validationFailure`。
  - `foo` 的訊息包含 `Unexpected argument 'foo'`，退出碼為 `.validationFailure`。

  確認測試在實作前因 `Sources/LKAIKitCLI` 不存在、package 載入失敗而無法通過後，依「CLI 以 swift-argument-parser 建立 lkai 根指令」手寫 `Sources/LKAIKitCLI/LKAICommand.swift`，宣告 `@main struct LKAICommand: AsyncParsableCommand`，`configuration` 依 design 的 `CommandConfiguration` 設定，不實作 `run()`。驗證：`swift test --filter LKAIKitCLITests` 通過，且這次編譯 `LKAIKitCLI` 與 `LKAIKitCLITests` 沒有警告；產生的 `Package.resolved` 內含 swift-argument-parser，版本號為 1.8.2 以上、2.0.0 以下；對照 ios-dev-kit 鐵則與「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」自檢程式碼與檔頭。

## 4. 整體驗收

- [x] 4.1 [after: 3.1] 依「採用多 target 分層：LKAICore、LKAIKit 總成與 LKAIKitCLI」，以 `swift package dump-package` 驗證完整 manifest，交付 Module dependency direction 與 Library free of external package dependencies。驗證：平台為 iOS 26.0 與 macOS 26.0；六個 target 的依賴與 design「Implementation Contract」的 target 表一致；`LKAICore` 的依賴為空；`LKAIKit` 與它可達的每個 target，每一個依賴都是本 package 宣告的 target；`LKAIKitCLI` 在本 package 內只依賴 `LKAIKit`。
  - spectra-exclude: package-distribution / Inspect the declared minimum platforms | manifest 宣告的平台只能由 `swift package dump-package` 觀察，專案的單元測試環境讀不到 manifest；由本任務的 dump-package 檢查驗證，沒有自動化測試持續把關
  - spectra-exclude: package-distribution / Inspect the library build graph | target 依賴圖只能由 `swift package dump-package` 觀察，專案的單元測試環境讀不到 manifest；由本任務的 dump-package 檢查驗證，沒有自動化測試持續把關
  - spectra-exclude: package-distribution / Inspect target dependency direction | target 依賴方向只能由 `swift package dump-package` 觀察，專案的單元測試環境讀不到 manifest；由本任務的 dump-package 檢查驗證，沒有自動化測試持續把關
- [x] 4.2 [after: 4.1] 依「測試採 Swift Testing 並依受測 target 分成三個測試 target」，在 macOS 先執行 `swift package clean` 清除建置產物，再執行 `swift build` 與完整的 `swift test`，交付 Library product for app integration 的 macOS 建置情境。驗證：建置成功；`LKAICoreTests`、`LKAIKitTests`、`LKAIKitCLITests` 三個測試 target 的測試全部通過；這次完整重新編譯中，LKAIKit 自身的 target（`LKAICore`、`LKAIKit`、`LKAIKitCLI` 與三個測試 target）沒有編譯警告。
  - spectra-exclude: package-distribution / Build the library for macOS | 建置成功與否由 `swift build` 本身判定，單元測試以建置成功為前提、無法另外觀察；由本任務在 `swift package clean` 後執行 `swift build` 驗證
- [x] 4.3 [after: 4.1] 以 XcodeBuildMCP 對 iOS 26 模擬器建置 `LKAIKit` scheme，交付 Library product for app integration 的 iOS 建置情境：先以 `session_show_defaults` 查看 session defaults，以 `list_schemes` 指定 `.swiftpm/xcode/package.xcworkspace` 確認清單包含 `LKAIKit`，再把 `workspacePath` 設為該 workspace、`scheme` 設為 `LKAIKit`，並選定 iOS 26 模擬器。驗證：`list_schemes` 的清單包含 `LKAIKit`；`build_sim` 回報建置成功，沒有錯誤。
  - spectra-exclude: package-distribution / Build the library for an iOS simulator | iOS 建置成功與否由建置工具判定，`swift test` 只在 macOS 執行、觀察不到 iOS 建置；由本任務以 XcodeBuildMCP `build_sim` 驗證，沒有自動化測試持續把關
- [x] 4.4 [after: 4.2] 執行 4.2 建置出的 `lkai` 執行檔，交付 Executable product for CI/CD、Help output、Version output 與 Invalid input rejection 的端對端行為。驗證：逐一比對 stdout、stderr 與退出碼——不帶參數、`--help`、`-h` 時 stdout 含 `USAGE: lkai` 與 `--version`、stderr 為空，以 0 結束；`--version` 時 stdout 只有 `0.1.0` 一行，以 0 結束；`--bogus` 與 `foo` 時 stderr 第一行分別為 `Error: Unknown option '--bogus'` 與 `Error: Unexpected argument 'foo'`，stdout 為空，以 64 結束。
- [x] 4.5 確認 `docs/spectra/config.yaml` 的專案說明包含「命名規則」一節，內容與 design「非供應商型別以 LKAI 開頭，供應商型別以 LK 加供應商名開頭」一致，並與本 change 的其他檔案一起提交。驗證：內容審查 `docs/spectra/config.yaml`，逐條比對模組名稱、頂層型別前綴、巢狀與測試型別的例外、不得與模組同名、`public` 與 `package` 層級的擴充限制，以及頂層函式的限制；`spectra instructions proposal --change "add-swift-package-foundation" --json` 回傳的 `context` 含有「命名規則」。

## 5. 行程層級的 CLI 輸出測試

- [x] 5.1 [after: 4.4] 依「以行程層級測試驗證 lkai 的輸出分流」，在 `Tests/LKAIKitCLITests/LKAICommandTests.swift` 加入以 `Process` 執行建置出的 `lkai` 的測試：從測試 bundle（`LKAIKitCLITests.xctest`）所在資料夾取得執行檔，找不到時以 `try #require` 讓測試失敗；stdout 與 stderr 各接一條 `Pipe` 分開讀取。逐一比對六種輸入：
  - 不帶參數、`--help`、`-h`：stdout 有一行剛好是 `USAGE: lkai`，且含 `--version`；stderr 為空；退出碼 0。
  - `--version`：stdout 剛好是 `LKAIKitInfo.version` 加一個換行；stderr 為空；退出碼 0。
  - `--bogus`、`foo`：stderr 第一行分別為 `Error: Unknown option '--bogus'` 與 `Error: Unexpected argument 'foo'`；stdout 為空；退出碼 64。

  每個測試上方加上它對應的 scenario 與 example 的 `spectra-scenario` 標記。行為已由 3.1 實作，新測試預期一寫好就通過，因此改以破壞實驗確認它擋得住回歸：主對話在 scratchpad 的副本中分別做兩件事——刪除 `commandName`，以及讓不帶參數時的說明改印到 stderr（例如實作一個把 `helpMessage()` 寫到 standardError 的 `run()`）——新測試都要失敗。驗證：`swift test --filter LKAIKitCLITests` 通過，且這次編譯 `LKAIKitCLITests` 沒有警告；完整的 `swift test` 通過；兩個破壞實驗中新測試都失敗；對照 ios-dev-kit 鐵則自檢（所有宣告有 `///`、禁止 `!` / `try!` / `as!`、不使用 GCD）。

## 6. 改用 swift-tools-version 6.2

- [x] 6.1 [after: 5.1] 依「宣告 swift-tools-version 6.2 並以 .v26 指定 iOS 26 與 macOS 26」（取代 1.1 所依據的 6.0 決策），`Package.swift` 改為 `// swift-tools-version: 6.2` 與 `platforms: [.iOS(.v26), .macOS(.v26)]`，並刪除只適用於 6.0 的字串平台說明註解；這些修改使用者已於 2026-11-21 19:15 直接完成。本任務另依 ios-dev-kit `formatting.md`「多行陣列、字典字面值的最後一個元素後面一律加逗號」，補回 `dependencies` 陣列最後一個元素的尾隨逗號，並重跑受 manifest 變更影響的驗收。驗證：`swift package dump-package` 的 toolsVersion 為 6.2.0、平台為 iOS 26.0 與 macOS 26.0、六個 target 的依賴與 design 的 target 表一致；`swift package clean` 後 `swift build` 與完整 `swift test` 通過，且這次完整重新編譯中 LKAIKit 自身的 target 沒有警告；XcodeBuildMCP 對 iOS 26 模擬器建置 `LKAIKit` scheme 成功；建置出的 `lkai` 六種輸入的 stdout、stderr 與退出碼符合 spec。
