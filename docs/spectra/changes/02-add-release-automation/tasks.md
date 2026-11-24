`01-add-ci` 已於 2026-11-24 合併（PR #8，merge commit `33210e7`），本 change 可以開始實作（design 的 Migration Plan 第 1 點）。

派工方式依 design「實作由 sonnet 在單一 worktree 依序進行」：

- 第 1 到 3 組由 sonnet 在 `.worktrees/sonnet`（分支 `wt/release-sonnet`）依序實作，主對話逐項驗證、commit，並合併回功能分支 `feat/02-add-release-automation`。
- 第 4 組：4.1、4.2 由主對話做；4.3 由 owner 做，或 owner 同意後由主對話執行；4.4 在 owner 同意推送與開 PR 後由主對話做。

測試的做法：

- **新行為先寫測試**：依 design「發版 script 以假的 lkai、gh、swift 與暫存 git repo 測試」，先寫測試與能執行的最小骨架，主對話觀察到新測試在實作前失敗，才實作。
- **spec 標記**：每個為 spec 情境寫的測試函式上方加 `# spectra-scenario: <capability> / <情境>`，有範例時再加一行 `# / <範例>`，名稱照抄 spec；範例表的每一列都要有對應的斷言。
- **寫法的限制**：依 design「發版邏輯寫成 bash script，只用 BSD 與 GNU 都有的寫法」。每個任務都以本機的 `/bin/bash`（3.2.57）執行 `bash .github/scripts/release/tests/run-tests.sh`，也以 `GITHUB_ACTIONS=true` 執行一次，結果要相同。
- **不連網、不改 GitHub**：script 的測試只用 `tests/fakes/` 的 `lkai`、`gh`、`swift` 與暫存的 git repo（bare repo 作為 remote），不送 AI 請求、不建置 package，也不讀本機的 git 全域設定與 GitHub Actions 的環境變數。
- **出處**：寫進文件的出處一律寫 change 的完整名稱（例如 `02-add-release-automation`），不只寫編號。
- **用語**：換行字元寫 LF、CR、CRLF，不寫「回車」；「換行」只指一行結束。script 的訊息以正體中文撰寫。

## 1. 發版 script

- [x] 1.1 依 design「發版 script 以假的 lkai、gh、swift 與暫存 git repo 測試」與「1.0.0 之前 major 只升 MINOR、minor 與 patch 升 PATCH」，建立 script 的測試工具，並交付 release-automation「Next version computation」與「Release script test isolation」（sonnet）：
  - `.github/scripts/release/tests/run-tests.sh`：
    - 執行同一個資料夾內 `test-*.sh` 的每個 `test_` 函式，每個函式在自己的 subshell 與暫存資料夾中執行。
    - 執行前設定 `GIT_CONFIG_GLOBAL=/dev/null` 與 `GIT_CONFIG_NOSYSTEM=1`；每個測試開始前清掉 design 列出的 GitHub Actions、`GH_*`、`LKAI_RELEASE_*` 與 `LKAI_*_API_KEY` 變數。
    - 受測 script 的 stdout 與 stderr 收進檔案；印出失敗的細節時，每一行前面加兩個空格。
    - 逐一印出 `PASS`／`FAIL` 與函式名稱，最後印出總數；有任何失敗時以 1 結束，全部通過時以 0 結束。
  - `tests/helpers.sh`：
    - 相等、包含、不包含與退出碼的斷言。
    - 建立暫存 git repo 的函式：以本 repo 真正的 `Sources/LKAICore/LKAIKitInfo.swift` 建立第一個 commit（以明確的身分 commit），並建立 bare repo 作為 `origin`。
    - 建立版本 tag 的函式：預設同時寫下這個 tag 的 Release 紀錄，可以指定不寫。
  - `tests/fakes/lkai`、`gh`、`swift` 的骨架，形狀照 Implementation Contract 的「假的指令」。
  - `.github/scripts/release/next-version.sh` 與 `tests/test-next-version.sh`：範例表「next versions」的 11 列各一個斷言，不合法的列另外確認 stdout 為空、退出碼不是 0。
  - 驗證：
    - 主對話觀察到 `test-next-version.sh` 在實作前失敗；`run-tests.sh` 以 `/bin/bash` 通過。
    - 故意讓一個斷言失敗時，`run-tests.sh` 以 1 結束（確認後還原），涵蓋 continuous-integration「A release script test fails」中 script 的部分；job 失敗的部分只以內容審查確認，由任務 2.2 的檢查項負責（step 的非 0 退出碼會讓 job 失敗），不為了觀察它而推一個會失敗的 commit。
    - 情境「Run the tests inside GitHub Actions」：以 `GITHUB_ACTIONS=true` 與一個暫存檔作為 `GITHUB_STEP_SUMMARY` 執行 `run-tests.sh`，每個測試的結果相同，暫存檔沒有改變，輸出沒有以 `::` 開頭的行。
