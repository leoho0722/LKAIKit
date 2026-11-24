## Context

**由來**：這個 change 原本是 `add-ci-cd` 的發版部分。2026-11-24 由 fable（架構）與 opus（正確性）做規劃審查，兩人都沒有 Critical。使用者依審查建議拆成兩個 change（`01-add-ci` 的決策「拆成 01-add-ci 與 02-add-release-automation」）。

拆分後的第二輪審查（2026-11-24）：fable 沒有 Warning，有 7 項 Suggestion；opus 有 3 項 Warning、5 項 Suggestion。都已處理，主要的修改：

- 補建 Release 與失敗時的保證不再矛盾。
- 測試隔離 GitHub Actions 的環境變數。
- `iconv` 的退出碼。
- 有沒有 Release 改以 `gh release list` 判斷。
- 供應商與模型的優先順序移進 script。
- 報告的步驟名稱補齊。
- AI 文字的保護規則寫清楚。

`01-add-ci` 合併後的實作前審查（2026-11-24）：兩人都沒有 Critical；opus 有 1 項 Warning、3 項 Suggestion，fable 有 3 項 Suggestion 與 4 個小項，都是 01 合併後才過時的前提或用語，都已處理。主要的修改：

- CI 的 script 測試規則改放 continuous-integration（決策「CI 的 script 測試規則放在 continuous-integration，測試的隔離留在 release-automation」）。
- `release.yml` 的 checkout 加上不可設定 `persist-credentials: false` 的註解。
- 數字、工具與「已解決」的用語更新。

本 change 依賴 `01-add-ci`：

- 使用它的 `action.yml`：沒有 input，輸出 `path` 與 `version`，release 版的 `lkai` 留在建置資料夾並加進 `PATH`。
- 在它的 `.github/workflows/ci.yml` 加上 script 測試。

`01-add-ci` 已於 2026-11-24 合併（PR #8，merge commit `33210e7`），本 change 可以開始實作。

**現況**（2026-11-23 查看，2026-11-24 由兩位審查者複查）：

- repo 是 public，沒有任何 tag 或 release。`main` 沒有 branch protection（`gh api repos/leoho0722/LKAIKit/branches/main/protection` 回 404），rulesets 是空的。
- `LKAIKitInfo.version` 是 `0.1.0`，宣告寫成 `public static let version: String = "0.1.0"`，`///` 寫「發佈新版時手動更新這個值」。測試都讀 `LKAIKitInfo.version`，沒有寫死 `0.1.0`（`grep -rn "0\.1\.0" Tests Sources` 只出現在 `LKAIKitInfo.swift`）。
- `lkai`：
  - `--provider` 的值是 `anthropic`、`openai`、`google`。Gemini 的值是 `google`，環境變數是 `LKAI_GEMINI_API_KEY`。
  - 送出的請求只有一則使用者訊息、沒有系統指示，輸出上限預設 4096，`--timeout` 預設 60 秒（cli-chat spec）。
  - 不加 `--stream` 時也是由串流彙整，所以 `--timeout` 是「多久沒收到資料就放棄」，不是整段回應的上限（opus 審查確認）。
- 本機的 Keychain 存有三家的金鑰，service 名稱是 `lkai-<供應商>-api-key`（`docs/adding-a-provider.md` 第 3 章）。
- `docs/adding-a-provider.md` 以單獨的編號（「01」到「04」）稱呼 2026-11-22、23 的那一組 change，和本 change 與 `01-add-ci` 的編號相撞（fable 第二輪審查 N5）；兩個 change 留下的出處一律寫完整名稱，`01-add-ci` 的任務 1.3 在清單第 3 章補上說明。

**查證結果**：

1. **Runner**：`xcode-27` runner 的 bash 是 3.2.57（runner-images 的 `xcode-27-arm64` README，image 20261104.0337.1），和本機的 `/bin/bash` 相同。`01-add-ci` 在 PR #8 上的 CI 實測：runner 預設的 Xcode 27.1 帶 Swift 6.4（swiftlang-6.4.0.34.1），能編譯這個 package；bash 確實是 3.2.57；action 的 release 建置約 41 秒，`swift test` 的 step 約 38 秒。runner-images 的 `install-git.sh` 沒有設定 `user.name` 與 `user.email`（opus 審查），所以 commit 的身分要明確指定。
2. **GitHub Actions 的行為**（官方文件，2026-11-23 與 2026-11-24）：
   - `paths-ignore`：
     - 「When all the path names match patterns in `paths-ignore`, the workflow will not run.」
     - 一次 push 超過 1,000 個 commit，或 diff 逾時，workflow 一律執行。
     - diff 超過 3,000 個檔案、而且符合條件的檔案不在前 3,000 個之內時，workflow 不執行。
   - 「events triggered by the `GITHUB_TOKEN` will not create a new workflow run」，例外是 `workflow_dispatch` 與 `repository_dispatch`。
   - concurrency：
     - 同一個 group「at most one running job or workflow」。
     - 「By default, any existing `pending` job or workflow in the same concurrency group will be canceled and the new queued job or workflow will take its place.」
     - 另有 `queue` 屬性（預設 `single`；`max` 最多 100 個 pending）。
   - `workflow_dispatch`：「This trigger only receives events when the workflow file is on the default branch.」
   - 運算式：
     - `github.event.inputs` 會把 boolean 轉成字串；型別不同的比較會兩邊都轉成數字（opus 審查引用 events 與 expressions 文件）。
     - `&&`、`||` 回傳運算元本身，空字串視為 false；`!` 先於 `&&`，`&&` 先於 `||`。
   - `inputs` context：文件只說它在 reusable workflow 與 `workflow_dispatch` 中可用，沒寫 push 時的取值。
     - 本 change 只在三處讀它：`concurrency.group`、`LKAI_RELEASE_DRY_RUN`，以及原樣傳入的 `provider`、`model`。
     - 取不到值時，結果分別是 `release`、`false` 與空字串，都是 push 時預期的值。
     - 第一次發版時以 job summary 的模式是「release」確認（opus 第二輪審查 S5）。
   - workflow commands：輸出中以 `::` 開頭的行會被當成指令。`::stop-commands::<token>` 之後到 `::<token>::` 之前的內容不會被執行（Workflow commands 文件）。
   - `GITHUB_ACTIONS`：「Always set to `true` when GitHub Actions is running the workflow」；`GITHUB_STEP_SUMMARY` 由 runner 設定給每個 step（Variables 文件，opus 第二輪審查 W2）。
3. **gh 與 git 的實測**（2026-11-24，gh 2.105.0）：
   - `gh release create` 在 tag 不存在時自動建立。`--verify-tag`：「Abort in case the git tag doesn't already exist in the remote repository」。
   - `gh release list -R leoho0722/LKAIKit --limit 100 --json tagName --jq '.[].tagName'`：沒有 Release 時不印任何東西、退出碼 0；`-R cli/cli --limit 3` 印出三個 tag 名稱。對不存在的 repo，`gh release list` 的退出碼是 1。
   - `gh release view 9.9.9 --json tagName` 印出 `release not found`、退出碼 1，但對不存在的 repo 也印出同一句，所以不用它判斷有沒有 Release（fable 第二輪審查 N4）。
   - 對 GitHub 執行 `GIT_TRACE_PACKET=1 git push --dry-run --atomic`，伺服器宣告的能力含 `atomic`，表示支援 atomic push。
4. **`lkai` 的輸入檢查**（2026-11-24 實測）：
   - `lkai --provider gemini -m x -p hi`：退出碼 64，stderr 為「Error: The value 'gemini' is invalid for '--provider <provider>'. Please provide one of 'anthropic', 'openai' or 'google'.」
   - 沒有 `LKAI_GEMINI_API_KEY` 時執行 `lkai --provider google -m x -p hi`：退出碼 64，stderr 為「Error: No API key is available. Pass --apiKey, or set the environment variable LKAI_GEMINI_API_KEY.」
