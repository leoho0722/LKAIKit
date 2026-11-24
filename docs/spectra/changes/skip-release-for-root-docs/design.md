## Context

- 現況：「哪些變更不發版」寫在兩處，都只排除 `docs/spectra/`：
  - 觸發：`.github/workflows/release.yml` 的 `on.push.paths-ignore: ['docs/spectra/**']`，對應 release-automation「Release workflow trigger」。
  - 計畫：`release.sh` 在目前版號的 tag 已存在時，以 `git diff --name-only <tag 的 commit> HEAD -- . ':(exclude)docs/spectra'` 列出變更的檔案，沒有任何檔案時判斷為沒有可發佈的變更，對應「Release plan」的第 3 點。
- 先前的決策與 Non-Goal（都仍有效，本 change 延伸它們、不推翻）：
  - `02-add-release-automation` / 「tag 之後只有 docs/spectra 的變更時不發版」：`paths-ignore` 只看這一次 push，手動觸發時不受它限制，所以 script 裡也寫同一條規則，並以暫存 repo 測試；當時就說明「之後要排除其他路徑時也有兩處可以一起改」。
  - `02-add-release-automation` / 「只有 docs/spectra 的 push 不觸發，CD 取 main 最新的 commit，正式 run 一次只跑一個」：GitHub 只在變更的檔案全部符合時才略過。
  - `02-add-release-automation` 的 Non-Goal「`docs/spectra/` 以外的文件（例如 `CLAUDE.md`、`docs/adding-a-provider.md`）也不觸發發版：使用者只指定 Spectra 文件。」：那是當時的範圍限制，不是拒絕這個做法。本 change 依 owner 新的決定，只把根目錄的 `README.md`、`CLAUDE.md`、`AGENTS.md` 加進排除；其他文件（例如 `docs/adding-a-provider.md`）仍照常發版。
  - `02-add-release-automation` 的 Non-Goal「AI 回答「不發版」的等級」：不受影響，本 change 不改 AI 的回答。
  - `add-swift-package-foundation` 的 Non-Goal「README 與 DocC 文件。」只是那個 change 的範圍，不影響本 change。
- `docs/releasing.md` 5.2 已寫明：要排除其他路徑時，同時修改 `paths-ignore`、`release.sh` 的規則與 spec 的範例表。
- 查證（2026-11-24）：
  - GitHub 文件原文（github/docs 的 `content/actions/reference/workflows-and-actions/workflow-syntax.md`，commit `28d27064d4`，2026-11-16；以 `gh api repos/github/docs/contents/<路徑> -H 'Accept: application/vnd.github.raw'` 讀取）：
    - 「Path patterns must match the whole path, and start from the repository's root.」
    - `'**/README.md'`：「A README.md file anywhere in the repository.」；`'*.md'` 加 `'!README.md'` 的例子中，`docs/hello.md` 列在「Does not match」。所以 `README.md` 只比對根目錄的檔案。
    - `?`：「Matches zero or one of the preceding character.」；`+`：「Matches one or more of the preceding character.」；`!` 放在 pattern 開頭表示否定。這三個和 git 的 glob 語意不同。
  - GitHub 文件（docs.github.com 的 workflow syntax，paths 一節，原文）：「When all the path names match patterns in `paths-ignore`, the workflow will not run. If any path names do not match patterns in `paths-ignore`, even if some path names match the patterns, the workflow will run.」例外：push 超過 1,000 個 commit，或產生 diff 逾時，workflow 一律執行；diff 超過 3,000 個檔案、而且 filter 比對到的檔案不在前 3,000 個之中時，workflow 不執行。
  - git（本機 git 2.54.0，在暫存 repo 實測；fable 與 opus 審查時也各自實測，結果相同）：
    - `:(exclude,glob)docs/spectra/**`、`:(exclude,glob)README.md` 等 4 個 pathspec 只排除 `docs/spectra/` 底下的檔案（包含 `docs/spectra/README.md`）與根目錄的三個檔案；`docs/README.md`、`docs/CLAUDE.md`、`Sources/README.md`、`.github/AGENTS.md`、`README.md.bak`、`docs/spectra-notes.md` 都沒有被排除。
    - 不加 `glob` 的 `:(exclude)README.md` 結果相同；原本的 `:(exclude)docs/spectra` 與 `:(exclude,glob)docs/spectra/**` 結果相同。
    - git 的 `?` 是任意一個字元、`+` 是字面的加號：`:(exclude,glob)docs/x.mdx?` 排除 `docs/x.mdx` 後面多一個任意字元的檔案（例如 `docs/x.mdxy`），不排除 `docs/x.md` 與 `docs/x.mdx`；`:(exclude,glob)a+b.txt` 不排除 `ab.txt` 與 `aab.txt`。GitHub 的這兩條 pattern 則分別比對 `docs/x.md`、`docs/x.mdx`，以及 `ab.txt`、`aab.txt`（fable 與 opus 第二輪審查）。
    - 把 `Sources/` 的檔案改名到 `docs/spectra/` 或 `README.md` 時，仍列出原本的路徑，不會被誤判成只有不發版的檔案。
  - 實際紀錄：PR #10 的合併（`2703033`，只改 `docs/spectra/`）沒有開 Release run；`gh run list --workflow release.yml` 只有 PR #9 合併的那一次（run `45391671172`，從建立到結束約 2 分鐘）。

