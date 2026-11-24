## Why

目前發版只排除 `docs/spectra/` 的變更。只改 repo 根目錄的 `README.md`、`CLAUDE.md` 或 `AGENTS.md`（給人與 coding agent 看的說明文件）的合併，也會開 runner、送出 AI 請求並升版，發出一個 library 與 `lkai` 都沒有改變的版本。這三個檔案剛以 `/init` 重寫，之後也會跟著其他 change 調整，所以現在把它們加進排除。

## What Changes

- 新增「不發版的檔案」的定義：`docs/spectra/` 底下的檔案，以及 repo 根目錄的 `README.md`、`CLAUDE.md`、`AGENTS.md`。只比對根目錄的這三個路徑，`docs/spectra/` 以外的子資料夾中同名的檔案（例如 `docs/README.md`）照常發版。
- 觸發：push 到 `main` 時，改動的檔案全部是不發版的檔案，就不執行 release workflow（`release.yml` 的 `paths-ignore` 加上這三個檔案）。
- 計畫：目前版號的 tag 之後，變更的檔案全部是不發版的檔案時，`release.sh` 判斷為沒有可發佈的變更，以 0 結束；手動觸發（`workflow_dispatch`）時也一樣，不會升版。`release.sh` 的清單寫在開頭的一個具名變數，pattern 與 `paths-ignore` 逐字相同。
- 新增 bash 測試：讀出 `release.yml` 的整個 `paths-ignore` 區塊，逐條建立符合的檔案並執行 `release.sh`，確認每一條都判斷為沒有可發佈的變更；兩處的清單不一致時測試失敗，並寫出是哪一條、要改哪裡。區塊中有認不得的行或認不得形狀的 pattern 時也失敗，不會默默少檢查。
- 清單只在 `paths-ignore`、`release.sh` 的具名變數與 `docs/releasing.md` 的一節列出，其他說明（註解、手冊的其他章節）都引用它們，不重抄。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `release-automation`: 新增「不發版的檔案」的 requirement，並把觸發的範例表搬進它；「Release workflow trigger」與「Release plan」改為以它判斷要不要執行、有沒有可發佈的變更。

## Impact

- 修改的檔案：
  - `.github/workflows/release.yml`：`paths-ignore` 與開頭的註解。
  - `.github/scripts/release/release.sh`：不發版的 pattern 清單、判斷沒有可發佈的變更時排除的路徑，以及開頭的註解。
  - `.github/scripts/release/tests/test-release.sh`：新增的測試。
  - `docs/releasing.md`：第 2 章的「計畫」、3.1、3.3、4.1 的表格、4.4 與 5.2。
- 公開 API、`lkai` 的命令列介面與 setup action 都不變。
- 合併本 change 的那一次改到 `.github/`，不是只有不發版的檔案，所以那次合併仍會發版；升級等級由 AI 判斷。
- `/init` 產生的 `CLAUDE.md`、`AGENTS.md`、`README.md` 還沒有 commit，不屬於本 change。它們說明發版的句子改成指向 `docs/releasing.md`，不列清單；在本 change 那次的 Release run 成功結束之後，以只改這三個檔案的 PR 合併。那次合併不應開 Release run，同時作為合併後的實際確認。
