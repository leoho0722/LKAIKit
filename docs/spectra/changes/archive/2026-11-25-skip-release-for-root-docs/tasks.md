實作的做法：

- **新行為先寫測試**：先寫 1.1 的測試，觀察到應該失敗的測試確實失敗，才修改 `release.yml` 與 `release.sh`。
- **spec 標記**：每個為 spec 情境寫的測試函式上方加 `# spectra-scenario: release-automation / <情境>`，有範例時再加一行 `# spectra-scenario: release-automation / <情境> / <範例>`，名稱照抄 spec；範例表的每一列都要有對應的斷言。
- **寫法的限制**：沿用發版 script 的寫法限制（每支 script 開頭的註解）：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法；變數後面緊接著中文或全形標點時寫成 `${名稱}`；並避開 design Implementation Contract 列出的 bash 3.2 陷阱。每個任務都以本機的 `/bin/bash`（3.2.57）執行 `bash .github/scripts/release/tests/run-tests.sh`。
- **用語**：換行字元寫 LF、CR、CRLF，不寫「回車」；「換行」只指一行結束。註解與訊息以正體中文撰寫。
- **規劃審查**：本文件與 design 已依 fable 與 opus 的規劃審查（2026-11-24）修正；design 中標註的 W、S 編號是審查報告的編號。

## 1. 不發版的檔案

- [x] 1.1 依 design「以測試確認 paths-ignore 的每一條都讓 release.sh 判斷為沒有可發佈的變更」與 Implementation Contract 的 `test-release.sh` 一項，先在 `.github/scripts/release/tests/test-release.sh` 寫測試，涵蓋 release-automation「Release-neutral files」與「Release plan」新增的範例：
  - 「Classify the file changed after the tag」的範例表「changed file and plan」：8 列各一個測試函式，tag 0.1.0（有 Release）之後只有一個 commit 改動該列的檔案；`nothing to release` 的列確認退出碼 0、沒有可發佈的變更的報告、沒有 AI 請求、repo 沒有改變；`version bump` 的列確認退出碼 0、計畫是 `version-bump`、上一版 `0.1.0`、新版號 `0.1.1`。
  - 「Every pattern the workflow ignores is release-neutral to the script」：一個測試函式，依 Implementation Contract 讀 `release.yml` 的整個 `paths-ignore` 區塊，依序為每一條 commit 一個檔案並執行 `release.sh`，預期每次都是沒有可發佈的變更，而且執行 `release.sh` 的次數等於讀到的 pattern 數；第一條不符合時，失敗訊息寫出 pattern、建立的檔案與要改的地方。區塊內有認不得的行、遇到認不得形狀的 pattern，或讀不到任何一條時，測試失敗並寫出原因。讀取與形狀判斷寫成 Implementation Contract 描述的函式。
  - 讀取規則的 6 個測試（Implementation Contract 的 `test-release.sh` 一項）：以 `$TEST_TMP` 中的 YAML 為輸入，確認清單中間有相同縮排的註解、從行首開始的註解、雙引號、認不得形狀的 pattern、一條都沒有、寫成同一行的清單，這 6 種寫法都讓讀取以非 0 結束，訊息含那一行、那個 pattern，或說明找不到整行只有 `paths-ignore:` 的行。不加 spectra-scenario 標記。
  - 「Choose the plan」範例表「plans」新增的一列（2 個只改 `README.md` 與 `AGENTS.md` 的 commit）：一個測試函式，預期退出碼 0、沒有可發佈的變更、沒有 AI 請求。
  - 驗證：
    - 以 `/bin/bash` 執行 `run-tests.sh`，記錄結果。預期在修改 `release.yml` 與 `release.sh` 之前，「Classify」的 `README.md`、`CLAUDE.md`、`AGENTS.md` 三列與「plans」新增的一列失敗（計畫是升版）；「Classify」的其他 5 列、讀 `paths-ignore` 的測試（此時只有 `docs/spectra/**`）、讀取規則的 6 個測試與所有既有的測試通過。
    - 讀取規則的 6 個測試在修改前就通過（它們不依賴真正的 `release.yml` 的內容）；以 `git diff .github/workflows/release.yml` 確認本任務沒有修改它。
  - 執行紀錄（2026-11-24，主對話，分支 `feat/skip-release-for-root-docs`）：
    - 新增的測試：「Classify」8 個、讀 `paths-ignore` 的 1 個、讀取規則失敗的 6 個，另加 1 個成功情況的讀取規則測試（清單結尾、下一個 key 上方的註解與空行略過；這是讀取函式的一個分支），以及「plans」新增的一列 1 個，共 17 個。
    - 以 `/bin/bash`（3.2.57）執行 `run-tests.sh`：共 139 個，通過 135 個，失敗 4 個，正是預期的 4 個（「Classify」的 `README.md`、`CLAUDE.md`、`AGENTS.md` 與 `test_release_plan_with_only_root_doc_changes_after_the_tag_has_nothing_to_release`），失敗的原因是計畫為 `version-bump`（升級等級 patch、新版號 0.1.1）；修改前是 122 個全部通過。
    - 讀取規則的測試一寫完就通過，所以做了變異檢查：暫時拿掉「清單中間有空行或註解」的判斷，兩個註解的測試失敗；暫時拿掉形狀的判斷，`docs/note?.md` 的測試失敗；確認後還原（`cmp` 與備份相同）。
    - `shellcheck -x -s bash test-release.sh` 修改前後都沒有輸出；`git diff --stat` 確認 `release.yml` 與 `release.sh` 沒有修改。