5. **建置路徑**（2026-11-24 實測）：`swift build --show-bin-path` 印出 Debug 的資料夾，加上 `-c release` 才是 Release 的資料夾。
6. **`iconv`**（2026-11-24 本機實測，兩位審查者也各自實測）：`printf '中文字\xe4\xb8' | iconv -c -f UTF-8 -t UTF-8` 的輸出是正確的「中文字」，但退出碼是 1，stderr 印出「iconv: unexpected end of file; the last character is incomplete.」。最後一個字元完整時退出碼是 0。GNU iconv 的行為沒有實測。
7. **變更的大小**（實測，用來決定 prompt 的上限）：
   - 已合併的 8 個 PR 中，`Sources/`、`Package.swift`、`Package.resolved`、`action.yml` 的 diff 為 2,838 到 105,884 bytes（最小的是 `01-add-ci` 的 PR #8，2026-11-24 量測）；前 7 個 PR 包含測試等其他檔案（`docs/spectra/` 除外）時為 17,075 到 285,332 bytes。
   - 從空的 tree 到 `HEAD`（`01-add-ci` 合併後）：`Sources/`、兩個 Package 檔與 `action.yml` 是 293,150 bytes；合併前量的 `docs/spectra/` 以外全部檔案是 1,162,430 bytes。
   - 非 merge 的 commit 有 146 個（`01-add-ci` 合併後，2026-11-24），以 `- <標題>` 逐行列出共 13,191 bytes。
8. **SwiftPM 的版本範圍**：Apple 文件寫 `upToNextMajor(from:)` 的範圍到「the next major version」為止，所以 `from: "0.1.0"` 會接受 `0.2.0`。這是依文件文字的推論，沒有實測。
9. **actions/checkout**：v7.0.1 的 SHA 是 `3d3c42e5aac5ba805825da76410c181273ba90b1`。`persist-credentials` 預設是 true，release.sh 的 `git push` 依靠它（opus 審查）。
10. **跨 change 的 delta**（2026-11-24 實測兩次）：在本 change 為 `continuous-integration` 加一份只有 ADDED 的 delta，`spectra validate` 都通過。`01-add-ci` 封存之前，`spectra analyze` 回報 Warning，把它當成沒有 Purpose 的新 capability；`01-add-ci` 封存並合併之後再測，`spectra analyze` 沒有任何發現。見決策「CI 的 script 測試規則放在 continuous-integration，測試的隔離留在 release-automation」。

**相關的既有決定**：

- `add-swift-package-foundation`「版本資訊集中於 LKAICore 的 LKAIKitInfo.version」：
  - 版號只有一個來源，「發佈時手動更新此值」。
  - 要求最晚在第一個 release tag 之前另開 change 處理 tag 同步。
  - 本 change 改由 CD 更新這個值，見決策「版號由 AI 回答升級等級、script 計算」。
- `add-swift-package-foundation` 的 Non-Goals「版本號與 git tag 自動同步、release 流程」：只限制了那個 change 自己的範圍，本 change 接手。
- `docs/adding-a-provider.md` 第 7 章「第一份｜調整 `LKAIKitInfo.version` 並打第一個 release tag｜留給之後」：由本 change 處理（任務 3.2）。
- `01-add-ci`：
  - 「Composite action 從 action 所在的原始碼建構 lkai，不採用 container action」。
  - 「第三方 action 以 commit SHA 固定」。

## Goals / Non-Goals

**Goals:**

- 合併到 `main` 後自動決定版號，建立 tag、GitHub Release 與 Release Notes；變更只有 Spectra 文件時不發版。
- tag 永遠等於被 tag 的 commit 中的版號。
- 發版失敗時，repo 留在下一次執行能接手的狀態，不需要人工清理。
- 發版邏輯能在 CI 與本機測試，結果相同；owner 在本機只能 dry run，打錯變數也不會真的發版。

**Non-Goals:**

- CI 的單元測試與 setup action：由 `01-add-ci` 處理。
- Linux 支援與 container action。
- 發佈 `lkai` 的執行檔（附在 release 上、Homebrew）。之後要做時，注意以 `GITHUB_TOKEN` 建立的 release 不會觸發 `on: release` 的 workflow（Context 第 2 點）。
- 設定 branch protection 與 required status check；影響見 Risks。
- 在 CI 執行 actionlint、shellcheck：只在實作時於本機執行（任務 4.1）。
- 修改 `lkai`（例如加上系統指示的選項）。
- `docs/spectra/` 以外的文件（例如 `CLAUDE.md`、`docs/adding-a-provider.md`）也不觸發發版：使用者只指定 Spectra 文件。
- AI 回答「不發版」的等級：只改 `.github/`、測試或 `CLAUDE.md` 的合併仍會升 PATCH（fable 審查的觀察）；之後需要時，AI 多一個可回答的字、計畫多一種「沒有可發佈的變更」。
- 補建「目前版號以外」的舊 tag 的 Release：只檢查目前版號的 tag（見決策「tag 沒有 Release 時先補建」）。
- push 被拒絕時自動 rebase 重試。

## Decisions

### 版號由 AI 回答升級等級、script 計算

**Supersedes**: add-swift-package-foundation / 版本資訊集中於 LKAICore 的 LKAIKitInfo.version

- 保留原決策的部分：
  - `LKAICore` 的 `public enum LKAIKitInfo` 提供 `public static let version: String`，格式 `MAJOR.MINOR.PATCH`、不加 `v`。
  - `lkai --version` 讀這個值，版號只有這一個來源。
- 改變的部分：原決策的「發佈時手動更新此值」改由 release workflow 更新。
  - 上一個 tag 之後有新的變更時，`lkai` 依變更回答 `major`、`minor` 或 `patch`。
  - `next-version.sh` 依規則算出新版號，`package-version.sh` 修改宣告的值，再推一個 commit 到 `main`。
- AI 只回答升級等級，不直接寫版號；script 只接受三個完全相同的字（去掉前後的空白、tab、CR、LF 後比對，大小寫要相同）。理由：版號的算法要固定、可測試；回答不合法時直接失敗，不會發出奇怪的版號。
- 原決策要求的「打第一個 release tag 之前處理 tag 同步」由本 change 完成（package-distribution「Release tag matches the package version」）。
- 這是使用者 2026-11-23 的選擇；選項中的「版號改了才自動發版」與「手動觸發」沒有採用。
- 考慮過的替代方案：
  - 由人在 PR 中更新版號，CD 只在版號沒有 tag 時發版：使用者選擇交給 AI；這個做法保留為人工指定版號的方式（決策「版號還沒有 tag 時照原樣發佈」）。
  - 以 build plugin 從 git tag 產生版號：原決策已因建置複雜度否決。

### 1.0.0 之前 major 只升 MINOR、minor 與 patch 升 PATCH

- MAJOR 是 0 時：`major` → `0.(Y+1).0`；`minor`、`patch` → `0.Y.(Z+1)`。MAJOR 至少是 1 時照一般的 SemVer。
- 理由：
  - 1.0.0 代表公開介面穩定，由人決定，不應由 AI 的一個回答觸發；升版的計算永遠不會到 1.0.0，要發 1.0.0 時在 PR 中把版號改成 `1.0.0`。
  - 0.x 期間以 MINOR 表示破壞性變更、PATCH 表示其他變更，和 Cargo 對 0.x 的慣例相同。App 以 `.upToNextMinor(from:)` 引用時，只會自動拿到不破壞的更新（Context 第 8 點）。
- 考慮過的替代方案：
  - 0.x 期間 `major` 直接升到 1.0.0：AI 判斷一次破壞性變更就宣告穩定，不採用。
  - 0.x 期間 `minor` 也升 MINOR：破壞性變更與新功能都升 MINOR，App 無法以版號區分，不採用。

### 版號還沒有 tag 時照原樣發佈

- 版號還沒有同名 tag 時，不問 AI 升級等級，直接以這個版號發佈，AI 只寫 Release Notes。
- 涵蓋兩種情況：
  - 第一次發版：目前沒有 tag，合併本 change 後發佈 `0.1.0`。
  - 人工指定版號：在 PR 中把版號改成還沒有 tag 的值（例如 `1.0.0`）。
