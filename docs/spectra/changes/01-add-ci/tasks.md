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

- [x] 1.1 依 design「Composite action 從 action 所在的原始碼建構 lkai，不採用 container action」、「lkai 留在 release 建置資料夾執行，不複製」與「action 只要求 macOS runner，不寫 runner 標籤」，新增 repo 根目錄的 `action.yml`，交付 lkai-setup-action「Setup action interface」、「Build lkai from the action source」與「macOS runner only」（sonnet）：
  - 形狀照 Implementation Contract 的「`action.yml` 的形狀」。
  - 驗證：主對話逐條對照形狀審查內容，確認以下幾點：
    - 兩個 `swift build` 都有 `-c release`。
    - `run` 中沒有直接展開 `${{ }}`。
    - 建置失敗時不寫 `GITHUB_PATH`。
    - 錯誤訊息只說需要 macOS runner、不寫標籤。
  - 建置指令在 2.1 於本機照樣執行；CI 中的實際執行在 2.2 確認。「Use the action on a Linux runner」只以內容審查確認，不另外開 Linux job。
  - 測試範圍的排除（TDD）：
    - spectra-exclude: lkai-setup-action / Read the action outputs | 專案的測試環境（swift test）無法執行 GitHub Actions 的 composite action，觀察不到這個行為；由 1.2 的試跑檢查 version 與 path，2.2 在 CI 上確認
    - spectra-exclude: lkai-setup-action / Use the action from another repository | 專案的測試環境（swift test）無法執行 GitHub Actions 的 composite action，觀察不到這個行為；由 2.2 暫時以 uses: leoho0722/LKAIKit@feat/01-add-ci 引用確認
    - spectra-exclude: lkai-setup-action / Report a service failure when run from PATH | 專案的測試環境（swift test）無法執行 GitHub Actions 的 composite action，觀察不到這個行為；由 2.1 在本機照 action 的指令建置後，從 package 以外的資料夾實際執行確認
    - spectra-exclude: lkai-setup-action / The build fails | 專案的測試環境（swift test）無法執行 GitHub Actions 的 composite action，觀察不到這個行為；由內容審查確認 set -euo pipefail 與寫入 GITHUB_PATH 的位置
    - spectra-exclude: lkai-setup-action / Use the action on a Linux runner | 專案的測試環境（swift test）無法執行 GitHub Actions 的 composite action，觀察不到這個行為，也不另開 Linux job；由內容審查確認
- [x] 1.2 [after: 1.1] 依 design「CI 跑單元測試與 action 試跑」、「CI 在 xcode-27 runner 執行」與「第三方 action 以 commit SHA 固定」，新增 `.github/workflows/ci.yml`，交付 continuous-integration「Pull request workflow trigger and runner」、「Unit tests without real API keys」與「Setup action smoke check」（sonnet）：
  - 形狀照 Implementation Contract 的「`ci.yml` 的形狀」。
  - 驗證：主對話審查內容，確認以下幾點：
    - 不引用任何 secret。
    - 沒有 `paths` 或 `paths-ignore`。
    - `actions/checkout` 以 SHA 固定並附版本註解。
    - `uses: ./` 與試跑在 `swift test` 之前，之前沒有任何建置的 step。
    - 試跑比對 `lkai -v` 與 `version` 輸出，並檢查 `path` 輸出是可執行檔、最後一段是 `lkai`、以 `-v` 執行印出同樣的版號。
    - `steps.lkai.outputs.*` 以 `env` 傳入。
  - actionlint 在 2.1 執行；實際執行在 2.2 確認。
  - 測試範圍的排除（TDD）：
    - spectra-exclude: continuous-integration / Open a pull request | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由 2.2 的 PR 確認
    - spectra-exclude: continuous-integration / Open a pull request that changes only Spectra documents | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由內容審查確認沒有 paths 或 paths-ignore
    - spectra-exclude: continuous-integration / Push a new commit while a run is in progress | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；只以內容審查確認 concurrency 的設定（以 PR 編號分組、cancel-in-progress: true），2.2 的幾次 push 沒有重疊，沒有實際觀察到取消
    - spectra-exclude: continuous-integration / Run the unit tests on a pull request | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由 2.1 在本機執行 swift test、2.2 在 CI 上確認
    - spectra-exclude: continuous-integration / A unit test fails | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由內容審查確認 swift test 的退出碼會讓 job 失敗
    - spectra-exclude: continuous-integration / Smoke check the setup action | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由 2.2 在 CI 上確認
    - spectra-exclude: continuous-integration / The action looks for lkai in the debug build directory | 專案的測試環境（swift test）無法執行 GitHub Actions 的 workflow，觀察不到這個行為；由 2.1 在 scratch 的乾淨 clone 中實測
