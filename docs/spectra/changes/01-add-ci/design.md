## Context

**由來**：這個 change 原名 `add-ci-cd`，同時包含 CI 與自動發版。2026-11-24 由 fable（架構）與 opus（正確性）做規劃審查，兩人都沒有 Critical。使用者依審查建議拆成兩個 change：

- 本 change：CI 與 setup action。
- `02-add-release-automation`：發版 script、release workflow、tag 與版號一致的規則。

見決策「拆成 01-add-ci 與 02-add-release-automation」。拆分後的第二輪審查（2026-11-24）中，opus 認為本 change 沒有需要修正的項目；fable 建議把 action 的試跑移到單元測試之前，並讓 CI 的 requirement 不依賴 action 內部的路徑（見決策「CI 跑單元測試與 action 試跑」），也指出 required status check 會擋住之後的升版 commit（見 Migration Plan）。

**現況**（2026-11-23 查看，2026-11-24 由兩位審查者複查）：

- repo 沒有 `.github/`。GitHub 上是 public repo，`main` 沒有 branch protection（`gh api repos/leoho0722/LKAIKit/branches/main/protection` 回 404），rulesets 是空的。
- 需要真實 API Key 的 9 個測試函式都以 `.enabled(if:)` 判斷 `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`，沒有設定時略過。
- `config.yaml` 寫明 executableTarget（`lkai`）主要供 CI/CD 使用。

**查證結果**：

1. **Container action 只能在 Linux 執行，而 LKAIKit 目前無法在 Linux 建置**（2026-11-23）：
   - GitHub 文件：「Docker container actions can only execute on runners with a Linux operating system.」（About custom actions）
   - `LKAIHTTPClient` 以 `URLSession.bytes(for:)` 讀取回應，但 swift-corelibs-foundation 沒有 `URLSession.AsyncBytes`：
     - Swift Forums「AsyncBytes and AsyncLineSequence not available on Linux」、swift-http-types PR #58 都這樣寫。
     - Swift Package Index 在 2026 年 9 月以 Swift 6.4 建置 Linux 的紀錄仍出現「'AsyncBytes' is not a member type of class 'FoundationNetworking.URLSession'」。
2. **Runner**（2026-11-23；bash 的部分 2026-11-24 查證）：
   - `xcode-27` runner 於 2026-10-15 GA（GitHub Changelog），作業系統是 macOS 27.0.1，只有 Apple Silicon。
   - 安裝 Xcode 27.0、27.1（預設）與 27.2，bash 是 3.2.57（runner-images 的 `xcode-27-arm64` README，image 20261104.0337.1）。
   - `macos-26`（也是 `macos-latest`）安裝 Xcode 26.0.1 到 26.6，預設 26.6。
   - 程式碼用了 `@nonexhaustive`（SE-0487）。本機只有 Xcode 27.2（Swift 6.4.2），Xcode 26.x 與 Xcode 27.1 能不能編譯都沒有實測；27.1 由 PR 上的第一次 CI 確認（任務 2.2），退路見 Risks。
3. **測試與建置的實測**（2026-11-23，本機 M1、8 核、Xcode 27.2）：
   - 不設定任何 `LKAI_*` 環境變數執行 `swift test`：退出碼 0，7 個測試 target 共 270 個測試通過，9 個測試函式顯示為略過（library 三家各 2 個，CLI 三家各 1 個參數化函式）。增量建置後的執行時間 14 秒。
   - 在空的 scratch path 執行 `swift build -c release --product lkai`：21.7 秒。建置資料夾內有 `lkai`、`LKAIKit_LKAICore.bundle` 與 `LKAIKit_LKAIKitCLI.bundle`，`lkai --version` 印出 `0.1.0`。
   - runner 的標準 arm64 機器核心數較少，release 建置估計 1 到 2 分鐘。這是估計值，由任務 2.2 的 CI 紀錄確認。
   - 2026-11-24 實測：`swift build --show-bin-path` 印出 `.build/out/Products/Debug`，`swift build -c release --show-bin-path` 印出 `.build/out/Products/Release`。不加 `-c release` 時拿到的是 debug 的資料夾（opus 審查 W4）。