- [x] 1.2 [after: 1.1] 依 design「「不發版的檔案」定義成一個 requirement，觸發與計畫都引用它」與「清單只寫在 paths-ignore、release.sh 的具名陣列與手冊 3.1，其他說明引用它們」，在 `.github/workflows/release.yml` 的 `paths-ignore` 依序加上 `'README.md'`、`'CLAUDE.md'`、`'AGENTS.md'`，並改寫開頭說明觸發的註解（指向 `paths-ignore`，不重抄 pattern），交付 release-automation「Release workflow trigger」：push 改動的檔案全部是不發版的檔案時不執行。
  - 驗證：
    - `run-tests.sh` 中讀 `paths-ignore` 的測試此時失敗，訊息寫出 `release.sh` 沒有排除的第一條 pattern `README.md`，證明它抓得到兩處不一致；記錄失敗的輸出。
    - `actionlint .github/workflows/release.yml` 以 0 結束、沒有輸出。
    - `git diff` 只改了 `paths-ignore` 與註解，其他 trigger、`permissions`、`concurrency`、step 都沒有改變。
    - 依 design「觸發條件以審查與合併後的實際 push 確認」，逐列對照「Release-neutral files」的範例表「changed files and whether the workflow runs」的 9 列與新的 `paths-ignore`，並確認 `paths-ignore` 剛好四條、沒有其他 pattern；記錄審查結果。實際的 push 在 3.4 確認。
  - 執行紀錄（2026-11-24，主對話）：
    - `run-tests.sh`（`/bin/bash` 3.2.57）：共 139 個，通過 134 個，失敗 5 個：1.1 的 4 個，加上 `test_release_neutral_files_every_ignored_pattern_has_nothing_to_release`，訊息是「release.yml 的 paths-ignore 有 README.md，但 release.sh 把 README.md 當成可發佈的變更」，並寫出要改的地方。
    - `actionlint .github/workflows/release.yml` 以 0 結束、沒有輸出。
    - `git diff`：只改了開頭說明觸發的註解（改成引用 `paths-ignore`，不重抄 pattern）與 `paths-ignore` 新增的三行；trigger 的其他部分、`permissions`、`concurrency`、step 都沒有改變。
    - 範例表「changed files and whether the workflow runs」逐列對照新的 `paths-ignore`（依據是 design Context 引用的 GitHub 文件原文：pattern 從 repo 根目錄比對完整路徑、全部符合才略過）：第 1–4 列每個檔案都符合其中一條，不執行；第 5–9 列各有一個檔案不符合任何一條（`Sources/LKAICore/LKAIKitInfo.swift`、`docs/README.md`、`docs/adding-a-provider.md`、`.github/workflows/ci.yml`），執行。`paths-ignore` 剛好四條：`docs/spectra/**` 一條，三個檔案各一條，沒有其他 pattern。
    - 本任務開始時漏了 `spectra task start`，修改 `release.yml` 之後才記下基準線，所以完成時以 `--file .github/workflows/release.yml` 指定修改的檔案。
  - spectra-exclude: release-automation / Decide whether a push to main runs the workflow | 觸發條件只由 GitHub Actions 評估，run-tests.sh 觀察不到；由本任務依 GitHub 文件原文逐列對照 paths-ignore 審查，合併後由 3.4 以實際的 push 確認
  - spectra-exclude: release-automation / Decide whether a push to main runs the workflow / changed files and whether the workflow runs | 同上：範例表的 9 列由本任務逐列對照 paths-ignore 審查
  - spectra-exclude: release-automation / A push by the release workflow itself | 本 change 不改變這個行為，GitHub 的行為測試環境觀察不到；由本任務確認 release.yml 的 diff 沒有動到 checkout 與 GH_TOKEN
  - spectra-exclude: release-automation / Two pushes in quick succession | 本 change 不改變這個行為，排隊由 GitHub Actions 執行；由本任務確認 release.yml 的 diff 沒有動到 concurrency 與 checkout
  - spectra-exclude: release-automation / A dry run while a release run waits | 本 change 不改變這個行為，concurrency group 由 GitHub Actions 求值；由本任務確認 release.yml 的 diff 沒有動到 concurrency