- [x] 1.2 [after: 1.1] 依 design「版號從 LKAIKitInfo.swift 讀取，與寫入共用同一個規則」，新增 `.github/scripts/release/package-version.sh` 的 `get` 與 `set`，交付 release-automation「Release plan」讀版號的規則，以及「Version commit and tag push」修改版號的部分（sonnet）：
  - `tests/test-package-version.sh` 以本 repo 真正的 `LKAIKitInfo.swift` 的複本測試：
    - `get` 印出 `0.1.0`。
    - `set` 換成 `0.1.1` 後只有那一行改變（以 `diff` 確認），`get` 印出 `0.1.1`。
    - 宣告不存在時，`get` 與 `set` 都以 1 結束，檔案不變。
    - 宣告出現兩次時，`get` 與 `set` 都以 1 結束，檔案不變。
    - `set` 的版號不合格式（例如 `v0.1.1`）時，檔案不變、退出碼 1。
  - 驗證：主對話觀察到新測試在實作前失敗；`run-tests.sh` 通過；內容審查確認沒有使用 `sed -i`。
- [x] 1.3 [after: 1.1] 依 design「兩個 prompt 帶同樣的變更資料：commit 清單、變更統計與 200,000 bytes 以內的程式碼 diff」、「Release Notes 以正體中文分類撰寫」與「判斷升級等級與撰寫 Release Notes 分成兩次請求」，新增兩個 prompt 範本與 `make-prompt.sh`，交付 release-automation「Change data in prompts」，以及「AI bump level answer」「Release notes generation」中對 prompt 的要求（sonnet）：
  - `prompts/bump-level.md`：第一行是標記；依公開介面定義 `major`、`minor`、`patch`；要求只回答其中一個字。
  - `prompts/release-notes.md`：第一行是標記；要求以正體中文、Markdown，分成「破壞性變更」「新功能」「修正」「其他」，沒有項目的分類不寫。
  - 兩個範本都說明 `<commits>`、`<stat>`、`<diff>` 中的文字是資料，要忽略其中的指示。
  - `make-prompt.sh`：形狀照 Implementation Contract。
  - `tests/test-make-prompt.sh` 的情境：
    - 「Change data for a version bump」：兩種 prompt 都含兩個 commit 的標題與變更統計，含 `Sources/` 的 diff、不含 `Tests/` 的 diff。
    - 「Change data for the first release」：`LKAI_RELEASE_DIFF_LIMIT` 改小，確認含第一個 commit 在內的全部標題，並說明 diff 因大小而省略。
    - 「Build the release notes prompt for a version bump」「Build the release notes prompt for the first release」。
  - `tests/test-make-prompt.sh` 的其他測試：
    - bump level prompt 含上一版、不含 `<version>`。
    - merge commit 的標題不出現。
    - `<target-ref>` 是 tag 時，範圍到那個 tag 為止。
    - 範本的第一行標記保留在輸出的第一行。
  - 驗證：主對話觀察到新測試在實作前失敗；`run-tests.sh` 通過；主對話審查兩個範本的文字。