- 失敗後的接手不依賴這條規則：升版 commit 與 tag 一起推送（決策「升版 commit 與 tag 以一次 atomic push 推上 main，再以 --verify-tag 建立 Release」），`main` 不會停在沒有 tag 的升版 commit。
- 考慮過的替代方案：一律問 AI。第一次發版會從 `0.1.0` 升成 `0.1.1`，人工指定的版號也會被改掉，不採用。

### tag 與版號相同，沒有 v 前綴

- tag 名稱就是 `LKAIKitInfo.version`，例如 `0.1.0`；release 的標題也是這個字串。
- 理由：和 `LKAIKitInfo.version` 的格式完全相同，比對時不必轉換；SwiftPM 社群常見的寫法也沒有 `v`。
- 考慮過的替代方案：`v0.1.0`。SwiftPM 也能解析，但與版號差一個字元，使用者選擇不加。

### 版號從 LKAIKitInfo.swift 讀取，與寫入共用同一個規則

- `package-version.sh get <file>` 與 `package-version.sh set <file> <version>` 以同一個比對規則定位 `public static let version: String = "<版號>"` 這一行：剛好一行才算找到，否則失敗。
- 計畫的「目前版本」是 `HEAD` 中的值：`release.sh` 以 `git show HEAD:Sources/LKAICore/LKAIKitInfo.swift` 寫到暫存檔，再以 `get` 讀取，不讀工作目錄的檔案（opus 第二輪審查 S5）。
- `lkai -v` 只用在升版後確認重新建置的結果，以及 `01-add-ci` 的 action 試跑。
- 理由（fable 審查 S5）：
  - PATH 上的 `lkai` 不一定由 `HEAD` 建置，例如本機的舊建置，或之後 workflow 改用某個 tag 的 action。
  - 本機的工作目錄可能有還沒 commit 的修改。
  - 讀 `HEAD` 的檔案才保證計畫看的就是要發佈的內容，測試也只要修改暫存 repo 的 commit。
- 宣告的寫法改變時，`package-version.sh` 會失敗。`LKAIKitInfo.swift` 的 `///` 寫明要一起修改（任務 3.2）；測試以真正的檔案建立暫存 repo（決策「發版 script 以假的 lkai、gh、swift 與暫存 git repo 測試」），所以在 PR 的 CI 就會失敗。

### 升版 commit 與 tag 以一次 atomic push 推上 main，再以 --verify-tag 建立 Release

- 升版的順序：
  1. 兩次 AI 回答都通過。
  2. `package-version.sh set` 修改版號。
  3. `swift build -c release --product lkai` 重新建置，以 `"$(swift build -c release --product lkai --show-bin-path)/lkai" -v` 確認是新版號，不用 PATH 上的 `lkai`（fable 第二輪審查的小項：之後 workflow 改用某個 tag 的 action 時，PATH 上的 `lkai` 是那個 tag 的版本）。
  4. commit。
  5. 在 commit 上建立 tag。
  6. `git push --atomic <remote> HEAD:refs/heads/main refs/tags/<版號>`，不 force。
  7. `gh release create <版號> --verify-tag --title <版號> --notes-file <檔案>`。
- 照原樣發佈：在 `HEAD` 建立 tag，只推 tag，再建立 Release。
- commit 的 author 與 committer 都是 `github-actions[bot]`（`41898282+github-actions[bot]@users.noreply.github.com`），訊息是 `chore: 版本號更新為 <版號>`，只改 `Sources/LKAICore/LKAIKitInfo.swift`。以 `GIT_AUTHOR_*`、`GIT_COMMITTER_*` 環境變數設定身分，不修改 git 設定（opus 審查 S4）。
- 理由（fable 審查 W1，使用者 2026-11-24 選擇方案 c）：
  - 原本的設計先推 commit、再由 `gh release create` 建 tag。建 Release 失敗時，`main` 會停在沒有 tag 的版號。下一次合併帶著新的 commit 進來時，會以舊版號照原樣發佈，新的變更沒有經過升級等級的判斷，例如破壞性變更混進 PATCH。
  - atomic push 讓 commit 與 tag 一起成功或一起失敗，`main` 不會再有「有升版 commit、沒有 tag」。剩下的中間狀態只有「有 tag、沒有 Release」：SwiftPM 只看 tag，這個狀態不影響 App，由下一個決策補建。
  - 先通過所有會失敗的檢查（AI 回答、版號修改、重新建置）再寫入 remote，失敗時不留下半套的狀態。
- `GITHUB_TOKEN` 推的 commit 與 tag 不會再觸發 workflow（Context 第 2 點），所以不會循環。計畫本身也可以重複執行：tag 就在 `HEAD` 上時以「沒有可發佈的變更」結束（fable 第二輪審查）。
- push 被拒絕（`main` 在執行期間有新的 commit）時失敗，remote 沒有 commit 也沒有 tag。
- 考慮過的替代方案：
  - 維持「先推 commit、再以 `gh release create --target` 建 tag 與 Release」，在 spec 與 Risks 寫明：新的變更可能以舊版號發佈，不採用。
  - 接手時把 tag 打在 bot 的升版 commit 而不是 `HEAD`：要以作者與訊息辨識升版 commit，較脆弱，不採用。
  - 不推 commit，只在 tag 上記錄版號：`LKAIKitInfo.version` 會和 tag 不同，違反 package-distribution 的新 requirement，不採用。

### tag 沒有 Release 時先補建

- 目前版號的 tag 已存在時，先以 `gh release list --limit 100 --json tagName --jq '.[].tagName'` 列出最近 100 個 Release 的 tag：
  - 退出碼不是 0：失敗。
  - 清單中沒有這個 tag：撰寫這個 tag 的 Release Notes（範圍是比它小、而且是它祖先的最高版本 tag 到這個 tag），以 `--verify-tag` 建立 Release，再照常判斷之後的變更。
- 理由（fable 第二輪審查 N4）：不必比對 `gh` 的錯誤文字。錯誤文字不是介面，而且 `gh release view` 在 repo 不存在時也印同一句（Context 第 3 點）。
- 為什麼 100 個就夠：目前版號是最高的 tag。它的 Release 存在時，是最近建立的那幾筆之一。這是推論；有人在之後手動補建了大量舊 Release 時才可能不成立。
- 補建的 Release Notes 請求或建立失敗，都算「補建 Release」這一步失敗。
- 補建成功之後，同一次執行的後續步驟才失敗時，補建的 Release 保留，不回收；其他的保證（不改檔案、不建 commit 與 tag、不建立其他 Release）不變（opus 第二輪審查 W1）。
- 一次執行可能建立兩個 Release：補建的那一個，以及之後的升版。
- dry run 時只撰寫補建用的 Release Notes 並印出，不建立。
- 限制：只檢查目前版號的 tag。建立 Release 失敗後，下一次合併剛好是人工指定版號的 PR（走照原樣發佈）時，舊 tag 的 Release 不會再被補建（fable 第二輪審查的觀察）；SwiftPM 不受影響，由 owner 手動建立（`docs/releasing.md`）。

### 計畫先擋下比現在版號更大的 tag

- 讀到版號後，先檢查有沒有比它大的版本 tag，有就失敗，訊息寫出最高的 tag；之後才判斷升版或照原樣發佈。
- 理由（opus 審查 W2）：只在照原樣發佈時檢查的話，版號被 revert 回舊值、而舊的 tag 還在時，升版算出的版號可能等於或小於既有的 tag。先檢查之後，升版的起點一定是最高的 tag，算出的版號一定比所有 tag 大，也不會撞名。這個檢查在送出 AI 請求之前，不花費用。

### tag 之後只有 docs/spectra 的變更時不發版

- 目前版號的 tag 之後，`git diff --name-only <tag> HEAD -- . ':(exclude)docs/spectra'` 沒有任何檔案時，以 0 結束、不發版。
- 理由（fable 審查 S6）：`paths-ignore` 只看「這一次 push」，手動觸發時不受它限制；把同一條規則寫進 script，才能以暫存 repo 測試，之後要排除其他路徑時也有兩處可以一起改。`paths-ignore` 仍然保留，作用是不必開 runner。