- [x] 1.3 [after: 1.2] 依 design「release.sh 的排除路徑與 paths-ignore 寫成同樣的 pattern」，在 `.github/scripts/release/release.sh` 開頭的常數區新增陣列 `release_neutral_patterns`（與 `paths-ignore` 逐字相同、順序相同），判斷沒有可發佈的變更時以它組成 `:(exclude,glob)<pattern>`，並把開頭「流程」的說明與判斷旁的註解改成引用它，交付 release-automation「Release plan」第 3 點與「Release-neutral files」：目前版號的 tag 之後只有不發版的檔案的變更時，不論觸發方式，以 0 結束、不發版。
  - 驗證：
    - `run-tests.sh` 以 `/bin/bash` 全部通過，包含 1.1 的所有新測試；再以 `GITHUB_ACTIONS=true` 執行一次，結果相同。
    - `shellcheck -x -s bash .github/scripts/release/release.sh .github/scripts/release/tests/test-release.sh` 沒有新的警告（與修改前的輸出比較）。
    - `git diff` 中，`release.sh` 只改了常數區、這個判斷的 pathspec 與註解，失敗的訊息與其他步驟沒有改變。
  - 執行紀錄（2026-11-24，主對話）：
    - `run-tests.sh`（`/bin/bash` 3.2.57）：共 139 個，全部通過；以 `GITHUB_ACTIONS=true` 再執行一次，共 139 個全部通過，每個測試的 PASS／FAIL 和第一次逐行相同。
    - `shellcheck -x -s bash .github/scripts/release/release.sh .github/scripts/release/tests/test-release.sh` 沒有輸出，修改前的 `release.sh` 也沒有輸出，沒有新的警告。
    - `git diff`：`release.sh` 只改了開頭「流程」的說明、常數區新增的 `release_neutral_patterns`、判斷沒有可發佈的變更時的 pathspec（以陣列組成 `:(exclude,glob)<pattern>`）與旁邊的註解；「無法比較 tag … 與 HEAD 的檔案」的失敗訊息與其他步驟沒有改變。這段判斷在 script 的最上層，所以新的變數照既有的寫法不加 `local`，名稱加上 `release_neutral_` 前綴。

## 2. 發版手冊