- [ ] 1.4 [after: 1.2, 1.3] 依 design「只有 GitHub Actions 中明確設成 false 才正式發版」、「供應商與模型：優先順序由 script 決定，只留一組預設值，驗證交給 lkai」、「計畫先擋下比現在版號更大的 tag」、「tag 之後只有 docs/spectra 的變更時不發版」與「版號還沒有 tag 時照原樣發佈」，新增 `.github/scripts/release/release.sh` 的前半段，交付 release-automation「Release mode」、「Release provider and model selection」、「Release plan」、「AI bump level answer」、「Release notes generation」與「Failed AI request」（sonnet）：
  - 流程照 Implementation Contract 的第 1 到 5 步；這個任務先不處理第 3 步的「檢查 Release」，由 1.6 加上。
  - 呼叫 `lkai` 的方式照「呼叫 `lkai` 的方式」；截斷被拒絕的回答照 design「發版邏輯寫成 bash script，只用 BSD 與 GNU 都有的寫法」的 `iconv` 寫法。
  - 這個任務先以「印出計畫與 Release Notes 後以 1 結束」作為第 5 步之後的暫時行為，由 1.5 取代。
  - `tests/test-release.sh` 以假的 `lkai` 測試：
    - 範例表「modes」的 7 列。
    - 範例表「provider and model resolution」的 8 列，以及情境「lkai rejects the provider」。
    - 範例表「plans」的 8 列，以及情境「Choose a version by hand」「Read the version at HEAD」：計畫與兩個版號；失敗的列確認退出碼與訊息。
    - 範例表「answers」的 6 列，以及情境「Shorten a long rejected answer」（stderr 不含 `iconv:`）。
    - 情境「The release notes are blank」「The AI service rejects the request」「The release notes are cut off」。
    - 回答不合法與 AI 請求失敗時，假的 `gh` 沒有收到 `release create`，`LKAIKitInfo.swift` 沒有改變。
  - 驗證：主對話觀察到新測試在實作前失敗；`run-tests.sh` 通過。
- [ ] 1.5 [after: 1.4] 依 design「每個結束點都寫執行報告」與「AI 的文字以 stop-commands 包起來」，交付 release-automation「Dry run」、「Run report」、「AI text in the job log」與「API keys stay in the environment」（sonnet）：
  - `release.sh` 的第 6 步與第 9 步照 Implementation Contract，報告以 `trap ... EXIT` 統一寫出，步驟名稱照 design 的固定清單。
  - `tests/test-release.sh` 新增：
    - 情境「Dry run a version bump」：工作目錄、remote 的 `main`、tag 與假的 `gh` 的紀錄都沒有改變，退出碼 0；報告只印一次。
    - 情境「Report a release in the job summary」「Report nothing to release」「Report a failed run」「Report a failure before the version is read」：以暫存檔作為 `GITHUB_STEP_SUMMARY`。
    - 情境「Release notes contain a workflow command」「A rejected answer contains a workflow command」（回答是 `upgrade` LF `::add-mask::x`）：`GITHUB_ACTIONS=true` 時，標記與文字在同一個流，token 至少 32 個十六進位字元，`::error::` 那一行不含 AI 的文字；`GITHUB_ACTIONS` 沒有設定時不加標記。
    - 情境「Inspect the lkai invocation」：假的 `lkai` 記錄的引數、stdout、stderr、job summary 與 prompt 檔都不含 `sk-test-secret`。
  - 驗證：主對話觀察到新測試在實作前失敗；`run-tests.sh` 通過。