4. **GitHub Actions 的行為**（官方文件，2026-11-23）：
   - `github.action_path`：「only supported in composite actions」，「You can use this path to access files located in the same repository as the action」。
   - `paths-ignore` 文件：被略過的 required check 會停在 Pending，擋住要求這個 check 的 PR。
   - 同一個 concurrency group「at most one running job or workflow」，`cancel-in-progress: true` 時取消執行中的 run。
   - `uses:` 不接受運算式，所以 workflow 無法以 `${{ github.sha }}` 引用自己的 action。
   - `actions/checkout` 最新版是 v7.0.1（2026-07-20），tag 指向 commit `3d3c42e5aac5ba805825da76410c181273ba90b1`（`gh api repos/actions/checkout/git/ref/tags/v7.0.1`）。

**相關的既有決定**：

- `add-swift-package-foundation` 的 Non-Goals「CI 設定檔（例如 GitHub Actions workflow）」與 `add-cli-chat-command` 的 Non-Goals「發佈方式（release 執行檔、Homebrew）」：都只限制了那兩個 change 自己的範圍，這個 change 接手 CI 與 `lkai` 的取得方式。
- `docs/adding-a-provider.md` 第 7 章「`lkai` 要和 `LKAIKit_LKAICore.bundle`、`LKAIKit_LKAIKitCLI.bundle` 放在同一個資料夾」一列：
  - 要求發佈方式由之後的 change 決定，並以「把 `lkai` 複製到空資料夾後，`-v` 與一個服務錯誤的情境都正常」驗收。
  - 這個 change 不複製 `lkai`，見決策「lkai 留在 release 建置資料夾執行，不複製」。

## Goals / Non-Goals

**Goals:**

- 每個 PR 自動跑單元測試，不需要任何真實的 API Key。
- 這個 repo 與其他 repo 都能以一行 `uses:` 取得 `lkai`。
- 合併前就確定 runner 的工具鏈能建置這個 package。

**Non-Goals:**

- 自動發版（版號、tag、GitHub Release、Release Notes）：由 `02-add-release-automation` 處理。
- Linux 支援與 container action：要先移植 `LKAIHTTPClient` 的網路層，另開 change。
- 發佈 `lkai` 的執行檔（附在 release 上、Homebrew）。
- CI 的建置快取（`actions/cache`）：先看任務 2.2 的實測時間再決定。
- CI 建置 iOS simulator 版本：package-distribution 的「Build the library for an iOS simulator」仍由各 change 的驗收手動確認。
- 設定 branch protection 與 required status checks：由 owner 決定。
- 在 CI 執行 actionlint：只在實作時於本機執行（任務 2.1）。
- 修改 `lkai` 的行為。

## Decisions

### 拆成 01-add-ci 與 02-add-release-automation

- 本 change 只做 CI 與 setup action；發版的部分由 `02-add-release-automation` 處理，它依賴本 change 的 action 與 CI。
- 理由（fable 審查 W4，使用者 2026-11-24 同意）：
  - runner 預設的 Xcode 27.1 能不能編譯、建置要多久，會影響兩個 workflow。本 change 先合併，這些事實當天就確定。
  - CI 與 action 風險低、馬上有用。自動發版會建立對外無法收回的 tag，也需要推 commit 到 `main` 的權限。分開之後，可以只退其中一個。
  - `02-add-release-automation` 的 PR 也能先受到 CI 保護。
- 考慮過的替代方案：
  - 維持一個 change，只調整任務順序：回退時無法只退一半，不採用。
  - 拆成兩個，第二個分兩次合併（先只開手動觸發）：使用者選擇不分兩次。

### CI 在 xcode-27 runner 執行

- `runs-on: xcode-27`，用 image 預設的 Xcode（27.1），不另外選 Xcode。
- 理由：本機以 Xcode 27.2 開發，`@nonexhaustive` 等新語法在 Xcode 27 系列最有把握編譯；macOS 26 runner 只有 Xcode 26.x，能不能編譯沒有實測。
- 考慮過的替代方案：
  - `macos-latest`（目前指向 macOS 26）：會隨 GitHub 調整而改變，不採用。
  - `macos-26`：Xcode 26.x 的工具鏈較舊，不採用。

### Composite action 從 action 所在的原始碼建構 lkai，不採用 container action

