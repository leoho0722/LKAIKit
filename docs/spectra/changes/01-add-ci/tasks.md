派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1 組由 sonnet 在 `.worktrees/sonnet`（分支 `wt/ci-sonnet`）依序實作，主對話逐項驗證、commit，並合併回功能分支 `feat/01-add-ci`。
- 第 2 組：2.1 由主對話做；2.2 在 owner 同意推送與開 PR 後由主對話做。

用語：換行字元寫 LF、CR、CRLF，不寫「回車」；「換行」只指一行結束。

**拆分紀錄（不是任務）**：本 change 原名 `add-ci-cd`，依 design「拆成 01-add-ci 與 02-add-release-automation」，原本的下列任務都還沒開始，已移出本 change，改由 `02-add-release-automation` 處理：

- 原 1.1 到 1.6：發版 script 與它的測試。
- 原 2.3：`release.yml`。
- 原 3.1：`LKAIKitInfo.swift` 的 `///`，以及 `docs/adding-a-provider.md` 中屬於發版的部分。
- 原 4.2 的 dry run、原 4.3 的 repository secret。

原 2.1、2.2、4.1、4.4 中屬於 CI 與 action 的部分，改寫為下面的 1.1、1.2、2.1、2.2。

## 1. Action 與 CI

- [ ] 1.1 依 design「Composite action 從 action 所在的原始碼建構 lkai，不採用 container action」、「lkai 留在 release 建置資料夾執行，不複製」與「action 只要求 macOS runner，不寫 runner 標籤」，新增 repo 根目錄的 `action.yml`，交付 lkai-setup-action「Setup action interface」、「Build lkai from the action source」與「macOS runner only」（sonnet）：
  - 形狀照 Implementation Contract 的「`action.yml` 的形狀」。
  - 驗證：主對話逐條對照形狀審查內容，確認以下幾點：
    - 兩個 `swift build` 都有 `-c release`。
    - `run` 中沒有直接展開 `${{ }}`。
    - 建置失敗時不寫 `GITHUB_PATH`。
    - 錯誤訊息只說需要 macOS runner、不寫標籤。
  - 建置指令在 2.1 於本機照樣執行；CI 中的實際執行在 2.2 確認。「Use the action on a Linux runner」只以內容審查確認，不另外開 Linux job。
- [ ] 1.2 [after: 1.1] 依 design「CI 跑單元測試與 action 試跑」、「CI 在 xcode-27 runner 執行」與「第三方 action 以 commit SHA 固定」，新增 `.github/workflows/ci.yml`，交付 continuous-integration「Pull request workflow trigger and runner」、「Unit tests without real API keys」與「Setup action smoke check」（sonnet）：
  - 形狀照 Implementation Contract 的「`ci.yml` 的形狀」。
  - 驗證：主對話審查內容，確認以下幾點：
    - 不引用任何 secret。
    - 沒有 `paths` 或 `paths-ignore`。
    - `actions/checkout` 以 SHA 固定並附版本註解。
    - `uses: ./` 與試跑在 `swift test` 之前，之前沒有任何建置的 step。
    - 試跑比對 `lkai -v` 與 `version` 輸出，並檢查 `path` 輸出是可執行檔、最後一段是 `lkai`、以 `-v` 執行印出同樣的版號。
    - `steps.lkai.outputs.*` 以 `env` 傳入。
  - actionlint 在 2.1 執行；實際執行在 2.2 確認。
- [ ] 1.3 依 design「lkai 留在 release 建置資料夾執行，不複製」，改寫 `docs/adding-a-provider.md` 第 7 章「`lkai` 要和 `LKAIKit_LKAICore.bundle`、`LKAIKit_LKAIKitCLI.bundle` 放在同一個資料夾」一列，讓之後修改的人知道 bundle 的問題怎麼處理（sonnet）：
  - 處理方式改為已處理：action 不複製 `lkai`，從 release 的建置資料夾執行。
  - 寫出這個 change 的驗收方式（lkai-setup-action「Report a service failure when run from PATH」）。
  - 寫明之後要複製 `lkai`（例如附上執行檔）時，仍要連同兩個 bundle 一起複製。
  - 出處寫 change 的完整名稱 `01-add-ci`，不只寫「01」；並在第 3 章開頭說明出處的地方補一句：只寫編號的 01 到 04 指 2026-11-22、23 的那一組 change（`01-extract-chat-stream-skeleton` 到 `04-add-gemini-provider`），之後的 change 一律寫完整名稱（fable 第二輪審查 N5）。
  - 驗證：主對話審查文字；`git diff` 只有這一列與第 3 章開頭的說明改變。

## 2. 驗收

- [ ] 2.1 [after: 1.1, 1.2, 1.3] 主對話在功能分支上做本機的檢查，不 push：
  - owner 同意後以 Homebrew 安裝 `actionlint`，`actionlint .github/workflows/ci.yml` 沒有錯誤。
  - 照 `action.yml` 建置 step 的指令建置 release 版的 `lkai`，確認 `--show-bin-path` 印出 `.build/out/Products/Release`，把它加進 `PATH`。
  - 依 lkai-setup-action「Report a service failure when run from PATH」，在 package 以外的資料夾：
    - 執行 `lkai -v`，印出版號、退出碼 0。
    - 以被拒絕的金鑰送一次請求，退出碼 1，stderr 第一行以 `Error: ` 開頭。
  - 依 continuous-integration「The action looks for lkai in the debug build directory」，在 scratch 的乾淨 clone 中，把 action 的 `--show-bin-path` 改成不加 `-c release` 執行一次，確認 `lkai -v` 失敗、退出碼不是 0。
  - `swift test` 通過。
  - 驗證：以上指令的結果記在任務回報中。
- [ ] 2.2 [after: 2.1] owner 同意後，主對話 push 功能分支並開 PR，確認 CI 在 `xcode-27` runner 通過：
  - 依 design「CI 跑單元測試與 action 試跑」，在分支上暫時加一個 step，以 `uses: leoho0722/LKAIKit@feat/01-add-ci` 引用 action，並執行 `lkai -v`；通過後移除這個 step 再推一次，確認 CI 仍通過。
  - 驗證：PR 的 CI check 成功。
  - 驗證：任務回報記錄以下內容：
    - `swift --version` 與 `bash --version` 印出的版本。
    - 各 step 的時間，包含 release 建置的時間。
    - `swift test` 略過的測試。
    - 暫時 step 的結果。
  - Xcode 27.1 無法編譯時，依 design 的 Risks 處理。