- [x] 1.3 依 design「lkai 留在 release 建置資料夾執行，不複製」，改寫 `docs/adding-a-provider.md` 第 7 章「`lkai` 要和 `LKAIKit_LKAICore.bundle`、`LKAIKit_LKAIKitCLI.bundle` 放在同一個資料夾」一列，讓之後修改的人知道 bundle 的問題怎麼處理（sonnet）：
  - 處理方式改為已處理：action 不複製 `lkai`，從 release 的建置資料夾執行。
  - 寫出這個 change 的驗收方式（lkai-setup-action「Report a service failure when run from PATH」）。
  - 寫明之後要複製 `lkai`（例如附上執行檔）時，仍要連同兩個 bundle 一起複製。
  - 出處寫 change 的完整名稱 `01-add-ci`，不只寫「01」；並在第 3 章開頭說明出處的地方補一句：只寫編號的 01 到 04 指 2026-11-22、23 的那一組 change（`01-extract-chat-stream-skeleton` 到 `04-add-gemini-provider`），之後的 change 一律寫完整名稱（fable 第二輪審查 N5）。
  - 驗證：主對話審查文字；`git diff` 只有這一列與第 3 章開頭的說明改變。

## 2. 驗收

- [x] 2.1 [after: 1.1, 1.2, 1.3] 主對話在功能分支上做本機的檢查，不 push：
  - owner 同意後以 Homebrew 安裝 `actionlint`，`actionlint .github/workflows/ci.yml` 沒有錯誤。
  - 照 `action.yml` 建置 step 的指令建置 release 版的 `lkai`，確認 `--show-bin-path` 印出 `.build/out/Products/Release`，把它加進 `PATH`。
  - 依 lkai-setup-action「Report a service failure when run from PATH」，在 package 以外的資料夾：
    - 執行 `lkai -v`，印出版號、退出碼 0。
    - 以被拒絕的金鑰送一次請求，退出碼 1，stderr 第一行以 `Error: ` 開頭。
  - 依 continuous-integration「The action looks for lkai in the debug build directory」，在 scratch 的乾淨 clone 中，把 action 的 `--show-bin-path` 改成不加 `-c release` 執行一次，確認 `lkai -v` 失敗、退出碼不是 0。
  - `swift test` 通過。
  - 驗證：以上指令的結果記在任務回報中。
  - 執行紀錄（2026-11-24，本機 M1、Xcode 27.2）：
    - 實作審查後新增 `.github/actionlint.yaml`，把 `xcode-27` 宣告為已知的標籤，直接執行 `actionlint .github/workflows/ci.yml` 的退出碼是 0；下面是加入設定之前的紀錄。
    - `brew install actionlint`（1.7.12，連同依賴 `shellcheck`）。`actionlint .github/workflows/ci.yml` 只回報 `label "xcode-27" is unknown`：1.7.12 內建的標籤清單還沒有 2026-10-15 GA 的 `xcode-27`（GitHub Changelog 與 runner-images README 都列有這個標籤），屬於誤報，由 2.2 的實際執行確認；以 `-ignore 'label "xcode-27" is unknown'` 重跑沒有其他錯誤，`run` 區塊的 shellcheck 也通過。
    - 照 `action.yml` 的指令以 `--package-path` 指向 repo 建置：`--show-bin-path` 印出 `.build/out/Products/Release`，`lkai -v` 是 `0.1.0`。
    - 在 package 以外的資料夾從 `PATH` 執行：`lkai -v` 印出 `0.1.0`、退出碼 0；以被拒絕的金鑰執行 `lkai --provider anthropic -m claude-opus-5-5 -p hi`，退出碼 1，stderr 第一行是 `Error: The API key is invalid.`，stdout 是空的，輸出不含金鑰。
    - 「The action looks for lkai in the debug build directory」：在 scratch 的乾淨 clone 中只做 release 建置，再以不加 `-c release` 的 `--show-bin-path` 取資料夾，用 `bash --noprofile --norc -eo pipefail` 執行時 `lkai -v` 以退出碼 127 失敗，後面的指令沒有執行。（第一次誤用 zsh 執行，zsh 的 `set -e` 不會在失敗的指令替換中止，那次結果不採用。）
    - 另外把 `action.yml` 的建置 step 與 `ci.yml` 的試跑 step 原樣取出，在乾淨的 clone 中以同樣的 bash 依序執行：建置 step 退出碼 0，`GITHUB_PATH` 是 Release 資料夾，輸出 `path` 與 `version=0.1.0`；試跑 step 退出碼 0。
    - `swift test` 退出碼 0：7 個測試 target 共 270 個測試通過、0 個失敗，9 個需要真實 API Key 的測試函式顯示為略過；環境中沒有任何 `LKAI_*` 變數。