### 只有 docs/spectra 的 push 不觸發，CD 取 main 最新的 commit，正式 run 一次只跑一個

- `on.push.branches: [main]` 加 `paths-ignore: ['docs/spectra/**']`。GitHub 只在變更的檔案全部符合時才略過，所以同時改了程式碼與 Spectra 文件的 PR 仍會發版。
- 另提供 `workflow_dispatch`（輸入 `provider`、`model`、`dry_run`），用來在失敗後重跑或試跑；合併後才能使用（Context 第 2 點）。
- checkout 指定 `ref: main`、`fetch-depth: 0`，不設定 `persist-credentials: false`。spec 寫的是「checkout 保存的憑證」而不是「預設的憑證」：之後依 `docs/releasing.md` 改用 App 或 PAT 的 token（以 checkout 的 `token:` 傳入）時，requirement 中 checkout 憑證的這一句不必改（opus 第五輪審查 S1）；它底下只描述 `GITHUB_TOKEN` 的情境仍要依決策「發版的操作寫在 docs/releasing.md」的限制一段更新（fable 第六輪審查 V1）。
- 理由：等待中的 run 會被更新的 run 取代；每個 run 都處理當下最新的 `main`，所以被取代的 run 的變更不會漏掉。要是 checkout 觸發 run 的 commit，後面的 run 會拿到已經發佈過的舊 commit。
- 考慮過的替代方案：
  - 只用 `workflow_dispatch` 手動觸發：使用者選擇合併時自動觸發。
  - `queue: max`：保留所有等待中的 run，但每個 run 都處理最新的 `main`，多餘的 run 只會以「沒有可發佈的變更」結束，不需要。

### dry run 用另一個 concurrency group

- `concurrency.group` 寫成 `${{ inputs.dry_run && 'release-dry-run' || 'release' }}`，`cancel-in-progress: false`。push 觸發時 `inputs.dry_run` 沒有值，屬於 `release`（Context 第 2 點）。
- 理由（opus 審查 W1）：共用同一個 group 時，等待中的正式 run 會被之後的 dry run 取代而取消，而 dry run 不發版，那次合併的變更要等下一次觸發。dry run 不寫入，可以和正式 run 並行。

### 只有 GitHub Actions 中明確設成 false 才正式發版

- `LKAI_RELEASE_DRY_RUN`：
  - 沒有設定、空字串或 `true`：dry run。
  - `false`：正式發版，只在 `GITHUB_ACTIONS` 是 `true` 時允許；不在 GitHub Actions 中時失敗。
  - 其他值：在做任何事之前就失敗。
- workflow 寫成 `${{ inputs.dry_run && 'true' || 'false' }}`；不可寫成 `github.event.inputs.dry_run == true`，那樣的比較永遠是 false（Context 第 2 點）。
- 理由（fable 審查 W3、opus 審查 W7）：owner 在本機執行時用的是自己的 git 與 gh 權限，而 `main` 沒有保護。漏設或打錯變數時，原本的設計會真的推到 `origin` 的 `main` 並建立 Release，而且這次 push 不是 `GITHUB_TOKEN` 推的，還會再觸發一次 release workflow。預設改成安全的一邊，本機永遠不會正式發版。

### 判斷升級等級與撰寫 Release Notes 分成兩次請求

- 升級等級與 Release Notes 各一次請求。一次執行的請求數：
  - 照原樣發佈：一次（Release Notes）。
  - 升版：兩次（升級等級、Release Notes）。
  - 補建 Release：再多一次（補建用的 Release Notes），所以補建加升版時最多三次（opus 第二輪審查 S3）。
- 理由：兩個回答的格式各自固定、各自驗證；第二次請求在 prompt 中已經知道新版號。
- 代價：同樣的變更資料送兩次。以 Context 第 7 點的大小估計，每次升版最多送出約 2 ×（200,000 bytes 的 diff ＋ commit 清單 ＋ 變更統計）。這是估計值，以實際發版後供應商後台的用量確認。
- 考慮過的替代方案：一次請求，第一行是升級等級、後面是 Release Notes。省一半的輸入，但解析較脆弱，不採用。

### 兩個 prompt 帶同樣的變更資料：commit 清單、變更統計與 200,000 bytes 以內的程式碼 diff

- 兩個範本放在 `.github/scripts/release/prompts/`，由 `make-prompt.sh` 在後面接上同一份變更資料：
  - 非 merge commit 的標題。
  - `git diff --stat` 的變更統計。
  - `Sources/`、`Package.swift`、`Package.resolved`、`action.yml` 的 diff。
- 範圍：
  - 起點：沒有上一版時從空的 tree 開始，包含第一個 commit（opus 審查 S7）。
  - 終點：`HEAD`；補建 Release 時是被補建的 tag。
- bump level prompt 帶上一版，不帶新版號；release notes prompt 帶要發佈的版號，以及上一版或「第一次發版」的說明。
- diff 超過 200,000 bytes（`LKAI_RELEASE_DIFF_LIMIT` 可在測試中改小）時，整段不放，並在 prompt 中說明；不截斷到一半。
- 上限的依據：
  - 過去 8 個 PR 的程式碼 diff 最大 105,884 bytes，全部放得下。
  - 第一次發版從空的 tree 開始，293,150 bytes 超過上限，改以 146 個 commit 的標題撰寫（Context 第 7 點；合併本 change 時還會再多幾個）。
- 測試與 `docs/` 的變更不放進 diff；commit 標題已經涵蓋這些變更。
- commit 標題、統計與 diff 以 `<commits>`、`<stat>`、`<diff>` 標記包起來，prompt 明說其中的文字是資料，要忽略其中的指示。
- 理由（opus 審查 W5）：只規定範本、不規定資料時，實作漏接資料，測試照樣通過，AI 卻是在沒看到變更的情況下判斷等級。

### Release Notes 以正體中文分類撰寫

- 以 Markdown 分成「破壞性變更」、「新功能」、「修正」、「其他」，沒有項目的分類不寫。語言固定為正體中文，和 commit 標題與 owner 的使用語言相同。
- 要調整格式或語言時，修改 `prompts/release-notes.md`，不必改 script。

### 供應商與模型：優先順序由 script 決定，只留一組預設值，驗證交給 lkai

- workflow 只原樣傳入四個值（fable 第二輪審查 N3）：
  - `LKAI_RELEASE_PROVIDER`、`LKAI_RELEASE_MODEL`：`workflow_dispatch` 的輸入，push 時是空的。
  - `LKAI_RELEASE_DEFAULT_PROVIDER`、`LKAI_RELEASE_DEFAULT_MODEL`：同名的 repository variables。
- `release.sh` 的優先順序（spec「Release provider and model selection」的範例表）：
  - 供應商：本次的值 → repository 的預設值 → `anthropic`。
  - 模型：本次指定了供應商時，只看本次的模型；否則本次的模型 → repository 的預設模型 → 兩個預設值都沒有設定時用 `claude-opus-5-5`。
  - 沒有模型時，在送出請求前失敗，訊息寫出 `LKAI_RELEASE_MODEL` 與 `LKAI_RELEASE_DEFAULT_MODEL`。
  - 不驗證供應商的值，也不檢查金鑰，原樣交給 `lkai`。
- 本機執行時，owner 只需要設定前兩個。
- `lkai` 已經會在送出請求前，以退出碼 64 拒絕不認得的供應商與缺少的金鑰，訊息寫出值或環境變數名稱（Context 第 4 點）；`release.sh` 依「Failed AI request」處理，這時還沒有改任何檔案。
- 三個 secret 都以同名環境變數傳入（GitHub 的運算式組不出 secret 名稱）。
- 理由：
  - 優先順序是發版流程中唯一有分支的設定邏輯。放在 script 才能以範例表測試；原本寫在 YAML 的運算式只能靠逐列代入審查，而且已經修過一次（fable 第二輪審查 N3）。
  - `lkai` 的 `LKAIChatProvider` 是新增供應商時唯一要改的程式。原本在 bash 再抄一份清單、金鑰對照與預設模型，新增供應商要多改四處（fable 審查 W2）；現在要改的是 release.yml 的 secret、spec 中列出 secret 的那一句，以及 GitHub 上的 repository secret。
  - 實際 API 測試的模型是為了便宜選的，和讀大量 diff 的用途不同，不該共用一份對照。