- repo 根目錄的 `action.yml`，`runs.using: composite`，在 `github.action_path` 建構 release 版的 `lkai`。
- 這個 repo 以 `uses: ./` 使用，其他 repo 以 `uses: leoho0722/LKAIKit@main` 或某個 tag 使用，建構的就是那個 ref 的程式碼。
- action 不收 input，輸出 `path` 與 `version`。
- 理由：container action 只能在 Linux 執行，而 LKAIKit 依賴 Linux 沒有的 `URLSession.bytes(for:)`（Context 第 1 點）。composite action 在 macOS runner 上一樣能以 `uses:` 引用，達到「方便整合在 CD」的目的，也不用修改 library。
- 介面的擴充：之後改成下載預先建好的執行檔，或 Linux 支援後拿掉 macOS 的檢查，介面（沒有 input、輸出 `path` 與 `version`）都不必變。container action 會是「執行 `lkai`」型的介面，屬於另一個 capability，不是這個 action 的遷移（fable 審查的觀察）。
- 考慮過的替代方案：
  - container action：需要移植網路層與擴大支援平台，另開 change。
  - 只在 workflow 內執行 `swift build`、不包成 action：其他 repo 無法重用，不採用。
  - action 放在 `.github/actions/setup-lkai/`：引用時要寫 `leoho0722/LKAIKit/.github/actions/setup-lkai@main`，比根目錄的 `leoho0722/LKAIKit@main` 長；根目錄的 `action.yml` 不影響 SwiftPM，所以放根目錄。

### lkai 留在 release 建置資料夾執行，不複製

- action 以 `swift build -c release --product lkai --package-path <action 路徑>` 建置，再以同樣加上 `-c release` 的 `--show-bin-path` 取得資料夾，把它加進 `GITHUB_PATH`；`lkai` 與兩個 resource bundle 留在原處。
- 一定要加 `-c release`：不加時拿到的是 debug 的資料夾（Context 第 3 點）。CI 先跑 `swift test` 時 debug 的資料夾裡已有 `lkai`，試跑會誤以為正確；但在沒有先跑測試的 workflow 中，那個資料夾沒有 `lkai`，每次都會失敗（opus 審查 W4）。所以 CI 在任何建置之前先執行 action（決策「CI 跑單元測試與 action 試跑」）：乾淨的 checkout 沒有 debug 的 `lkai`，路徑錯時 action 自己執行的 `lkai -v` 就會失敗。
- 理由：`lkai` 每次執行都讀 `LKAIKit_LKAIKitCLI.bundle`，印服務錯誤時讀 `LKAIKit_LKAICore.bundle`；SwiftPM 產生的 `Bundle.module` 只在執行檔旁（`Bundle.main.resourceURL`、`Bundle.main.bundleURL`）尋找（`docs/adding-a-provider.md` 第 7 章，opus 審查時讀 `resource_bundle_accessor.swift` 確認）。不複製就不會少帶 bundle。
- 清單要求的驗收改成：從 action 加入的 `PATH`，在 package 以外的資料夾執行 `lkai -v`，以及一個服務錯誤（金鑰被拒絕）的情境，兩者都要正常（lkai-setup-action「Report a service failure when run from PATH」，任務 2.1）。
- `docs/adding-a-provider.md` 第 7 章這一列改寫為這個決定（任務 1.3）。

### action 只要求 macOS runner，不寫 runner 標籤

- 不在 macOS 上執行時，第一個 step 就失敗，訊息只說需要 macOS runner，不寫 `xcode-27` 等標籤。
- 理由：action 本身只依賴 macOS 與夠新的 Swift 工具鏈，不依賴標籤。runner 標籤每年都會換，這則訊息是給其他 repo 看的，標籤過期了也沒有人會發現（fable 審查 S10）。兩個 workflow 的 `runs-on` 仍寫 `xcode-27`。

### CI 跑單元測試與 action 試跑

- 一個 job，依序執行：
  1. 印出 `swift --version` 與 `bash --version` 的第一行，記錄 runner 的工具鏈。
  2. `uses: ./`。
  3. 在 `runner.temp` 執行 `lkai -v`，比對 action 的 `version` 輸出；並確認 `path` 輸出是可執行檔、最後一段是 `lkai`、以 `-v` 執行也印出同樣的版號（opus 第三輪審查 S1：其他 repo 可能直接用 `path`）。這幾項都不依賴檔案放在哪個資料夾。
  4. `swift test`。