## Goals / Non-Goals

**Goals:**

- 只改 `docs/spectra/` 與根目錄 `README.md`、`CLAUDE.md`、`AGENTS.md` 的合併不開 runner；手動觸發時也不因為這些檔案升版。
- 「不發版的檔案」在 spec 只定義一次，之後再加路徑時，spec 只改這一個 requirement。
- 兩處的清單不一致到會發錯版時，bash 測試失敗，並寫出是哪一條、要改哪裡；`paths-ignore` 的寫法改變到測試讀不懂時，測試也失敗，不會默默少檢查。
- 清單只在少數幾處列出，其他說明引用它們。

**Non-Goals:**

- 不排除其他文件或設定：`docs/adding-a-provider.md`、`docs/releasing.md`、`.github/`、`LICENSE`、`.gitignore` 等照常發版。使用者這次只要求這三個檔案；要再加時依 `docs/releasing.md` 5.2 修改。
- 不比對 `docs/spectra/` 以外子資料夾中同名的檔案（例如 `docs/README.md`），也不用 `**/README.md` 或 `**.md` 這類 pattern：後者會連 `docs/` 的手冊與日後 DocC 的 Markdown 一起排除。
- 不改 CI：`ci.yml` 不依路徑篩選（continuous-integration spec），只改文件的 PR 仍要跑 CI。
- 不改 Release Notes 的變更資料：升版時，prompt 的 commit 清單與變更統計仍包含這三個檔案的變更；prompt 的 diff 本來就只含 `Sources`、`Package.swift`、`Package.resolved`、`action.yml`。
- `AGENTS.md`、`README.md` 中說明發版的句子不在本 change 修改：這兩個檔案是 `/init` 產生、還沒有 commit 的文件，它們的句子改成指向 `docs/releasing.md` 3.1、不列清單，由之後只改這三個檔案的 PR 一起合併（見 Migration Plan）。

## Decisions

### 「不發版的檔案」定義成一個 requirement，觸發與計畫都引用它

- release-automation 新增「Release-neutral files」：`docs/spectra/` 底下的檔案，以及根目錄的 `README.md`、`CLAUDE.md`、`AGENTS.md`。「Release workflow trigger」與「Release plan」的第 3 點都改成引用它。
- 觸發的情境「Decide whether a push to main runs the workflow」與它的範例表搬進「Release-neutral files」：之後再加路徑時，只要 MODIFIED 這一個 requirement（定義與兩張範例表），不必重貼「Release workflow trigger」的整段條文與情境（fable 規劃審查 S1）。「Release plan」的範例表「plans」只在本 change 加一列，之後加路徑時不必再改。
- 條文要求 `paths-ignore` 剛好每一部分一條、沒有其他 pattern（fable S2、opus S3），所以 spec 只有一個來源；1.2 的審查以這句擋下多出來的 pattern。
- 理由：之後再加路徑時只改一個 requirement，兩個 requirement 的句子不會各改各的。
- 取捨：單獨讀「Release workflow trigger」時看不到路徑的例子，要跟著引用去看。
- 考慮過的替代方案：直接在兩個 requirement 的句子各加三個檔名，範例表留在原處。可行，但每次加路徑都要重貼兩個 requirement，也沒有一個地方能完整列出「哪些檔案不發版」。