- [x] 2.2 [after: 2.1] owner 同意後，主對話 push 功能分支並開 PR，確認 CI 在 `xcode-27` runner 通過：
  - 依 design「CI 跑單元測試與 action 試跑」，在分支上暫時加一個 step，以 `uses: leoho0722/LKAIKit@feat/01-add-ci` 引用 action，並執行 `lkai -v`；通過後移除這個 step 再推一次，確認 CI 仍通過。
  - 驗證：PR 的 CI check 成功。
  - 驗證：任務回報記錄以下內容：
    - `swift --version` 與 `bash --version` 印出的版本。
    - 各 step 的時間，包含 release 建置的時間。
    - `swift test` 略過的測試。
    - 暫時 step 的結果。
  - Xcode 27.1 無法編譯時，依 design 的 Risks 處理。
  - 執行紀錄（2026-11-24，PR #8：https://github.com/leoho0722/LKAIKit/pull/8）：
    - 第一次 CI（run 45285504606，含暫時的 step）：成功，job 2 分 34 秒。
      - 工具鏈：`swift --version` 是 Apple Swift version 6.4（swiftlang-6.4.0.34.1），Target `arm64-apple-macosx27.0.0`，也就是 runner 預設的 Xcode 27.1 能編譯，不需要改用 27.2；`bash --version` 是 GNU bash 3.2.57。
      - 各 step 的時間：Setup lkai 65 秒（release 建置 40.95 秒）、試跑 1 秒、暫時的外部引用 35 秒（建置 29.85 秒）、`swift test` 38 秒（建置 22.58 秒）。
      - 試跑：`lkai -v` 是 `0.1.0`，`path` 是 `/Users/runner/work/LKAIKit/LKAIKit/.build/out/Products/Release/lkai`。
      - 暫時的 step：以 `uses: leoho0722/LKAIKit@feat/01-add-ci` 引用時，action 在 `/Users/runner/work/_actions/leoho0722/LKAIKit/feat/01-add-ci/` 建置（不在 workspace 中），`path` 輸出與 `PATH` 上的 `lkai` 都是那一份，版號 `0.1.0`。
      - `swift test`：7 個測試 target 共 270 個測試通過，9 個需要真實 API Key 的測試函式顯示為略過。
    - 移除暫時的 step 後（commit c8fba2f，`ci.yml` 和加入前相同）的第二次 CI（run 45286073982）：成功，job 2 分 0 秒。
    - 三次 CI 的時間沒有重疊（UTC 23:04:12–23:06:52、23:07:55–23:10:00、23:10:44–23:12:49），所以沒有觀察到「新的 commit 取消執行中的 run」；這個情境只以內容審查確認（/spectra-verify 與實作審查指出，2026-11-24）。