- action 與試跑放在 `swift test` 之前（fable 第二輪審查 N7）：
  - action 在乾淨的 checkout 中執行，和 release workflow、其他 repo 的實際用法相同。取錯資料夾時，那個資料夾沒有 `lkai`，action 會自己失敗。
  - CI 的 requirement 規定 `lkai -v`、`version` 輸出與 `path` 輸出三者一致，`path` 是名為 `lkai` 的可執行檔，但不規定它在哪個資料夾。之後 action 改成下載預先建好的執行檔時，這條 requirement 不必改。
  - 代價：單元測試的結果晚一次 release 建置的時間才出來（估計 1 到 2 分鐘，Context 第 3 點）。
  - 考慮過的替代方案：維持 `swift test` 在前，另外比對 `path` 是否在 release 的資料夾。requirement 會依賴 action 的內部做法，不採用。
- 所有 PR 都執行，不以路徑略過：要是 owner 之後把它設為 required check，被略過的 check 會停在 Pending、擋住合併（Context 第 4 點）。
- 理由：action 之後由自動發版與其他 repo 使用，要在 PR 階段先驗證。放在同一個 job 可以少開一台 macOS 機器。
- 新的 commit 推上同一個 PR 時，取消還在執行的 CI（`concurrency` 以 PR 編號分組，`cancel-in-progress: true`）。
- 從其他 repo 引用時，action 會下載到另一個資料夾並在那裡建置，`uses: ./` 的試跑走不到這條路徑，而 `uses:` 又不接受運算式（Context 第 4 點），所以由任務 2.2 驗證一次（fable 審查 S11）：在 PR 的分支上暫時加一個以 `uses: leoho0722/LKAIKit@<功能分支>` 引用的 step，通過後移除這個 step 再合併。

### 第三方 action 以 commit SHA 固定

- 只用到 `actions/checkout`，寫成 `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`。
- 理由：tag 可以被改指向其他 commit，SHA 不行。之後的 release workflow 有寫入權限，從第一個 workflow 就統一這個寫法。

### 實作由 sonnet 在單一 worktree 依序進行

- 沿用之前的做法：sonnet 在 `.worktrees/sonnet`（分支 `wt/ci-sonnet`）依任務順序實作；主對話逐項驗證、commit 並合併回功能分支 `feat/01-add-ci`。
- 任務 1.1 到 1.3 由 sonnet 做；2.1 由主對話做；2.2 在 owner 同意推送與開 PR 後由主對話做。

## Implementation Contract

**檔案與介面**：

| 檔案 | 形狀 |
| --- | --- |
| `action.yml` | 見下方「`action.yml` 的形狀」 |
| `.github/workflows/ci.yml` | 見下方「`ci.yml` 的形狀」 |
| `docs/adding-a-provider.md` | 第 7 章 bundle 一列的「處理」改成已處理，寫出決策「lkai 留在 release 建置資料夾執行，不複製」與它的驗收方式；第 3 章開頭說明出處的地方補一句編號的說明（任務 1.3） |

**`action.yml` 的形狀**：

- `name: Setup lkai`，沒有 `inputs`。
- `outputs.path`、`outputs.version` 取自建置 step 的輸出。
- `runs.using: composite`。
- 第一個 step：`if: runner.os != 'macOS'`，印出 `::error::` 並 `exit 1`。訊息說明需要 macOS runner，不寫 runner 標籤。
- 建置 step：
  - 以 `env` 傳入 `github.action_path`，不在 `run` 中直接展開 `${{ }}`。
  - `set -euo pipefail`。
  - 依序 `swift build -c release --product lkai --package-path "$path"`、`swift build -c release --product lkai --package-path "$path" --show-bin-path`、`"$bin/lkai" -v`。
  - 全部成功後，才寫 `GITHUB_PATH` 與 `GITHUB_OUTPUT`。

**`ci.yml` 的形狀**：