### release.sh 的排除路徑與 paths-ignore 寫成同樣的 pattern

- `release.sh` 在開頭的常數區以一個具名的陣列 `release_neutral_patterns` 列出 pattern，依序是 `docs/spectra/**`、`README.md`、`CLAUDE.md`、`AGENTS.md`，和 `paths-ignore` 逐字相同、順序相同。判斷沒有可發佈的變更時，以陣列的每一條組成 `:(exclude,glob)<pattern>` 交給 `git diff`。
- 可以照抄的只有兩種形狀：不含 `*`、`?`、`+`、`[`、`]`、`!` 的完整路徑，以及以 `/**` 結尾、前段不含這些字元的資料夾。這兩種在 GitHub 與 git 的 `:(glob)` 語意相同（Context 的查證）。其他形狀（例如含 `?`、`+`，或以 `!` 開頭）兩邊語意不同或沒有查證，要另外換算，並擴充測試（fable S3、opus W1）。
- 理由：兩邊的字串相同時，加路徑時照抄即可，測試也能直接拿 `paths-ignore` 的 pattern 推出要建立的檔案。原本的 `:(exclude)docs/spectra` 換成 `:(exclude,glob)docs/spectra/**` 結果相同。
- 考慮過的替代方案：
  - 保留 `:(exclude)docs/spectra`，再加 `:(exclude)README.md` 等三個：結果相同，但與 `paths-ignore` 的寫法不同，加路徑時要自己換算。
  - `release.sh` 在執行時讀 `release.yml` 的 `paths-ignore`：本機執行 script 也要解析 YAML，多一種失敗的可能，而且 workflow 檔案的格式改變時會在發版當下才失敗。

### 以測試確認 paths-ignore 的每一條都讓 release.sh 判斷為沒有可發佈的變更

- `test-release.sh` 新增一個測試：讀出 `release.yml` 的整個 `paths-ignore` 區塊，依序為每一條建立一個符合的檔案，每建立一個就 commit、執行一次 `release.sh`，預期沒有可發佈的變更；在第一個不是沒有可發佈的變更的 pattern 停下，失敗訊息寫出那個 pattern、建立的檔案與要改的地方（fable W2、opus S2）。這條路徑在送出 AI 請求之前就結束，多執行幾次的成本只有幾次 `release.sh`。
- 讀取的規則嚴格：區塊內每一行都必須認得，出現註解、其他引號的寫法或認不得形狀的 pattern 時測試失敗，不會在第一個認不得的行停下而少檢查後面的 pattern（fable W1、opus W2）。
- 只檢查這一個方向：`paths-ignore` 有、`release.sh` 沒有時，手動觸發會為只改這些檔案的變更升版，這正是本 change 要避免的；反方向（`release.sh` 多排除）只會多開一次 runner，並以沒有可發佈的變更結束，而且「Classify the file changed after the tag」中升版的 3 列能擋住 `release.sh` 寫得太寬（例如 `**/README.md`）。
- 理由：`paths-ignore` 無法讀取其他檔案，兩處的清單不可能共用同一個來源；以測試把它們綁在一起，CI 就能擋下只改一處的 PR。
- 考慮過的替代方案：
  - 測試中寫死預期的四條：`release.yml` 加了一條而 `release.sh` 沒加時抓不到。
  - 以文字比對兩個檔案中的清單：要解析 `release.sh` 的原始碼，綁住它的寫法。
  - 所有檔案一起 commit、只執行一次 `release.sh`：結果等價，但失敗時分不出是哪一條。

### 清單只寫在 paths-ignore、release.sh 的具名陣列與手冊 3.1，其他說明引用它們

- 列出四條 pattern 的地方只有三處：`release.yml` 的 `paths-ignore`、`release.sh` 的 `release_neutral_patterns`、`docs/releasing.md` 3.1。spec 的「Release-neutral files」是定義，另外列出範例。
- 其他地方只寫「不發版的檔案」並引用：
  - `release.yml` 開頭的註解指向它自己的 `paths-ignore`，並寫明要和 `release.sh` 的 `release_neutral_patterns` 一致、由 `test-release.sh` 檢查。
  - `release.sh` 開頭「流程」的說明與判斷旁的註解指向 `release_neutral_patterns`。
  - `docs/releasing.md` 的其他章節引用 3.1。
  - `/init` 產生的 `AGENTS.md`、`README.md` 指向 `docs/releasing.md` 3.1（不屬於本 change，見 Non-Goals）。