- 代價：
  - 錯誤訊息改由 `lkai` 印出（會連用法一起印），而且要先組好第一個 prompt 才會發現；兩者都只是本機運算。
  - repository variables 的名稱帶 `DEFAULT`，和 dispatch 的輸入區分。
- 考慮過的替代方案：
  - 每家一個預設模型：要在 bash 維護對照，不採用。
  - `provider` 用 `type: choice`：choice 一定有值，會蓋過 repository variable，不採用。
  - 優先順序寫在 workflow 的運算式：無法測試，不採用（上一版的做法）。

### AI 的文字以 stop-commands 包起來

- 在 GitHub Actions 中印出 AI 的文字時，前後各寫一行，而且和文字寫在同一個輸出流（opus 第二輪審查 S2）：
  - 前：`::stop-commands::<token>`。
  - 後：`::<token>::`。
  - token 每次執行以 `/dev/urandom` 產生 32 個十六進位字元。
  - AI 的文字包括 Release Notes 與錯誤訊息中被拒絕的回答。
- `release.sh` 自己寫的 `::error::` 那一行不放 AI 的文字。被拒絕的回答放在它後面幾行，以上面的兩行包起來，所以回答中的 LF 不會讓後面的行落在保護之外。
- 理由（opus 審查 S6）：回答與 Release Notes 可能受 diff 內容誘導而含有 `::error::`、`::add-mask::` 等行，GitHub 會把它們當成指令（Context 第 2 點）。stdout 與 stderr 是兩條管線，先後順序不保證，所以兩行標記要和文字在同一條。
- 本機執行時不加，避免輸出多出看不懂的行。

### 每個結束點都寫執行報告

- 選定模式之後，每個結束點都印出報告，並在有 `GITHUB_STEP_SUMMARY` 時寫入 job summary。結束點包括：沒有可發佈的變更、dry run、發佈成功、任何一步失敗。
- 報告內容：
  - 模式。
  - 已解析時：供應商與模型。
  - 已選定時：計畫。
  - 已知時：上一版、新版號。
  - 成功時：Release Notes。
  - 失敗時：失敗的步驟。
- 步驟名稱固定為（opus 第二輪審查 S1 補上兩個）：
  1. 解析供應商與模型
  2. 讀取版號
  3. 檢查 Release
  4. 補建 Release（包含補建時的 Release Notes 請求）
  5. 判斷升級等級
  6. 撰寫 Release Notes
  7. 修改版號
  8. 重新建置
  9. 建立 commit 與 tag
  10. 推送
  11. 建立 Release
- 理由（opus 審查 W3）：原本的流程只在發佈成功時寫報告，和 spec 的「every run that chooses a plan」矛盾；失敗時最需要知道停在哪一步。
- 實作以 `trap ... EXIT` 統一寫出，dry run 不會印兩次。

### 發版邏輯寫成 bash script，只用 BSD 與 GNU 都有的寫法

- `.github/scripts/release/`：
  - `next-version.sh`：計算新版號。
  - `package-version.sh`：讀寫版號。
  - `make-prompt.sh`：組 prompt。
  - `release.sh`：整個流程。
- workflow 的 YAML 只做 checkout、建構 `lkai`、原樣傳入環境變數，然後呼叫 `release.sh`。
- 寫法的限制：
  - 相容 bash 3.2：不用 associative array、`${var,,}`、`mapfile`。
  - 只用 BSD 與 GNU 都有的寫法：不用 `sed -i`（寫到暫存檔再 `mv`），不用兩邊旗標不同的 `stat`、`date`、`cut -c` 等。
  - 截斷 UTF-8 時，以 `head -c 200` 取 byte，再以 `iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true` 去掉不完整的字元。`2>/dev/null || true` 是必要的：結尾不完整時，macOS 的 `iconv -c` 輸出正確，但退出碼是 1，還會印一行訊息（Context 第 6 點）。
  - 變數後面緊接著中文或全形標點時寫成 `${名稱}`：macOS 的 bash 3.2 在 UTF-8 語系下（GitHub 的 macOS runner 預設也是），會把 `$名稱` 後面的非 ASCII 位元組當成變數名稱的一部分，值不見、訊息變成亂碼；語系是 C 時看不出來。實作任務 1.4 時發現，`tests/test-script-style.sh` 以 `LC_ALL=C` 掃描發版 script、假指令、測試、workflow 與 `action.yml`，有這種寫法時失敗。
  - 不用 `set -e`：每個會失敗的指令都接 `|| fail`，`fail` 才記得到失敗的步驟（決策「每個結束點都寫執行報告」）。
- 訊息以正體中文寫到 stderr；在 GitHub Actions 中以 `::error::` 開頭成為 annotation，其他情況以 `Error: ` 開頭。
- 理由：
  - 邏輯在 script 中才能在本機與 CI 測試。
  - runner 與本機都是 bash 3.2（Context 第 1 點）。
  - Linux 支援是已列出的下一步，CI/CD 之後可能搬到 ubuntu runner，所以現在就不寫 BSD 專屬的寫法（fable 審查 S9）。現在不驗證 Linux。
- 考慮過的替代方案：
  - 新增 Swift executable target：要修改 `Package.swift` 與 package-distribution 的依賴方向規則，App 也會看到這個 product，不採用。
  - 邏輯直接寫在 workflow 的 YAML：無法在本機測試，不採用。
  - release-please、semantic-release：依 Conventional Commits 決定版號，無法讓 AI 判斷，不採用。

### 發版 script 以假的 lkai、gh、swift 與暫存 git repo 測試

- `tests/run-tests.sh` 的行為：
  - 執行 `tests/test-*.sh` 中所有 `test_` 開頭的函式，每個函式在自己的 subshell 與暫存資料夾中執行。
  - 不依賴 bats 等外部工具。
  - 印出每個測試的結果，有任何失敗時以 1 結束。
- 環境的隔離（opus 第二輪審查 W2、fable 第二輪審查 N2）：
  - 執行前設定 `GIT_CONFIG_GLOBAL=/dev/null`、`GIT_CONFIG_NOSYSTEM=1`，不受本機的 git 設定影響（opus 審查 S4）。
  - 每個測試開始前清掉下列變數，由測試自己設定需要的值。比照 `add-cli-chat-command` 的決策「process 測試清掉 LKAI_*_API_KEY」。
    - `GITHUB_ACTIONS`、`GITHUB_STEP_SUMMARY`、`GH_REPO`、`GH_TOKEN`。
    - 所有 `LKAI_RELEASE_` 開頭的變數。
    - 所有 `LKAI_` 開頭、`_API_KEY` 結尾的變數。以樣式表示、不逐一列出，新增供應商時這條規定與 `run-tests.sh` 都不必修改（fable 第三輪審查 R1）。
  - 受測 script 的 stdout 與 stderr 一律收進檔案。失敗時要印出來的話，每一行前面加兩個空格，不讓它們成為 job log 中的 workflow command。
- 不清掉這些變數時會發生的事：
  - 在 CI 上 `GITHUB_ACTIONS` 是 `true`，「modes」表中 `not set` 的列、「沒有 `GITHUB_ACTIONS` 時不加 stop-commands」的測試，以及斷言 `Error: ` 開頭的測試，在本機通過、在 CI 失敗。
  - 沒有指定 `GITHUB_STEP_SUMMARY` 的測試會把報告寫進 PR 的 job summary。