- [x] 2.1 [after: 1.3] 依 Implementation Contract 的 `docs/releasing.md` 一項與 design「清單只寫在 paths-ignore、release.sh 的具名陣列與手冊 3.1，其他說明引用它們」，更新手冊，讓它和新的 release-automation spec 一致：3.1 是手冊中唯一列出不發版的檔案的地方；第 2 章「計畫」的兩項、3.3 最後一項、4.1 表格「推送」一列引用 3.1；4.1 表格第一列、4.4 與 5.2 中「下一次合併」的說法改成「下一次會觸發的合併（見 3.1）」（4.3 的「下一個合併」不改）；5.2 寫出之後加路徑時要改的地方（spec 的「Release-neutral files」與兩張範例表、`paths-ignore`、`release_neutral_patterns`、3.1 的清單）、只有兩種形狀可以照抄，以及測試會檢查 `paths-ignore` 的每一條都被 `release.sh` 排除。
  - 驗證：內容審查，逐項對照 release-automation 的 delta spec 與 1.2、1.3 的實作；`grep -n 'docs/spectra/' docs/releasing.md` 列出的每一處，都確認不再只以 `docs/spectra/` 說明不發版的條件（權威順序與檔案路徑的提及除外）；`grep -n '下一次合併' docs/releasing.md` 沒有結果。
  - 執行紀錄（2026-11-24，主對話）：
    - 修改的地方：第 2 章「計畫」的兩項（改成引用 3.1，並註明手動觸發時也一樣）、3.1（唯一列出不發版的檔案的地方，並說明兩處清單的角色與手動觸發的行為）、3.3 最後一項、4.1 表格第一列與「推送」一列、4.4、5.2 的兩項（之後加路徑時要改的地方、只有兩種形狀可以照抄、測試會檢查的事；以及「下一次會觸發的合併」）。
    - 內容審查：3.1 的清單和 delta spec「Release-neutral files」的定義相同（`docs/spectra/` 底下的檔案，以及根目錄的三個檔案；`docs/spectra/` 以外子資料夾中同名的檔案照常發版）；5.2 列出的位置和 1.2、1.3 的實作一致（`paths-ignore`、`release_neutral_patterns`、`test-release.sh` 的讀取規則）。
    - `grep -n 'docs/spectra/' docs/releasing.md`：剩下第 9、10 行（權威順序）、3.1 清單本身的兩行，以及 5.2 的 `docs/spectra/config.yaml`（路徑），都不是以 `docs/spectra/` 說明不發版的條件。`grep -n '下一次合併' docs/releasing.md` 沒有結果。

## 3. 驗收

- [x] 3.1 [after: 1.3, 2.1] 主對話在功能分支上做整體檢查：`run-tests.sh` 以 `/bin/bash` 全部通過；`actionlint` 以 0 結束；`spectra validate skip-release-for-root-docs` 通過；`grep -n 'AGENTS.md' .github/workflows/release.yml .github/scripts/release/release.sh docs/releasing.md` 只出現在 `paths-ignore`、`release_neutral_patterns` 與手冊 3.1 的清單；`git diff --stat main...HEAD`（只比對分支上的 commit，不含工作目錄中還沒 commit 的 `/init` 文件）只有 Implementation Contract 範圍內的四個檔案與本 change 的文件。
  - 執行紀錄（2026-11-24，主對話，commit `a1a2d03`、`d8f352a`）：`run-tests.sh`（`/bin/bash` 3.2.57）共 139 個全部通過；`actionlint`（全部 workflow）以 0 結束、沒有輸出；`spectra validate skip-release-for-root-docs` 通過；`grep -n 'AGENTS.md' …` 只有 `release.yml` 的 `paths-ignore`、`release.sh` 的 `release_neutral_patterns` 與手冊 3.1 的清單三處；`git diff --stat main...HEAD` 是 `release.sh`、`test-release.sh`、`release.yml`、`docs/releasing.md` 與本 change 的 5 個文件，工作目錄中 `/init` 產生的 `AGENTS.md`、`CLAUDE.md`、`README.md` 沒有 commit。
- [x] 3.2 [after: 4.2] owner 同意後，主對話 push 功能分支並開 PR；驗證：PR 的 CI 通過（`gh pr checks`），並記錄 run 的連結。
  - 執行紀錄（2026-11-25，主對話；owner 在對話中同意「套用後再 push 開 PR」）：push `feat/skip-release-for-root-docs`，開 PR #11（https://github.com/leoho0722/LKAIKit/pull/11）。CI 的 `test` job 在 HEAD `aaa0cf5` 上通過（run 45438814110，https://github.com/leoho0722/LKAIKit/actions/runs/45438814110 ，4 分 41 秒，conclusion `success`）；log 中發版 script 的測試是「共 142 個測試，通過 142 個，失敗 0 個」。