- `docs/releasing.md` 5.2 列出之後加路徑時要改的地方：spec 的「Release-neutral files」（定義與兩張範例表）、`paths-ignore`、`release_neutral_patterns`、3.1 的清單；並寫明只有兩種形狀可以照抄，以及測試會檢查 `paths-ignore` 的每一條都被 `release.sh` 排除。
- 理由：依原本的寫法，清單會被抄寫在十處左右，只有兩處有測試；加路徑時沒有檢查的地方會留下舊的清單（fable W4）。
- 考慮過的替代方案：每一處都列出清單，在 5.2 列全所有位置。可行，但要維護的位置多，而且 `AGENTS.md`、`README.md` 的修改不能和改 `docs/releasing.md` 放在同一個 PR 驗證（改手冊會觸發發版）。

### 觸發條件以審查與合併後的實際 push 確認

- 「Decide whether a push to main runs the workflow」只由 GitHub 評估，`run-tests.sh` 觀察不到，比照 `02-add-release-automation` 標為 spectra-exclude：
  - 實作時逐列對照 `paths-ignore` 審查範例表，依據是 Context 引用的 GitHub 文件原文。
  - 合併後，以只改 `README.md`、`CLAUDE.md`、`AGENTS.md` 的 PR（`/init` 產生的文件）確認 `main` 上沒有開 Release run。這只能確認這三條會略過；「子資料夾的同名檔案不會被略過」依文件原文判斷（fable S4）。
  - 同一次合併之後，以 dry run 手動觸發一次，確認手動觸發時判斷為沒有可發佈的變更（fable S6）；這條路徑在送出 AI 請求之前就結束，不花 AI 費用。
- 理由：GitHub 的 pattern 規則只能以文件與實際的 push 確認；手動觸發的一半有 bash 測試，再以真實環境確認一次。

## Implementation Contract

**觀察得到的行為**：

| 情況 | 結果 |
| --- | --- |
| push 到 `main`，改動的檔案全部是不發版的檔案 | 不開 Release run |
| push 到 `main`，有任何一個檔案不是不發版的檔案（例如同時改了 `README.md` 與 `Sources/`，或只改 `docs/README.md`） | 照常執行 |
| 目前版號的 tag 已有 Release，tag 之後變更的檔案全部是不發版的檔案；不論 push 或 `workflow_dispatch` 觸發，也不論是否 dry run | 報告的計畫是 `nothing-to-release`，有「沒有可發佈的變更。」一行，以 0 結束，沒有 AI 請求，不建立 commit、tag 或 Release。tag 沒有 Release 時，先依「Release repair」補建，和現在相同 |
| tag 之後還有其他檔案的變更 | 和現在相同，升版 |

**介面與檔案**：

- `.github/workflows/release.yml`：
  - `on.push.paths-ignore` 依序是 `'docs/spectra/**'`、`'README.md'`、`'CLAUDE.md'`、`'AGENTS.md'`，每一條一行，寫成 `- '<pattern>'`（單引號）。清單中不放註解與空行，說明寫在檔案開頭。
  - 開頭說明觸發的註解改寫成「改動的檔案全部是不發版的檔案時不執行」，指向下面的 `paths-ignore`，並寫明要和 `release.sh` 的 `release_neutral_patterns` 一致、由 `test-release.sh` 檢查，說明見 `docs/releasing.md` 3.1；不重抄四條 pattern。
- `.github/scripts/release/release.sh`：
  - 開頭的常數區新增陣列 `release_neutral_patterns`，四條 pattern 與 `paths-ignore` 逐字相同、順序相同；旁邊的註解寫明它和 `release.yml` 的 `paths-ignore` 一致、由測試檢查，以及只有兩種形狀可以照抄（見決策「release.sh 的排除路徑與 paths-ignore 寫成同樣的 pattern」）。
  - 判斷沒有可發佈的變更時，`git diff --name-only <tag 的 commit> HEAD -- .` 之後接陣列每一條組成的 `:(exclude,glob)<pattern>`。
  - 開頭「流程」的說明與這個判斷旁的註解，把「只有 docs/spectra/ 的變更」改成「只有不發版的檔案（`release_neutral_patterns`）的變更」。
  - 失敗的行為不變：`git diff` 出錯時照舊以「無法比較 tag … 與 HEAD 的檔案」失敗。
