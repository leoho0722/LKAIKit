## Why

`01-add-ci` 加上 PR 的單元測試與取得 `lkai` 的 setup action 之後，LKAIKit 仍然沒有任何 release tag，App 專案（例如 BuyLedger）只能直接引用分支。`add-swift-package-foundation` 的決策「版本資訊集中於 LKAICore 的 LKAIKitInfo.version」也寫明，最晚要在打第一個 release tag 之前另開 change 處理版號與 tag 的同步。這個 change 讓合併到 `main` 後，自動依變更決定版號，並建立 tag、GitHub Release 與 Release Notes。

這個 change 原本是 `add-ci-cd` 的一部分，2026-11-24 規劃審查後拆出來，依賴 `01-add-ci`。

## What Changes

- **CD（合併到 main 後自動發版）**：新增 `.github/workflows/release.yml`。
  - 觸發：push 到 `main`；變更的檔案全都在 `docs/spectra/` 底下時不觸發。另提供 `workflow_dispatch`，失敗時可手動重跑，或只產生結果、不發版（dry run）；dry run 不會擠掉排隊中的正式發版。
  - 版號：
    - `main` 上的 `LKAIKitInfo.version` 已有同名 tag、之後又有 `docs/spectra/` 以外的變更時，由 AI 依上一個 tag 到 HEAD 的變更回答升級等級（只接受 `major`、`minor`、`patch`），再由 script 算出新版號。
    - 版號還沒有 tag 時（第一次發版，或人工在 PR 中指定版號），照原樣發佈，AI 只寫 Release Notes。
    - 1.0.0 之前，`major` 只升 MINOR，`minor` 與 `patch` 都升 PATCH。
  - 發佈：
    - 需要升版時，CD 建立一個只改 `LKAIKitInfo.version` 的 commit，與 tag 以一次 atomic push（要嘛兩者都成功、要嘛都不成功）推到 `main`，再以 `gh release create --verify-tag` 建立 GitHub Release。
    - tag 與版號相同，沒有 `v` 前綴（例如 `0.1.0`）。
    - 建立 Release 失敗時，下一次執行會先補建（以 `gh release list` 確認有沒有 Release）。
  - Release Notes：由 `lkai` 依 commit 清單、變更統計與程式碼差異撰寫，以正體中文分類列出。
  - 供應商與模型：
    - 可在 `workflow_dispatch` 的輸入，或 repository variables（`LKAI_RELEASE_DEFAULT_PROVIDER`、`LKAI_RELEASE_DEFAULT_MODEL`）設定；優先順序由發版 script 決定，都沒有設定時用 `anthropic` 與 `claude-opus-5-5`。
    - 金鑰來自 repository secrets 的 `LKAI_ANTHROPIC_API_KEY`、`LKAI_OPENAI_API_KEY`、`LKAI_GEMINI_API_KEY`。
- **發版 script**：新增 `.github/scripts/release/`，包含版本計算、讀寫版號、組 prompt 與整個發版流程的 script，以及它們的測試。
  - workflow 只負責準備環境與呼叫 script。
  - 在 GitHub Actions 以外執行時只能 dry run，owner 能在本機安全地試跑。
- **CI**：`.github/workflows/ci.yml` 加上發版 script 的測試。
- **文件**：
  - 新增 `docs/releasing.md`，說明發版的操作：指定版號、dry run、失敗後怎麼接手、發錯怎麼退、切換供應商；`docs/spectra/config.yaml` 指向它。
  - `LKAIKitInfo.version` 的 `///` 改成由 CD 更新；值與公開 API 都不變。
  - `docs/adding-a-provider.md` 補上新增供應商時 release workflow 要多傳的 secret，並把第 7 章「調整 `LKAIKitInfo.version` 並打第一個 release tag」一列改成「已解決」。

## Non-Goals (optional)

見 design.md 的 Goals / Non-Goals。

## Capabilities

### New Capabilities

- `release-automation`: 合併到 `main` 後的自動發版，涵蓋：
  - 觸發與不觸發的條件，以及執行模式（dry run 與正式發版）。
  - 版號如何決定：AI 回答的升級等級、1.0.0 之前的規則、照原樣發佈的情況。
  - 升版 commit 與 tag 的推送、GitHub Release 的建立與補建。
  - Release Notes 的內容、供應商與模型的設定、執行報告。
  - 各種失敗時的處理，以及發版 script 測試的隔離。

### Modified Capabilities

- `continuous-integration`: 新增「Release script tests in CI」：CI 的 job 在 `swift test` 之後執行發版 script 的測試，job 的 runner 標籤和 release workflow 相同；測試失敗時 job 失敗。
- `package-distribution`: 新增「release tag 與套件版號一致」的 requirement：每個 release tag 的名稱，等於它指向的 commit 中 `LKAIKitInfo.version` 的值。

## Impact

- 新增的檔案：
  - `.github/workflows/release.yml`
  - `.github/scripts/release/` 的 script、prompt 範本與測試
  - `docs/releasing.md`
- 修改的檔案：
  - `.github/workflows/ci.yml`：加上發版 script 測試的 step。
  - `Sources/LKAICore/LKAIKitInfo.swift`：只改 `///`。
  - `docs/adding-a-provider.md`、`docs/spectra/config.yaml`。
- 公開 API：不變。`Package.swift` 不變，沒有新增 target、product 或外部依賴。
- GitHub repository 設定：
  - 由 owner 設定：repository secret `LKAI_ANTHROPIC_API_KEY`（使用其他供應商時改設對應的 secret）。
  - 選填：repository variables `LKAI_RELEASE_DEFAULT_PROVIDER`、`LKAI_RELEASE_DEFAULT_MODEL`。
  - release workflow 以 `GITHUB_TOKEN` 直接推送到 `main`。`main` 之後加上 branch protection 或 required status check 時，這個 push 會被拒絕；要先實測能不能讓 `GITHUB_TOKEN` 例外；不行時改用 GitHub App 或 PAT 的 token，並在 checkout 以 `token:` 傳入（做法見 `docs/releasing.md`）。
- 費用：
  - repo 是 public，標準的 GitHub-hosted runner 不收費。
  - 一次執行最多呼叫三次 AI：補建 Release 一次，升版兩次（判斷升級等級、撰寫 Release Notes）；照原樣發佈一次。費用由 secret 的金鑰負擔。
- 第一次發版：這個 change 合併到 `main` 後，CD 會照原樣把目前的 `0.1.0` 發佈為第一個 release；第一個 tag 之後，`config.yaml` 中「第一個 release tag 之後」的 API 演進規則開始生效。
- 依賴：`01-add-ci` 的 `action.yml` 與 `ci.yml`；`01-add-ci` 已於 2026-11-24 合併（PR #8，merge commit `33210e7`）。