- [ ] 1.6 [after: 1.5] 依 design「升版 commit 與 tag 以一次 atomic push 推上 main，再以 --verify-tag 建立 Release」、「tag 沒有 Release 時先補建」與「tag 與版號相同，沒有 v 前綴」，交付 release-automation「Version commit and tag push」、「Release creation」與「Release repair」，以及 package-distribution「Release tag matches the package version」（sonnet）：
  - `release.sh` 第 3 步的「檢查 Release」與第 7、8 步照 Implementation Contract。
    - commit 的 author、committer 與訊息照 spec，以環境變數設定身分，不修改 git 設定。
    - 重新建置後以 `--show-bin-path` 資料夾中的 `lkai -v` 確認版號。
  - 1.4、1.5 的測試因為 helpers 預設為 tag 寫下 Release 紀錄，加上「檢查 Release」之後仍要全部通過；不通過時修正 fixture，不改斷言的意思。
  - `tests/test-release.sh` 以 bare repo 作為 remote，新增 release-automation 的情境：
    - 「Bump the version」：remote 的 `main` 多一個只改版號的 commit，訊息、author 與 committer 正確；remote 的 tag `0.1.1` 指向它；假的 `gh` 收到 `release create 0.1.1 --verify-tag …`。
    - 「Main moved during the run」：在 push 前讓 remote 的 `main` 多一個 commit；push 被拒絕，remote 沒有升版 commit 也沒有 tag `0.1.1`，退出碼 1，假的 `gh` 沒有收到 `release create`。
    - 「Release as-is for the first time」：不建立 commit，tag 指向 `HEAD`。
    - 「Recover after a failed release creation」「Recover when a new change was merged」：補建的 Release Notes 範圍正確。
    - 「The release list cannot be read」（`FAKE_GH_LIST_EXIT`）。
    - 「A request fails after a repair」：補建的 Release 保留，沒有 commit、tag `0.1.2` 或其他 Release。
  - `tests/test-release.sh` 新增 package-distribution 的情境「Inspect a release tag」：以 `git show <tag>:Sources/LKAICore/LKAIKitInfo.swift` 確認值等於 tag。
  - `tests/test-release.sh` 的其他測試：
    - 重新建置後的 `lkai -v`（`FAKE_LKAI_VERSION`）與新版號不同時，在 commit 前失敗。
    - dry run 時，補建只印出 Release Notes，不呼叫 `release create`。
  - 驗證：主對話觀察到新測試在實作前失敗；`run-tests.sh` 通過。

## 2. Workflow

- [ ] 2.1 [after: 1.6] 依 design「只有 docs/spectra 的 push 不觸發，CD 取 main 最新的 commit，正式 run 一次只跑一個」與「dry run 用另一個 concurrency group」，新增 `.github/workflows/release.yml`，形狀與環境變數照 Implementation Contract，交付 release-automation「Release workflow trigger」，以及「Release mode」與「Release provider and model selection」中由 workflow 設定環境變數的部分（sonnet）：
  - 驗證：主對話逐列對照下列範例與情境審查內容：
    - 範例表「changed files and whether the workflow runs」與 `paths-ignore`。
    - 情境「Map the workflow inputs and repository variables」：四個變數原樣傳入，沒有運算式組合。
    - `LKAI_RELEASE_DRY_RUN` 寫成 `inputs.dry_run && 'true' || 'false'`，沒有用 `github.event.inputs`。
    - concurrency 的 group 運算式（「A dry run while a release run waits」）。
    - checkout 沒有 `persist-credentials: false`，並有一行註解寫明不可設定它的原因。
    - `inputs`、`vars` 與 `secrets` 都以 `env` 傳入。
  - actionlint 在 4.1 執行。合併前無法實際觸發（`workflow_dispatch` 要在預設分支上），合併後的確認見 design 的 Migration Plan 與 `docs/releasing.md`。