- `.github/scripts/release/tests/test-release.sh`：
  - 「Classify the file changed after the tag」的範例表，每一列一個測試函式：tag 0.1.0（有 Release）之後只有一個 commit，改動該列的檔案。`nothing to release` 的列以 `assert_exit_code 0`、`assert_nothing_to_release_report`、`assert_no_lkai_request`、`assert_repo_untouched` 確認；`version bump` 的列以 `assert_exit_code 0` 與 `assert_plan "version-bump" "0.1.0" "0.1.1"` 確認。
  - 「Every pattern the workflow ignores is release-neutral to the script」：
    - 讀取：在 `$REPO_ROOT/.github/workflows/release.yml` 找整行只有 `paths-ignore:`（前面只有空白）的那一行，必須剛好一行。區塊是它之後、到第一個縮排不比它深、而且不是註解的非空白行為止的所有行：YAML 的註解可以是任何縮排，不會結束清單，所以找區塊結尾時略過註解行（fable 與 opus 第二輪審查）。區塊結尾的空白行與註解行略過。區塊內其餘每一行都必須是 `- '<pattern>'`；出現其他形狀的行（包含任何縮排的註解、空行、雙引號或沒有引號）時測試失敗，訊息印出那一行。讀不到任何一條時測試失敗。
    - 每一條 pattern 要建立的檔案：不含 `*`、`?`、`+`、`[`、`]`、`!` 的 pattern 就是檔案路徑；以 `/**` 結尾、前段不含這些字元的 pattern，建立 `<前段>/release-neutral-sample.md`；其他形狀讓測試失敗，訊息寫出那個 pattern，並說明要先確認 GitHub 與 git 的語意、再擴充測試。
    - 讀取與形狀判斷寫成一個函式（例如 `read_release_neutral_patterns <workflow 檔案> <輸出檔>`），把每一條 pattern 與要建立的檔案寫進輸出檔，遇到認不得的行或形狀時以 `fail` 結束；直接在測試函式中呼叫，不放在 `$(...)` 或管線中（helpers.sh 開頭的規則）。主要的測試以真正的 `$REPO_ROOT/.github/workflows/release.yml` 呼叫它。
    - 讀取規則的測試（fable 第二輪審查 X2）：以 `$TEST_TMP` 中的 YAML 為輸入，各一個測試函式，共 6 個：清單中間有一行與清單相同縮排的註解、清單中間有一行從行首開始的註解、某一條用雙引號、一條認不得形狀的 pattern（例如 `'docs/note?.md'`）、`paths-ignore:` 底下一條都沒有、`paths-ignore` 寫成同一行的清單（例如 `paths-ignore: ['docs/spectra/**', 'README.md']`，找不到整行只有 `paths-ignore:` 的行；fable 第三輪審查 Y2）。每個測試在 subshell 中呼叫讀取的函式，確認以非 0 結束，訊息含那一行或那個 pattern。這 6 個測試不對應 spec 的情境，不加 spectra-scenario 標記；有了它們，就不必暫時修改受版本控制的 `release.yml` 來確認讀取的規則。
    - 執行：建立 tag 0.1.0（有 Release）之後，依 `paths-ignore` 的順序，每一條依序做：commit 這一條的檔案、推上 origin、記下狀態、執行一次 `release.sh`，並確認以 0 結束、計畫是 `nothing-to-release`、沒有 AI 請求，再處理下一條（不是全部 commit 完才執行一次）。第一條不符合時測試失敗，訊息寫出：`release.yml` 的 `paths-ignore` 有 `<pattern>`，但 `release.sh` 把 `<檔案>` 當成可發佈的變更；要在 `release.sh` 的 `release_neutral_patterns` 加上同一條，或從 `paths-ignore` 拿掉；見 `docs/releasing.md` 5.2。
  - 「Choose the plan」範例表新增的一列（只改 `README.md` 與 `AGENTS.md` 的兩個 commit）一個測試函式，以 `assert_exit_code 0`、`assert_nothing_to_release_report`、`assert_no_lkai_request` 確認。
  - 每個測試上方加 `# spectra-scenario: release-automation / <情境>`，有範例時再加一行 `# spectra-scenario: release-automation / <情境> / <範例>`；寫法照既有的測試，相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。
  - bash 3.2 的陷阱（opus S7，以 `/bin/bash` 3.2.57 實測）：
    - `case` 的 pattern 中，沒加引號的 `**` 等於 `*`，`*/**` 會符合 `docs/README.md`；要寫成 `*'/**'`，取前段用 `${pattern%'/**'}`。
    - 逐條處理 pattern 時用 `while IFS= read -r`，不要 `for p in $patterns`：沒加引號時會展開 glob，`docs/spectra/**` 可能被換成目前資料夾中的路徑。`while` 迴圈以 `<` 重導檔案或 here-doc 餵入，不要用管線：管線讓迴圈在 subshell 中執行，迴圈內的 `fail` 只結束那一層、測試照樣通過，迴圈內累加的值也會在迴圈結束後消失（helpers.sh 開頭的規則；opus 第二輪審查 S2）。
    - 逐條執行 `release.sh` 的迴圈，stdin 不要是 pattern 的清單：迴圈內的指令（commit、push、`release.sh` 與它呼叫的指令）只要讀了 stdin，就會吃掉清單剩下的行，迴圈提早結束、測試照樣通過（fable 第三輪審查 Y1、opus 第三輪審查 S1）。先把 pattern 讀進陣列，再以 `for pattern in "${patterns[@]}"` 執行（加了引號不會展開 glob），或以 `read -r -u 3` 搭配 `3<檔案` 讀取；迴圈結束後確認執行 `release.sh` 的次數等於讀到的 pattern 數。
    - `[[ $line =~ … ]]` 的 regex 含單引號時，先放進變數再比對；把 regex 加上引號時，bash 3.2 會把加引號的部分當成字面。