- [x] 3.3 [after: 3.2] owner 合併 PR 之後，依 design 的 Migration Plan 第 1 步確認本 change 的合併開了一次 Release run（預期，因為改到 `.github/`），並等它成功結束（`gh run watch <run>`）；驗證：`gh release list` 列出新的 tag 與 Release。run 失敗時先依 `docs/releasing.md` 4.1 處理完，才進行 3.4。記錄 run 的連結與新版號。
  - 執行紀錄（2026-11-25，主對話）：owner 合併 PR #11（merge commit `0473089`，2026-11-24T16:48:01Z）。它觸發 Release run 45441321144（https://github.com/leoho0722/LKAIKit/actions/runs/45441321144 ，push，16:48:04Z 開始），以 `gh run watch` 等到成功結束；報告是「計畫：version-bump／升級等級：patch／上一版：0.1.0／新版號：0.1.1」。`main` 多了版號 commit `037f923`（chore: 版本號更新為 0.1.1），`gh release list` 列出 `0.1.1`（Latest，16:49:54Z 建立），tag `0.1.1` 已推上 remote。
- [x] 3.4 [after: 3.3] owner 合併只改 `README.md`、`CLAUDE.md`、`AGENTS.md` 的 PR（`/init` 產生的文件）之後，依 Migration Plan 第 2 步確認；驗證：`gh run list --workflow release.yml --commit <合併的 commit>` 沒有結果。記錄合併的 commit 與查詢結果。
  - 執行紀錄（2026-11-25，主對話；owner 在對話中指示由主對話合併並刪除分支）：在 3.3 的 Release run 成功之後，從 `main`（`037f923`）開分支 `docs/init-agent-docs`，只 commit `CLAUDE.md`、`AGENTS.md`、`README.md`（`7bfff33`），開 PR #12（https://github.com/leoho0722/LKAIKit/pull/12 ，變更的檔案只有這三個）。PR 的 CI 通過（run 45441999004，4 分 10 秒）後，以 `gh pr merge 12 --merge --delete-branch` 合併（merge commit `d6f6ba2`，2026-11-24T16:56:28Z），遠端與本地的分支都已刪除。合併約 75 秒後查詢：`gh run list --workflow release.yml --commit d6f6ba27d6f5f288d35e42c7d6243443b0de7714` 是 0 筆，這個 commit 也沒有其他 workflow run；release workflow 最近的 run 仍是 3.3 的 45441321144。
- [x] 3.5 [after: 3.4] owner 同意後，主對話以 `gh workflow run release.yml -f dry_run=true` 手動試跑一次，依 Migration Plan 第 3 步確認手動觸發也不因為不發版的檔案升版；驗證：那次 run 的報告（job summary）中計畫是 `nothing-to-release`、有「沒有可發佈的變更。」一行，沒有「升級等級：」「補建的 Release：」與「Release Notes：」（`release.sh` 送出 AI 請求時不印紀錄，以這幾行確認沒有送出請求）。記錄 run 的連結。
  - 執行紀錄（2026-11-25，主對話；owner 在對話中指示「最後跑完 dry run 再封存 change」）：在 3.4 之後執行 `gh workflow run release.yml -f dry_run=true`，run 45443271255（https://github.com/leoho0722/LKAIKit/actions/runs/45443271255 ，workflow_dispatch，HEAD `d6f6ba2`，16:58:22Z 到 16:59:53Z，conclusion `success`）。報告是「模式：dry-run／供應商：anthropic／模型：claude-opus-5-5／計畫：nothing-to-release」加上「沒有可發佈的變更。」，沒有「升級等級：」「補建的 Release：」與「Release Notes：」。GitHub 的 API 讀不到 job summary，所以以 job log 中同一份報告確認（`docs/releasing.md` 3.6：stdout 與 job summary 是同一份資料）。

## 4. 實作審查的修正

實作審查（2026-11-25）：`/spectra-verify`、`/spectra-review`、fable 與 opus 都沒有需要修正的項目；owner 決定先套用下列建議再 push。第 4 組的任務在 3.1 之後、3.2 之前完成，3.2 因此改成排在 4.2 之後。

