## Why

LKAIKit 已經有三家供應商與 `lkai` 命令列工具，但還沒有任何 CI：PR 合併前沒有自動跑測試。之後的自動發版（`02-add-release-automation`）也需要在 workflow 中取得 `lkai`。這個 change 先加上 PR 的單元測試，並把 `lkai` 包成這個 repo 與其他 repo 都能以 `uses:` 引用的 GitHub Action。

這個 change 原本是 `add-ci-cd` 的一部分。2026-11-24 的規劃審查後，使用者決定拆成兩個 change：CI 風險低、馬上有用，而且 runner 預設的 Xcode 能不能編譯，要等第一次 CI 才知道；自動發版會產生公開的 tag，也需要推 commit 到 `main` 的權限，放在第二個 change 處理。

## What Changes

- **CI（PR 時跑單元測試）**：新增 `.github/workflows/ci.yml`。每個 PR 在 GitHub-hosted 的 `xcode-27` runner（macOS 27、Xcode 27）執行：
  - `swift test`：不提供任何 `LKAI_*_API_KEY`，需要真實 API Key 的測試（`*LiveTests`）依既有的 `.enabled(if:)` 顯示為略過，其餘測試都要通過。
  - Action 的試跑：在任何建置之前以 `uses: ./` 建構 `lkai`，確認 `lkai -v` 印出 action 回報的版本，而且 action 回報的 `path` 是名為 `lkai`、印出同樣版本的可執行檔。
- **Composite action（取得 `lkai`）**：新增 repo 根目錄的 `action.yml`。在 macOS runner 上以 action 所在的原始碼建構 release 版的 `lkai`，把它所在的建置資料夾加進 `PATH`，並輸出路徑與版本。這個 repo 以 `uses: ./` 使用；其他 repo 以 `uses: leoho0722/LKAIKit@main`（或某個 tag）使用。不在 macOS runner 上使用時立即失敗，並說明需要 macOS runner。
- **新增供應商的清單**：`docs/adding-a-provider.md` 第 7 章「`lkai` 要和兩個 bundle 放在同一個資料夾」一列，改寫為這個 change 決定的做法（不複製 `lkai`，直接從建置資料夾執行）；第 3 章開頭說明出處的地方補一句：只寫編號的 01 到 04 指哪一組 change，之後的 change 一律寫完整名稱。

## Non-Goals (optional)

見 design.md 的 Goals / Non-Goals。

## Capabilities

### New Capabilities

- `continuous-integration`: PR 觸發的 CI：在哪個 runner 執行、跑哪些檢查、需要真實 API Key 的測試如何略過，以及什麼情況算失敗。
- `lkai-setup-action`: 以 composite action 在 macOS runner 上從原始碼建構 `lkai`、加進 `PATH` 並輸出路徑與版本，讓這個 repo 與其他 repo 的 workflow 都能使用。

### Modified Capabilities

（無）

## Impact

- 新增的檔案：`.github/workflows/ci.yml`、`action.yml`（repo 根目錄）。
- 修改的檔案：`docs/adding-a-provider.md`（第 7 章 bundle 一列的處理方式，以及第 3 章開頭說明出處的一句）。
- 公開 API、`Package.swift` 與 `Sources/`：不變，沒有新增 target、product 或外部依賴。
- GitHub repository 設定：不需要任何 secret。之後要把 CI 設為 required check 時，由 owner 在 GitHub 設定。
- 費用：repo 是 public，標準的 GitHub-hosted runner 不收費。
- 後續：`02-add-release-automation` 依賴這個 change 的 action 與 CI。