- `docs/releasing.md`：
  - 3.1「push 到 `main`」：列出不發版的檔案（`docs/spectra/` 底下的檔案，以及根目錄的 `README.md`、`CLAUDE.md`、`AGENTS.md`；`docs/spectra/` 以外子資料夾中同名的檔案照常發版），改動的檔案全部是它們時不執行；舉例 `docs/` 的其他文件與 `.github/` 仍會發版。這是手冊中唯一列出清單的地方。
  - 第 2 章「計畫」的兩項、3.3 最後一項、4.1 表格「推送」一列：把「`docs/spectra/` 的變更」改成「不發版的檔案（見 3.1）的變更」。
  - 4.1 表格第一列、4.4 與 5.2 中「下一次合併」的說法改成「下一次會觸發的合併（見 3.1）」：只改不發版的檔案的合併不會觸發（fable S7、opus 第二輪審查 S4）。4.3 的「下一個合併」說的是一個特定的 PR，不必改。
  - 5.2：改寫「只改 `docs/spectra/` 以外的文件也會觸發發版」那一項，依決策「清單只寫在 paths-ignore、release.sh 的具名陣列與手冊 3.1，其他說明引用它們」寫出之後加路徑時要改的地方與注意事項。

**驗收**：

- `bash .github/scripts/release/tests/run-tests.sh` 在本機以 `/bin/bash`（3.2）執行全部通過，以 `GITHUB_ACTIONS=true` 再執行一次，結果相同；CI 以 runner 預設的 bash 執行。
- `actionlint` 以 0 結束；`shellcheck -x -s bash` 檢查 `release.sh` 與 `test-release.sh` 沒有新的警告。
- 測試先於實作：
  - 修改 `release.yml` 與 `release.sh` 之前：「Classify」的 `README.md`、`CLAUDE.md`、`AGENTS.md` 三列與「plans」新增的一列失敗（計畫是升版）；「Classify」的其他 5 列、讀 `paths-ignore` 的測試（此時只有 `docs/spectra/**`）、讀取規則的 6 個測試與所有既有的測試通過。
  - 只改 `release.yml` 之後：讀 `paths-ignore` 的測試失敗，訊息寫出第一條 `release.sh` 沒有排除的 pattern `README.md`。
  - 改完 `release.sh` 之後：全部通過。