- `tests/fakes/` 放假的 `lkai`、`gh`、`swift`，測試時排在 `PATH` 最前面，形狀見 Implementation Contract。
- 暫存的 git repo：
  - 以本 repo 真正的 `Sources/LKAICore/LKAIKitInfo.swift` 建立，搭配 bare repo 作為 remote。
  - helpers 預設為已建立的每個版本 tag 寫下 Release 紀錄，需要補建的測試再明確拿掉（opus 第二輪審查 W1）。所以 1.4、1.5 寫的測試在 1.6 加上補建之後仍然成立。
  - 正式發版的測試設定 `GITHUB_ACTIONS=true` 與 `LKAI_RELEASE_DRY_RUN=false`。
- 每個為 spec 情境寫的測試函式上方加 `# spectra-scenario: <capability> / <情境>`，有範例時再加一行 `# / <範例>`，名稱照抄 spec。
- 測試先寫：主對話觀察到新測試在實作前失敗，才實作。
- 考慮過的替代方案：bats-core。需要在 runner 與本機另外安裝，不採用。

### CI 的 script 測試規則放在 continuous-integration，測試的隔離留在 release-automation

- 本 change 為 continuous-integration 加一份 ADDED delta「Release script tests in CI」：CI 的 job 在 `swift test` 之後執行 `run-tests.sh`，job 的 runner 標籤和 release workflow 相同，測試失敗時 job 失敗。`ci.yml` 的內容就全部由 continuous-integration 規定，之後調整 CI 的人只讀這份 spec 就看得到這個限制。
- 測試本身的規定（替身、隔離 git 設定與環境變數、收住受測 script 的輸出）留在 release-automation「Release script test isolation」：它們是發版 script 的測試方式，和 CI 怎麼跑無關。
- `ci.yml` 中這個 step 仍加一行註解，指向 continuous-integration 的這條 requirement。
- 理由（fable 與 opus 的實作前審查，2026-11-24）：
  - 原本採方案 b（規則全部留在 release-automation），唯一的理由是「`01-add-ci` 封存之前，跨 change 的 delta 會讓 `spectra analyze` 一直回報 Warning」。01 封存後這個限制已經不存在（Context 第 10 點）。
  - 另一個理由「退掉本 change 時 requirement 也跟著退」，對 delta 同樣成立，因為 delta 也屬於本 change。
- 考慮過的替代方案：方案 b（全部留在 release-automation）。之後調整 CI 的人只讀 continuous-integration 時，會漏掉 runner 標籤要和 release workflow 相同的限制，不採用。

### 發版的操作寫在 docs/releasing.md

- 新增 `docs/releasing.md`（fable 審查 S8、第二輪審查 N6）。
- 開頭：比照 `docs/adding-a-provider.md` 第 1 章寫權威順序，系統的行為以 release-automation spec 為準，這份文件是操作方式。
- 一般操作：
  - 發版怎麼觸發、版號怎麼決定、1.0.0 之前的規則。
  - 怎麼指定版號。
  - 怎麼 dry run：GitHub 上的 `workflow_dispatch` 與本機。本機的前置條件：`PATH` 上有 `lkai`、設定所選供應商的金鑰環境變數、`gh` 已登入（版號已有 tag 時會執行 `gh release list`，沒有登入時在「檢查 Release」失敗；fable 第三輪審查的小項）。
  - 切換供應商與模型：repository variables `LKAI_RELEASE_DEFAULT_PROVIDER`、`LKAI_RELEASE_DEFAULT_MODEL`，以及要新增對應的 repository secret。
- 失敗與回退：
  - 各種失敗時怎麼接手。
  - 補建 Release 一直失敗時（例如 AI 拒絕那段 diff），之後每次執行都停在補建，由 owner 手動為那個 tag 建立 Release 解除；舊 tag 少了 Release 時也手動建立。
  - 發錯時怎麼退：刪 release 與 tag，再以 PR 改版號。
- 需要知道的限制：
  - `main` 加上 branch protection 或 required status check 之後，`GITHUB_TOKEN` 直接推上 `main` 的升版 commit 會被拒絕：它沒有 CI 的結果。GitHub 文件沒有寫明能不能讓 `GITHUB_TOKEN` 例外（fable 與 opus 第三輪審查各自查詢，沒有實測），所以加保護前先在 sandbox repo 實測。不行時改用 GitHub App 的 installation token 或 PAT，並把對應的對象加進 bypass。bypass 能加哪些對象以實測時 GitHub 提供的為準（官方 API 描述目前列出 App、角色、team、deploy key 與使用者；fable 第五輪審查 U1）：用 App 的 token 時加那個 App，用 PAT 時加 PAT 的擁有者或他的角色。不論哪一種，都要在 release workflow 的 checkout 以 `token:` 傳入，push 才會用到它（opus 第四輪審查 S2）。改用這類 token 之後，升版的 push 會再觸發 release workflow，它會以「沒有可發佈的變更」結束（決策「升版 commit 與 tag 以一次 atomic push 推上 main，再以 --verify-tag 建立 Release」）。改用其他 token 是對 `release.yml` 的修改，要另開 change：同時更新 release-automation「Release workflow trigger」的情境「A push by the release workflow itself」（它只描述 `GITHUB_TOKEN`），並補上「以其他 token 推送時會再觸發一次，並以沒有可發佈的變更結束」的情境（fable 第五輪審查 U2）。
  - 以 `GITHUB_TOKEN` 建立的 release 不會觸發其他 workflow。
  - 第一個 tag 之後，`config.yaml` 的 API 演進規則開始生效。
  - 第一次發版後要確認的項目。
- `docs/spectra/config.yaml` 的 context 加一行，比照指向 `docs/adding-a-provider.md` 的那一行：
  - 什麼時候讀：修改發版流程的 change 開始前。
  - 哪些 change 封存前要更新它：修改 release-automation spec、`release.yml` 或 `.github/scripts/release/` 的 change。
- `docs/adding-a-provider.md`：
  - 新增供應商要動的檔案加上 `release.yml` 的 secret、release-automation spec 中列出 secret 的那一句，以及 GitHub 上的 repository secret。
  - 第 5 章加一列：`add-swift-package-foundation` 的「發佈時手動更新此值」改由本 change 的決策處理。
  - 第 7 章「調整 `LKAIKitInfo.version` 並打第一個 release tag」一列改成「已解決」，依據寫 `02-add-release-automation` 的決策「版號由 AI 回答升級等級、script 計算」。清單第 7 章的狀態只用「已解決」「屬於下一家」「留給之後」（opus 實作前審查 S2）。
  - 出處寫完整名稱 `02-add-release-automation`。
- 理由：這個 repo 的規則是封存的 design 只記錄當時的決定；操作知識若只寫在 design，封存後就沒有人看得到。
- 這些文件不在 `docs/spectra/` 之內，修改它們的合併會觸發發版，這是使用者的規則下的預期行為。

### 實作由 sonnet 在單一 worktree 依序進行

- 沿用之前的做法：sonnet 在 `.worktrees/sonnet`（分支 `wt/release-sonnet`）依任務順序實作；主對話逐項驗證、執行測試、commit 並合併回功能分支 `feat/02-add-release-automation`。
- 任務 1.1 到 3.2 由 sonnet 做。4.1、4.2 由主對話做，4.3 由 owner 做（或 owner 同意後由主對話執行），4.4 在 owner 同意推送與開 PR 後由主對話做。
- 任務多半修改同一組 script 與測試，平行進行會衝突，所以依序進行。

## Implementation Contract

**檔案與介面**：