- [x] 4.1 [after: 3.1] 依 design「release.sh 的排除路徑與 paths-ignore 寫成同樣的 pattern」更新後的形狀規則，收緊 `.github/scripts/release/tests/test-release.sh` 的讀取規則，並修正註解、失敗訊息與手冊：
  - 讀取函式拒絕以 `/` 結尾、含 `//` 或 `.`、`..` 路徑片段的 pattern；多收一個 repo 根目錄的引數，有給時拒絕在其中是資料夾的檔案路徑 pattern，訊息提示改成 `<pattern>/**`；主要的測試以 `$REPO_ROOT` 呼叫。認不得形狀的訊息寫出可以照抄的兩種形狀與「資料夾要寫成 `<資料夾>/**`」；一條都讀不到的訊息補上縮排的說明；說明形狀規則的註解指向 `docs/releasing.md` 5.2。
  - 新增 3 個讀取規則的測試：`'docs/spectra/'`、`'./README.md'`、在暫存的根目錄中是資料夾的 `'Tests'`，三種都讓讀取以非 0 結束，訊息含那個 pattern 或改成 `/**` 的提示。不加 spectra-scenario 標記。
  - `.github/workflows/release.yml` 開頭的註解與 `.github/scripts/release/release.sh` 的 `release_neutral_patterns` 旁的註解：照實寫出測試只檢查 `paths-ignore` 的每一條都被排除，順序只是方便對照；`release.sh` 的註解補上「資料夾要寫成 `<資料夾>/**`」與完整路徑的定義。
  - `docs/releasing.md` 5.2：同樣的形狀定義與兩處清單的關係。
  - 驗證：新的 3 個測試在收緊讀取規則之前失敗（讀取成功、測試要求失敗），收緊之後通過；以 `/bin/bash` 執行 `run-tests.sh` 全部通過，`GITHUB_ACTIONS=true` 再跑一次結果相同；`shellcheck -x -s bash` 與 `actionlint` 沒有輸出；`git diff` 中 `release.yml` 與 `release.sh` 只改了註解。
  - 執行紀錄（2026-11-25，主對話）：
    - 先寫的 3 個測試（`test_release_neutral_reading_rejects_a_pattern_ending_with_a_slash`、`…_with_a_dot_segment`、`…_that_names_a_directory`）在收緊之前失敗，原因都是「讀取應該失敗」（讀取成功）：`run-tests.sh` 共 142 個，通過 139 個，失敗 3 個。
    - 收緊之後：讀取函式以新的 `is_plain_path` 拒絕空的、以 `/` 開頭或結尾、含 `//` 或 `.`、`..` 路徑片段的路徑；多收的 repo 根目錄引數有給時，拒絕在其中是資料夾的檔案路徑 pattern；主要的測試以 `$REPO_ROOT` 呼叫。`run-tests.sh`（`/bin/bash` 3.2.57）共 142 個全部通過；`GITHUB_ACTIONS=true` 再跑一次，共 142 個全部通過，PASS／FAIL 逐行相同。
    - `shellcheck -x -s bash release.sh tests/test-release.sh` 與 `actionlint` 都沒有輸出；`git diff -U0` 中 `release.yml` 與 `release.sh` 改動的行全部是註解。
    - 註解與手冊：`release.yml`、`release.sh` 照實寫出測試只檢查 `paths-ignore` 的每一條都被排除（不檢查順序與 `release.sh` 多出來的 pattern），順序只是方便對照；`release.sh` 與手冊 5.2 寫出完整路徑的定義與「資料夾要寫成 `<資料夾>/**`」；`has_glob_character` 與 `is_plain_path` 的註解指向手冊 5.2；一條都讀不到的訊息補上縮排的說明。
- [x] 4.2 [after: 4.1] 主對話重做 3.1 的整體檢查並 commit：`run-tests.sh` 以 `/bin/bash` 全部通過；`actionlint` 以 0 結束；`spectra validate skip-release-for-root-docs` 通過；`grep -n 'AGENTS.md' .github/workflows/release.yml .github/scripts/release/release.sh docs/releasing.md` 只出現在 `paths-ignore`、`release_neutral_patterns` 與手冊 3.1 的清單；`git diff --stat main...HEAD` 只有 Implementation Contract 範圍內的四個檔案與本 change 的文件。記錄 commit。
  - 執行紀錄（2026-11-25，主對話，commit `5830874`）：`run-tests.sh`（`/bin/bash` 3.2.57）共 142 個全部通過；`actionlint` 以 0 結束、沒有輸出；`spectra validate skip-release-for-root-docs` 通過；`grep -n 'AGENTS.md' …` 只有 `release.yml` 的 `paths-ignore`、`release.sh` 的 `release_neutral_patterns` 與手冊 3.1 的清單三處；`git diff --stat main...HEAD` 是 `release.sh`、`test-release.sh`、`release.yml`、`docs/releasing.md` 與本 change 的 5 個文件，`/init` 產生的三份文件沒有 commit。