- `on.pull_request.types: [opened, synchronize, reopened]`，沒有 `paths` 或 `paths-ignore`。
- `permissions: contents: read`。
- `concurrency: { group: ci-${{ github.event.pull_request.number }}, cancel-in-progress: true }`。
- 一個 job：`runs-on: xcode-27`、`timeout-minutes: 30`。
- step 依序是：
  1. checkout，以 SHA 固定。
  2. 印出 `swift --version` 與 `bash --version` 的第一行。
  3. `uses: ./`，`id: lkai`。這一步之前沒有任何建置。
  4. 試跑：在 `${{ runner.temp }}` 執行，`steps.lkai.outputs.version` 與 `steps.lkai.outputs.path` 以 `env` 傳入。依序檢查：
     - `lkai -v` 的輸出符合版號格式，且等於 `steps.lkai.outputs.version`。
     - `[ -x "$LKAI_PATH" ]`，`basename "$LKAI_PATH"` 是 `lkai`，`"$LKAI_PATH" -v` 也等於 `steps.lkai.outputs.version`。
  5. `swift test`。
- 不引用任何 secret。

**失敗時的行為**：

- 不在 macOS：action 的第一個 step 失敗，沒有執行 `swift build`。
- 建置失敗：建置 step 失敗，`PATH` 與 outputs 都沒有設定，後面的 step 不會執行。
- 試跑的任一項檢查不符：job 失敗，log 印出實際值與預期值，單元測試不執行。
- 單元測試失敗：job 失敗。

**驗收**：

- 內容審查：兩個 YAML 符合上面的形狀。
- `actionlint` 對 `ci.yml` 沒有錯誤。
- 本機照 action 的指令建置，`PATH` 上的 `lkai` 在 package 以外的資料夾通過 `-v` 與服務錯誤的情境。
- 在 scratch 的乾淨 clone 中，把 action 的 `--show-bin-path` 改成不加 `-c release` 執行一次，確認 `lkai -v` 失敗。
- PR 上的 CI 通過，暫時加上的 `uses: leoho0722/LKAIKit@<功能分支>` step 也通過，之後再移除。

**範圍**：

- 包含：`ci.yml`、`action.yml`、`docs/adding-a-provider.md` 第 7 章的一列與第 3 章開頭說明出處的一句。
- 不包含：發版的一切（`02-add-release-automation`）、`Package.swift` 與 `Sources/`、`lkai` 的行為、branch protection、Linux 支援、建置快取。

## Risks / Trade-offs

- [Xcode 27.1 無法編譯] → 本機只驗證過 27.2。任務 2.2 的 CI 失敗時，在 job 加上 `env: DEVELOPER_DIR: /Applications/Xcode_27.2.app/Contents/Developer`（路徑以 runner-images README 為準），並以 `/spectra-ingest` 更新決策「CI 在 xcode-27 runner 執行」。
- [其他 repo 以 `@main` 引用 action，每個 job 都重新建置] → 估計 1 到 2 分鐘（Context 第 3 點），由任務 2.2 的實測確認；之後需要時再加建置快取。
- [以 `@main` 引用的 repo 會拿到 main 上任何時候的程式碼] → 需要穩定時，改以 tag 引用；tag 由 `02-add-release-automation` 建立。
- [CI 不跑 iOS simulator 的建置] → iOS 的編譯錯誤不會在 PR 上被擋下，仍由各 change 的驗收手動確認。

## Migration Plan

1. 合併後，之後的每個 PR 都會跑 CI；owner 可以在 GitHub 把這個 check 設為 required。注意：在 `main` 上要求 required status check 時，`02-add-release-automation` 以 `GITHUB_TOKEN` 直接推到 `main` 的升版 commit 沒有 CI 結果，會被拒絕。GitHub 文件沒有寫明能不能讓 `GITHUB_TOKEN` 例外（fable 與 opus 第三輪審查各自查詢），所以加保護前要先在 sandbox repo 實測；不行時改用 GitHub App 的 installation token 或 PAT，並把對應的對象加進 bypass。bypass 能加哪些對象以實測時 GitHub 提供的為準（官方 API 描述目前列出 App、角色、team、deploy key 與使用者；fable 第五輪審查 U1）：用 App 的 token 時加那個 App，用 PAT 時加 PAT 的擁有者或他的角色。不論哪一種，都要在 release workflow 的 checkout 以 `token:` 傳入，push 才會用到它（opus 第四輪審查 S2）。`docs/releasing.md` 會寫明。
2. `02-add-release-automation` 在這個 change 合併後開始實作。
3. 停用：`gh workflow disable ci.yml`。

## Open Questions

無。