| 檔案 | 形狀 |
| --- | --- |
| `.github/workflows/release.yml` | 見下方「`release.yml` 的形狀」 |
| `.github/workflows/ci.yml` | 在 `swift test` 之後加一個 step：`bash .github/scripts/release/tests/run-tests.sh`，比照既有的 step 寫正體中文的 `name` 與 `shell: bash`，附一行註解指向 continuous-integration「Release script tests in CI」；檔案開頭的說明補上發版 script 的測試；job 的 `runs-on` 與 release.yml 相同 |
| `.github/scripts/release/next-version.sh` | `next-version.sh <version> <level>`；stdout 為新版號加 LF；不合法時 stdout 為空、stderr 有訊息、退出碼 1 |
| `.github/scripts/release/package-version.sh` | `get <file>`：印出版號加 LF。`set <file> <version>`：把宣告的值換成 `<version>`，寫到暫存檔再 `mv`。兩者都以同一個規則找 `public static let version: String = "<版號>"`；不是剛好一行，或版號不合格式時，不修改檔案、退出碼 1 |
| `.github/scripts/release/make-prompt.sh` | `make-prompt.sh <bump-level\|release-notes> <previous-version> <target-ref> [<version>]`；`<previous-version>` 為空字串表示沒有上一版（diff 從空的 tree 開始，包含第一個 commit）；`<version>` 只用於 release-notes；stdout 為完整的 prompt（範本加上變更資料）；diff 上限讀 `LKAI_RELEASE_DIFF_LIMIT`，預設 200000 |
| `.github/scripts/release/prompts/bump-level.md`、`release-notes.md` | 第一行分別是 `<!-- lkai-release-prompt: bump-level -->`、`<!-- lkai-release-prompt: release-notes -->`，供假的 `lkai` 分辨；內容依 release-automation「AI bump level answer」與「Release notes generation」 |
| `.github/scripts/release/release.sh` | 不收引數，在 git repo 的根目錄執行；環境變數見下表；退出碼 0 表示已發佈、沒有可發佈的變更或 dry run 完成，1 表示失敗 |
| `.github/scripts/release/tests/` | `run-tests.sh`、`helpers.sh`、`fakes/`（`lkai`、`gh`、`swift`，以及三者共用的 `fake-common.sh`）、`test-next-version.sh`、`test-package-version.sh`、`test-make-prompt.sh`、`test-release.sh`、`test-script-style.sh`（寫法的檢查，見決策「發版邏輯寫成 bash script，只用 BSD 與 GNU 都有的寫法」） |
| `docs/releasing.md` | 內容見決策「發版的操作寫在 docs/releasing.md」 |

**`release.yml` 的形狀**：

- 觸發：
  - `on.push: { branches: [main], paths-ignore: ['docs/spectra/**'] }`。
  - `on.workflow_dispatch.inputs`：`provider`（string，預設空字串）、`model`（string，預設空字串）、`dry_run`（boolean，預設 false）。
- `permissions: contents: write`。
- `concurrency: { group: ${{ inputs.dry_run && 'release-dry-run' || 'release' }}, cancel-in-progress: false }`。
- 一個 job：`runs-on: xcode-27`、`timeout-minutes: 30`。
- step 依序是：
  1. checkout：`ref: main`、`fetch-depth: 0`、以 SHA 固定、不設定 `persist-credentials`。附一行註解寫明不可設定 `persist-credentials: false`：`release.sh` 的 `git push` 依靠 checkout 保存的憑證，和 `ci.yml` 相反是刻意的（fable 實作前審查 Q2：之後有人為了一致而加上時，升版的 push 會失敗，而且只有實際發版時才會發現）。
  2. `uses: ./`。
  3. 執行 `.github/scripts/release/release.sh`，`env` 見下表。
- `inputs`、`vars` 與 `secrets` 都以 `env` 傳入，不在 `run` 中直接展開。

**`release.sh` 的環境變數**：

| 名稱 | 由 release workflow 設定的值 | 用途 |
| --- | --- | --- |
| `LKAI_RELEASE_DRY_RUN` | `${{ inputs.dry_run && 'true' \|\| 'false' }}` | 模式 |
| `LKAI_RELEASE_PROVIDER` | `${{ inputs.provider }}` | 本次的供應商 |
| `LKAI_RELEASE_MODEL` | `${{ inputs.model }}` | 本次的模型 |
| `LKAI_RELEASE_DEFAULT_PROVIDER` | `${{ vars.LKAI_RELEASE_DEFAULT_PROVIDER }}` | repository 的預設供應商 |
| `LKAI_RELEASE_DEFAULT_MODEL` | `${{ vars.LKAI_RELEASE_DEFAULT_MODEL }}` | repository 的預設模型 |
| `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY` | 同名的 repository secret | 由 `lkai` 讀取 |
| `GH_TOKEN` | `${{ github.token }}` | `gh release list`、`gh release create` |
| `GITHUB_ACTIONS`、`GITHUB_STEP_SUMMARY` | GitHub 提供 | 模式、AI 文字的保護、報告 |
| `LKAI_RELEASE_REMOTE`、`LKAI_RELEASE_BRANCH` | 不設定（預設 `origin`、`main`） | 測試以暫存的 remote 取代 |
| `LKAI_RELEASE_DIFF_LIMIT` | 不設定（預設 200000） | 測試改小 |

**`release.sh` 的流程**（括號內是 release-automation 的 requirement；每一步的名稱見決策「每個結束點都寫執行報告」）：

1. 選擇模式（「Release mode」），解析供應商與模型（「Release provider and model selection」）。
2. 讀取版號：`git show HEAD:Sources/LKAICore/LKAIKitInfo.swift` 寫到暫存檔，以 `package-version.sh get` 讀取；列出版本 tag；版號不合格式，或有更大的 tag 時失敗（「Release plan」第 1、2 條）。
3. 目前版號的 tag 存在時：
   - 檢查 Release，需要時補建（「Release repair」）。
   - 沒有新的 commit，或只有 `docs/spectra/` 的變更時，以 0 結束（「Release plan」第 3 條）。
   - 否則是升版：判斷升級等級、計算新版號（「AI bump level answer」「Next version computation」）。
4. tag 不存在時：照原樣發佈（「Release plan」第 4 條）。
5. 撰寫 Release Notes（「Release notes generation」）；AI 請求失敗的處理見「Failed AI request」。
6. dry run 時結束（「Dry run」）。
7. 升版時：修改版號，重新建置並以 `--show-bin-path` 資料夾中的 `lkai -v` 確認，建立 commit 與 tag，atomic push。照原樣發佈時：建立 tag，只推 tag（「Version commit and tag push」）。
8. 建立 Release（「Release creation」）。
9. 任何結束點都寫報告（「Run report」）；印出 AI 的文字時依「AI text in the job log」處理。

**呼叫 `lkai` 的方式**：

- 指令：`lkai --provider <供應商> --model <模型> --prompt-file <暫存資料夾>/<名稱>.md --timeout 180`。
- 選項：
  - Release Notes 另加 `--max-output-tokens 8192`；升級等級用預設的 4096。
  - 不加 `--stream`，不加 `--apiKey`。
- 暫存資料夾：在 `${RUNNER_TEMP:-${TMPDIR:-/tmp}}` 底下以 `mktemp -d` 建立，結束時刪除。
- 180 秒與 8192 都是估計值：輸入比 `lkai` 的實際 API 測試大很多，第一段回應可能較慢；Release Notes 可能比 4096 tokens 長。值太小時 `lkai` 以 1（逾時）或 2（截斷）結束，`release.sh` 隨之失敗，不會發出不完整的 Release Notes。

**假的指令**（`tests/fakes/`）：

| 指令 | 行為 |
| --- | --- |
| `lkai -v` | 印出目前資料夾 `Sources/LKAICore/LKAIKitInfo.swift` 中的版號；設定 `FAKE_LKAI_VERSION` 時改印它（測試重新建置後版號不同） |
| `lkai --provider … --prompt-file <f>` | 依 `<f>` 第一行的標記分辨兩種請求，以 `FAKE_LKAI_BUMP_REPLY`、`FAKE_LKAI_NOTES` 回答，以 `FAKE_LKAI_BUMP_EXIT`、`FAKE_LKAI_NOTES_EXIT`、`FAKE_LKAI_BUMP_STDERR` 決定退出碼與 stderr；把引數與 prompt 複製到 `FAKE_LOG_DIR` |
| `gh release list … --json tagName --jq '.[].tagName'` | 逐行印出 `FAKE_LOG_DIR` 中有 Release 紀錄的 tag；`FAKE_GH_LIST_EXIT` 不是 0 時以它結束 |
| `gh release create <tag> --verify-tag …` | 暫存 remote 沒有這個 tag 時失敗；`FAKE_GH_CREATE_EXIT` 不是 0 時失敗；成功時寫下 Release 紀錄並記錄引數 |
| `swift build … --show-bin-path` | 印出 fakes 資料夾 |
| `swift build …`（其他） | 以 `FAKE_SWIFT_EXIT`（預設 0）結束 |