- [x] 2.2 [after: 1.1] 依 design「CI 的 script 測試規則放在 continuous-integration，測試的隔離留在 release-automation」，在 `.github/workflows/ci.yml` 的 `swift test` 之後，加上 `bash .github/scripts/release/tests/run-tests.sh` 的 step，交付 continuous-integration「Release script tests in CI」（sonnet）：
  - 新的 step 比照既有的寫法：正體中文的 `name`、`shell: bash`，並附一行註解指向 continuous-integration「Release script tests in CI」。
  - 檔案開頭的說明補上發版 script 的測試。
  - 驗證：主對話審查內容，確認以下幾點；實際執行在 4.4 確認。
    - 其他 step 不變、沒有引用 secret。
    - job 的 `runs-on` 與 `release.yml` 相同。
    - 新 step 沒有 `continue-on-error`，也沒有吞掉 `run-tests.sh` 的退出碼（例如 `|| true`），所以非 0 會讓 job 失敗；這一項就是 continuous-integration「A release script test fails」中 job 失敗部分的內容審查。
    - `actionlint .github/workflows/ci.yml` 沒有錯誤。
  - 審查結果（2026-11-24）：`git diff` 只刪掉檔案開頭的舊說明一行，其他 step、trigger、permissions、concurrency 不變；`runs-on: xcode-27` 與 design 規定的 `release.yml` 相同；新 step 沒有 `continue-on-error`、`|| true`、`env`、`secrets` 或 `vars`；`actionlint .github/workflows/ci.yml` 以 0 結束、沒有輸出。

## 3. 文件

- [ ] 3.1 [after: 2.1] 依 design「發版的操作寫在 docs/releasing.md」，新增 `docs/releasing.md`，並在 `docs/spectra/config.yaml` 的 context 加一行指向它，讓之後的 owner 與 agent 不讀封存的 design 也知道怎麼操作發版（sonnet）：
  - 內容涵蓋決策列出的每一項。其中「第一次發版後的確認」包括：
    - tag `0.1.0` 指向合併後 `main` 的 commit。
    - Release 的標題與 Release Notes。
    - Actions 的 job summary，模式是「release」。
    - `main` 沒有多出 commit。
  - 本機 dry run 一節寫明前置條件，包括 `gh` 要已登入。
  - branch protection 一節照 design 的寫法：
    - 先實測能不能讓 `GITHUB_TOKEN` 例外。
    - 不行時改用 GitHub App 的 installation token 或 PAT，把那個 App，或 PAT 的擁有者或他的角色加進 bypass，能加的對象以實測為準；並在 `release.yml` 的 checkout 以 `token:` 傳入。
    - 改用其他 token 要另開 change，同時更新 release-automation「Release workflow trigger」中只描述 `GITHUB_TOKEN` 的情境「A push by the release workflow itself」，並補上「以其他 token 推送時會再觸發一次，並以沒有可發佈的變更結束」的情境。
  - `config.yaml` 的那一行寫明什麼時候讀，以及哪些 change 封存前要更新它。
  - 驗證：主對話逐項對照決策審查文字；`spectra validate 02-add-release-automation` 仍通過。
- [ ] 3.2 [after: 3.1] 更新兩份既有的說明（sonnet）：
  - `Sources/LKAICore/LKAIKitInfo.swift` 的 `///`：
    - 依 design「版號由 AI 回答升級等級、script 計算」，改成由 release workflow 更新。
    - 要指定版號時，在 PR 中改成還沒有 tag 的版號，並指向 `docs/releasing.md`。
    - 依「版號從 LKAIKitInfo.swift 讀取，與寫入共用同一個規則」，寫明宣告的寫法改變時要一起修改 `.github/scripts/release/package-version.sh`。
    - 值不變。
  - `docs/adding-a-provider.md`，依 design「發版的操作寫在 docs/releasing.md」：
    - 「新增供應商要動的既有檔案」補上 `release.yml` 傳入的 secret、release-automation spec 中列出 secret 的那一句，以及 GitHub 上的 repository secret。
    - 第 5 章加一列，說明 `add-swift-package-foundation` 的「發佈時手動更新此值」由 `02-add-release-automation` 的決策取代。
    - 第 7 章「調整 `LKAIKitInfo.version` 並打第一個 release tag」一列改成「已解決」，依據寫 `02-add-release-automation` 的決策「版號由 AI 回答升級等級、script 計算」。
  - 驗證：主對話審查文字；`git diff Sources/` 只有 `LKAIKitInfo.swift` 的 `///` 改變；`swift build` 通過。