- `grep -n 'AGENTS.md' .github/workflows/release.yml .github/scripts/release/release.sh docs/releasing.md` 只出現在 `paths-ignore`、`release_neutral_patterns` 與手冊 3.1 的清單；5.2 與其他說明只寫「不發版的檔案」並引用，不出現這個檔名。
- PR 的 CI 通過；合併後依 Migration Plan 確認。

**範圍**：

- 範圍內：上面列出的四個檔案，以及本 change 的 spec。
- 範圍外：`ci.yml`、`action.yml`、`make-prompt.sh` 與 prompt 範本、`docs/spectra/config.yaml`、`AGENTS.md`、`README.md`、`CLAUDE.md`。

## Risks / Trade-offs

- [GitHub 的 pattern 比對範圍和文件不同] → 依文件原文；合併後實際的 push 只能確認三條 pattern 會略過。就算比對到更多檔案，也只是那些 push 不開 runner；`release.sh` 仍把它們算成可發佈的變更，下一次發版會包含它們。
- [push 超過 1,000 個 commit 或產生 diff 逾時時，GitHub 一律執行 workflow] → `release.sh` 自己的判斷仍會以沒有可發佈的變更結束，不會發版。
- [diff 超過 3,000 個檔案時，GitHub 可能不執行 workflow] → 本 change 沒有改變這個風險：被略過的變更，下一次執行從 tag 起算時會包含。
- [合併本 change 的那一次會發版] → 本 change 改到 `.github/`，不是只有不發版的檔案；這是預期的，升級等級由 AI 判斷。
- [之後的 pattern 不是那兩種形狀] → 讀 `paths-ignore` 的測試在遇到其他形狀時失敗，要先確認兩邊的語意、換算 `release.sh` 的寫法，再擴充測試。
- [測試讀 `paths-ignore` 依賴固定的寫法] → 寫法在 Implementation Contract 寫明；區塊內有認不得的行，或讀不到任何一條時，測試失敗而不是通過。
- [排除清單之後越來越長] → 這是「排除」的寫法，每遇到一類不該發版的檔案就要加一條（例如 `LICENSE`、`docs/` 的手冊、`.github/`、`Tests/`）。之後要加第三批，或想表達「只有程式與 package 設定才發版」時，再評估改成正向清單（和 `make-prompt.sh` 的 diff 範圍 `Sources`、`Package.swift`、`Package.resolved`、`action.yml` 對齊），或 `02-add-release-automation` Non-Goal 記下的「AI 多一個不發版的回答」（fable 規劃審查的觀察）。這次的範圍由 owner 決定，不在本 change 處理。

## Migration Plan

1. 本 change 的 PR 合併到 `main`：改到 `.github/`，release workflow 會執行一次並升版。等那次 run 成功結束（`gh run watch <run>`），並以 `gh release list` 確認新的 tag 與 Release 已建立，才進行第 2 步。那次 run 失敗時，先依 `docs/releasing.md` 4.1 處理完。
   - 理由：那次 run 取出 `main` 之後、推送之前，要是又合併了只改不發版的檔案的 PR，升版的 push 會因為 `main` 多了 commit 被拒絕；而那次合併依本 change 不會觸發，沒有等待中的 run 接手（fable W3）。
2. 合併只改 `README.md`、`CLAUDE.md`、`AGENTS.md` 的 PR（`/init` 產生的文件）：`gh run list --workflow release.yml --commit <合併的 commit>` 沒有結果。
3. 以 `gh workflow run release.yml -f dry_run=true` 手動試跑一次：報告（job summary）的計畫是 `nothing-to-release`，有「沒有可發佈的變更。」一行，沒有「升級等級：」「補建的 Release：」與「Release Notes：」。`release.sh` 送出 AI 請求時不印紀錄，所以以報告的這幾行確認沒有送出請求（opus 第二輪審查 S3）。
4. 封存本 change 的 PR 只改 `docs/spectra/`，同樣不會發版。
5. 要回退時 revert 本 change 的 PR；revert 本身改到 `.github/`，會再執行一次 release workflow。