**失敗時的狀態**：

| 失敗的位置 | repo 的狀態 | 接手的方式 |
| --- | --- | --- |
| 解析供應商與模型、讀取版號、檢查 Release、AI 請求、修改版號、重新建置、建立 commit 與 tag（沒有補建時） | 沒有任何改變 | 修正原因後以 `workflow_dispatch` 重跑，或等下一次合併 |
| 補建 Release 成功後，上一列的任一步失敗 | 多了補建的 Release，其他沒有改變 | 同上；下一次執行不會再補建 |
| atomic push 被拒絕 | remote 沒有任何改變（補建的 Release 除外） | 下一個等待中的 run 處理；中間的 push 只改 `docs/spectra/` 而沒有等待中的 run 時，以 `workflow_dispatch` 重跑 |
| 建立 Release、補建 Release | 升版時 remote 多了 commit 與 tag，照原樣發佈時只多了 tag；沒有 Release | 下一次執行先補建；一直失敗時依 `docs/releasing.md` 手動建立 |

**驗收**：

- 由 `run-tests.sh` 涵蓋的情境：release-automation 中下列以外的所有情境與範例的每一列，以及 package-distribution「Inspect a release tag」的第一個 THEN。
- 只能以內容審查確認的情境（任務 2.1 逐項對照）：
  - 「Decide whether a push to main runs the workflow」的 5 列。
  - 「A push by the release workflow itself」「Two pushes in quick succession」「A dry run while a release run waits」。
  - 「Map the workflow inputs and repository variables」。
  - 「Release mode」中 workflow 設定變數的那一句。
- 以實際執行確認的情境（opus 第二輪審查 S4）：
  - continuous-integration「Release script tests in CI」的「Run the release script tests」：由任務 1.1 與 4.4 的 CI 確認。
  - 同一條的「A release script test fails」：script 以非 0 結束的部分由任務 1.1 的手動確認（故意讓一個斷言失敗）；job 失敗的部分只以內容審查確認：由任務 2.2 確認新 step 沒有 `continue-on-error`，也沒有吞掉退出碼（例如 `|| true`），所以 step 的非 0 退出碼會讓 job 失敗；4.4 的 CI 只會看到成功（fable 實作前第二輪審查 R1、opus 實作前第三輪審查 S1）。
  - release-automation「Release script test isolation」的「Run the tests inside GitHub Actions」：由任務 1.1 以 `GITHUB_ACTIONS=true` 與暫存的 `GITHUB_STEP_SUMMARY` 執行 `run-tests.sh` 確認，並在 4.4 的 CI 上再看一次。
- package-distribution「Inspect a release tag」的第二個 THEN（從那個 commit 建置的 `lkai -v`）：由「Version commit and tag push」重新建置後的比對涵蓋。
- 靜態檢查：`actionlint` 對兩個 workflow（`.github/actionlint.yaml` 已宣告 `xcode-27`，直接執行，不加 `-ignore`）、`shellcheck` 對所有 script 沒有錯誤。
- 回歸：`swift test` 通過，`git diff` 中 `Sources/` 只有 `LKAIKitInfo.swift` 的 `///` 改變。
- 本機 dry run（真實金鑰）：照原樣發佈、補建 Release 加升版的計畫都印出合理的結果（任務 4.2）。
- PR 上的 CI 通過，script 測試在 runner 的 bash 3.2 也通過。

**範圍**：

- 包含：
  - `release.yml`，以及 `ci.yml` 的一個 step 與檔案開頭的說明。
  - `.github/scripts/release/` 的 script、prompt 範本與測試。
  - `docs/releasing.md`、`LKAIKitInfo.swift` 的 `///`、`docs/adding-a-provider.md`、`docs/spectra/config.yaml`。
- 不包含：
  - `action.yml` 與 `ci.yml` 的其他 step（`01-add-ci`）。
  - `Package.swift` 與 `Sources/` 其他檔案、`lkai` 的行為。
  - branch protection、Linux 支援，以及 Goals / Non-Goals 列出的其他項目。

## Risks / Trade-offs

- [AI 判斷的升級等級不對] → 1.0.0 之前破壞性變更最多升 MINOR，不會意外宣告穩定。owner 可以先以 `dry_run` 試跑；要指定版號時，在 PR 中改版號，照原樣發佈。發錯時依 `docs/releasing.md` 刪除 release 與 tag，再發一個 PR 把版號改成正確的值。
- [diff 中的文字誘導模型（prompt injection）] → 升級等級只接受三個字；AI 的文字在 job log 中以 stop-commands 包起來；prompt 明說資料中的指示要忽略。合併進 `main` 的變更都經過 owner 審查。
- [`main` 之後加上 branch protection 或 required status check] → `GITHUB_TOKEN` 的 push 會被拒絕，每次發版都失敗。能不能讓 `GITHUB_TOKEN` 例外沒有文件依據，加保護前先在 sandbox repo 實測；不行時改用 GitHub App 的 installation token 或 PAT，把那個 App，或 PAT 的擁有者或他的角色加進 bypass（能加的對象以實測為準），並在 checkout 以 `token:` 傳入；這是對 `release.yml` 的修改，要另開 change；記在 `docs/releasing.md`。
- [只改 `.github/`、`CLAUDE.md` 等的合併也會發版] → 依使用者的規則，只有 `docs/spectra/` 不觸發，這類變更通常得到 `patch`。之後要排除其他路徑時，一起修改 `paths-ignore`、`release.sh` 的「只有 docs/spectra 的變更」規則與 spec 的範例表。
- [第一次實際執行時 change 已經封存] → 這個 repo 的封存 commit 在 PR 之內，合併的那次 push 就是 release workflow 的第一次執行，直接發佈 `0.1.0`。下列項目合併前只經過內容審查、actionlint 與本機 dry run：`GITHUB_TOKEN` 的 push 權限、atomic push、`gh release create`、`paths-ignore`、dispatch 的輸入、push 時 `inputs` 的取值。owner 依 `docs/releasing.md` 的「第一次發版後的確認」檢查；失敗時以 `workflow_dispatch` 重跑，原因在程式時另開 change 修正。
- [補建 Release 一直失敗] → 之後每次執行都停在補建，不會發新版；owner 手動為那個 tag 建立 Release 即可解除（`docs/releasing.md`）。
- [`LKAIKitInfo.version` 的宣告寫法改變] → `package-version.sh` 會找不到而失敗；測試以真正的檔案建立暫存 repo，所以在 PR 的 CI 就會失敗。
- [GNU iconv 的行為沒有實測] → 以 `2>/dev/null || true` 不依賴退出碼；之後搬到 Linux 時再實測輸出。
- [每次執行的 AI 費用] → 升版時兩次請求，每次的輸入以 200,000 bytes 的 diff 上限加上 commit 清單與統計為限；照原樣發佈一次；補建 Release 再多一次，最多三次。

## Migration Plan

1. `01-add-ci` 已於 2026-11-24 合併（PR #8，`33210e7`），本 change 可以開始實作。
2. 合併前：owner 在 repository secrets 設定 `LKAI_ANTHROPIC_API_KEY`（任務 4.3）。沒有設定時，合併後的第一次發版會在送出請求前失敗；設定後以 `workflow_dispatch` 重跑即可。
3. 合併後：release workflow 第一次執行，照原樣發佈 `0.1.0`，Release Notes 依全部 commit 的標題撰寫。owner 依 `docs/releasing.md` 確認：
   - tag `0.1.0` 與 release。
   - Actions 的 job summary，包括模式是「release」。
4. BuyLedger 等 App 在 0.x 期間以 `.upToNextMinor(from: "0.1.0")` 引用。
5. 停用：`gh workflow disable release.yml`；發錯的 release 與 tag 在 GitHub 刪除。

## Open Questions

無。