## 4. 驗收

- [ ] 4.1 [after: 1.6, 2.1, 2.2, 3.2] 主對話在功能分支上做靜態檢查與測試：
  - 以 `/bin/bash` 執行 `bash .github/scripts/release/tests/run-tests.sh`，全部通過；以 `GITHUB_ACTIONS=true` 再執行一次，結果相同。
  - 依 Implementation Contract 的「驗收」，確認以下幾點：
    - `spectra-scenario` 標記涵蓋所有應由 `run-tests.sh` 涵蓋的情境，範例表的每一列都有斷言。
    - 只能以內容審查確認的情境，在 2.1 的回報中都有逐項結果。
  - `actionlint` 與 `shellcheck` 已在 `01-add-ci` 任務 2.1 安裝（`shellcheck` 是 `actionlint` 的依賴），先以 `command -v` 確認：
    - `actionlint` 對兩個 workflow 沒有錯誤（直接執行，`.github/actionlint.yaml` 已宣告 `xcode-27`，不加 `-ignore`）。
    - `shellcheck` 對 `.github/scripts/release/` 的所有 script 沒有錯誤。
  - `swift test` 通過。
  - 驗證：以上指令的結果記在任務回報中。
- [ ] 4.2 [after: 4.1] 主對話以 Keychain 的 `lkai-anthropic-api-key` 在本機以 dry run 做實際的驗收，不 push、不建立 tag 或 release：
  - 在 scratch 的 clone 中執行，clone 的 `origin` 改成本機的 bare repo；`gh` 的讀取以 `GH_REPO=leoho0722/LKAIKit` 指向正式的 repo（只有 `gh release list`）；不設定 `GITHUB_ACTIONS`。
  - 照原樣發佈的計畫：沒有任何 tag，以 dry run 執行，確認計畫是 release as-is `0.1.0`，Release Notes 是正體中文且依分類撰寫。
  - 補建加升版的計畫：
    - 把暫時的 tag `0.1.0` 打在 PR #6 的 merge commit（`1eb98a3`），以 dry run 執行。
    - GitHub 上還沒有 Release，所以先印出補建 `0.1.0` 的 Release Notes。
    - 再確認升級等級是三個字之一、新版號依規則計算、Release Notes 合理。
  - 確認 `LKAI_RELEASE_DRY_RUN=false` 在本機被拒絕。
  - 驗證：輸出與 `lkai` 的退出碼記在任務回報中；本 repo 與 GitHub 上都沒有新的 commit、tag 或 release。
- [x] 4.3 owner 在 GitHub 的 repository secrets 設定 `LKAI_ANTHROPIC_API_KEY`（或 owner 同意後由主對話以 `gh secret set` 從 Keychain 設定）：
  - 驗證：`gh secret list` 列出 `LKAI_ANTHROPIC_API_KEY`。
  - 執行紀錄（2026-11-24）：owner 同意後由主對話執行。先以 `security find-generic-password -s lkai-anthropic-api-key` 確認項目存在（不加 `-w`），再以 `security find-generic-password -s lkai-anthropic-api-key -w | tr -d '\n' | gh secret set LKAI_ANTHROPIC_API_KEY --repo leoho0722/LKAIKit` 從標準輸入設定，金鑰沒有出現在命令列引數或輸出中；`gh secret list` 列出 `LKAI_ANTHROPIC_API_KEY`（更新時間 2026-11-24T04:20:01Z）。金鑰的內容由合併後第一次發版的 AI 請求實際確認。
- [ ] 4.4 [after: 4.2, 4.3] owner 同意後，主對話 push 功能分支並開 PR，確認 CI 通過：
  - 驗證：PR 的 CI check 成功；任務回報記錄 script 測試在 runner 上的結果與時間，並確認 job log 沒有出現測試造成的 annotation、job summary 沒有測試寫入的內容。
