# 發版操作手冊

合併到 `main` 之後，GitHub Actions 的 release workflow（`.github/workflows/release.yml`）會判斷要不要發版、算出版號、請 AI 撰寫 Release Notes，並建立版號 commit、tag 與 GitHub Release。這份手冊整理怎麼觸發、試跑、切換供應商與模型、失敗時怎麼接手，以及需要知道的限制。

## 1. 怎麼使用這份手冊

- **什麼時候讀**：修改發版流程的 change 開始前；以及要手動觸發、試跑、切換供應商與模型，或發版失敗、發錯版的時候。
- **權威順序**：
  - 系統的行為以 `docs/spectra/specs/release-automation/spec.md` 為準（tag 與版號的關係見 `docs/spectra/specs/package-distribution/spec.md`）。這份手冊是操作方式；和 spec 不同時，修正這份手冊。
  - 封存的 design（`docs/spectra/changes/archive/`）只記錄當時的決定；和這份手冊不同時，以這份手冊為準。
- **什麼時候更新**：修改 release-automation spec、`.github/workflows/release.yml` 或 `.github/scripts/release/` 的 change，封存前都要檢查並更新這份手冊。
- **來源**：本手冊由 `02-add-release-automation` 建立。

## 2. 發版怎麼運作

- **觸發**：push 到 `main`，或手動的 `workflow_dispatch`（見 3.1）。
- **模式**：
  - 正式發版（release）：會建立 commit、tag 與 Release。push 觸發時一律是這個模式。
  - 試跑（dry run）：只印出計畫與 Release Notes，不修改檔案、不建立 commit 與 tag、不推送、不建立 Release。只有手動觸發並把 `dry_run` 設成 `true`，或在本機執行 script 時才是這個模式。
- **計畫**：`release.sh` 讀 `HEAD` 的 `LKAIKitInfo.version`（`Sources/LKAICore/LKAIKitInfo.swift`），再依 tag 決定下列三種之一：
  - 沒有可發佈的變更（`nothing-to-release`）：這個版號的 tag 已經存在，而且 tag 之後沒有新的 commit，或只有不發版的檔案（見 3.1）的變更。以 0 結束，不發版；手動觸發時也一樣。
  - 升版（`version-bump`）：這個版號的 tag 已經存在，tag 之後有不發版的檔案（見 3.1）以外的變更。AI 回答升級等級，script 算出新版號，修改 `LKAIKitInfo.version`，commit、打 tag、推送，再建立 Release。
  - 照原樣發佈（`release-as-is`）：這個版號還沒有 tag。不問 AI 升級等級，不建立 commit，直接在 `HEAD` 打這個版號的 tag、只推 tag，再建立 Release。第一次發版與人工指定版號都是這一種。
- **步驟**：報告的「失敗的步驟」就是下列名稱之一：

  | 順序 | 步驟 | 做什麼 |
  | --- | --- | --- |
  | 1 | 解析供應商與模型 | 依 3.5 的優先順序決定供應商與模型 |
  | 2 | 讀取版號 | 讀 `HEAD` 的版號，列出版本 tag；版號格式不對、有比目前版號更大的 tag、列不出 tag、版本 tag 沒有指向 commit，或判斷祖先時 git 出錯時失敗 |
  | 3 | 檢查 Release | 目前版號的 tag 已存在時，以 `gh release list` 確認它有沒有 Release |
  | 4 | 補建 Release | 那個 tag 沒有 Release 時，撰寫它的 Release Notes 並建立（試跑只撰寫、不建立）；找不到補建的上一版（版本 tag 沒有指向 commit，或判斷祖先時 git 出錯）時也在這一步失敗 |
  | 5 | 判斷升級等級 | 升版時請 AI 回答 `major`、`minor` 或 `patch` |
  | 6 | 撰寫 Release Notes | 請 AI 撰寫這次的 Release Notes；試跑到這裡結束 |
  | 7 | 修改版號 | 升版時修改 `LKAIKitInfo.version` |
  | 8 | 重新建置 | 升版時重新建置 `lkai`，確認它印出的版號是新版號 |
  | 9 | 建立 commit 與 tag | 升版時 commit 版號檔並打 tag；照原樣發佈時只打 tag |
  | 10 | 推送 | 升版時以一次 atomic push 推 commit 與 tag；照原樣發佈時只推 tag |
  | 11 | 建立 Release | 以 `--verify-tag` 建立這個版號的 Release |

  所有可能失敗的檢查（AI 的回答、修改版號、重新建置）都在寫入 remote 之前。
- **AI 請求與費用**：照原樣發佈一次（Release Notes）；升版兩次（升級等級、Release Notes）；補建 Release 再多一次，所以補建加升版時最多三次。每次的輸入是 commit 標題、變更統計，加上 200,000 bytes 以內的程式碼 diff（超過時省略 diff，並在 prompt 中說明）。實際用量以供應商後台為準。
- **不會循環**：release workflow 以 `GITHUB_TOKEN` 推送版號 commit 與 tag，`GITHUB_TOKEN` 觸發的事件不會再開新的 workflow run，所以不會再觸發自己。

## 3. 一般操作

### 3.1 觸發

- **push 到 `main`**：自動執行。這次 push 改動的檔案全部是不發版的檔案時不執行；只要有一個檔案不是就會執行，所以只改 `docs/` 的其他文件（包含這份手冊）或 `.github/` 的合併也會發版（通常得到 `patch`）。
  - 不發版的檔案（這份手冊只在這裡列出清單，其他章節引用這裡）：
    - `docs/spectra/` 底下的檔案。
    - repo 根目錄的 `README.md`、`CLAUDE.md`、`AGENTS.md`。`docs/spectra/` 以外的子資料夾中同名的檔案（例如 `docs/README.md`）照常發版。
  - 這份清單寫在 `release.yml` 的 `paths-ignore`（決定要不要開 runner）與 `release.sh` 的 `release_neutral_patterns`（決定要不要發版）。手動觸發不經過 `paths-ignore`，但 `release.sh` 排除同樣的檔案，所以目前版號的 tag 之後只有不發版的檔案的變更時，手動觸發也以「沒有可發佈的變更」結束。要再加路徑時見 5.2。
- **手動（`workflow_dispatch`）**：用來在失敗之後重跑，或試跑。這個 workflow 合併進預設分支之後才能使用（GitHub 只在 workflow 檔案已經在預設分支上時才會收到這個事件）。不論從哪個分支觸發，job 取的都是 `main` 最新的 commit。
  - GitHub 網頁：Actions → Release → Run workflow，填 `provider`、`model` 與 `dry_run`。
  - 命令列：

    ```bash
    # 重跑一次正式發版
    gh workflow run release.yml

    # 試跑
    gh workflow run release.yml -f dry_run=true

    # 本次改用其他供應商與模型（兩個都要給）；可以同時試跑
    gh workflow run release.yml -f provider=openai -f model=<模型> -f dry_run=true
    ```
- **排隊**：能發版的 run（push，以及不是試跑的手動觸發）一次只執行一個，新的 run 不取消執行中的 run；等待中的 run 會被更新的 run 取代，沒有關係，因為每個 run 都處理 job 開始時 `main` 最新的 commit。試跑用另一組排隊，不會取代等待中的正式 run。

### 3.2 版號怎麼決定

- 版號只有一個來源：`LKAIKitInfo.version`，格式 `MAJOR.MINOR.PATCH`，tag 與 Release 的標題都是同一個字串，沒有 `v` 前綴。
- 升版時 AI 只回答 `major`、`minor` 或 `patch`（回答不是這三個字之一時，這次執行失敗，不會發出奇怪的版號）。`major` 指破壞公開介面的變更，`minor` 指向下相容的新增，`patch` 指其他變更；公開介面包含 `LKAIKit` library 的公開宣告、`lkai` 的命令列介面，以及 setup action 的輸入與輸出。
- 新版號由 script 計算：

  | 目前版號 | AI 的回答 | 新版號 |
  | --- | --- | --- |
  | `0.Y.Z` | `major` | `0.(Y+1).0` |
  | `0.Y.Z` | `minor` 或 `patch` | `0.Y.(Z+1)` |
  | `X.Y.Z`（`X` 至少是 1） | 照一般的 SemVer | 照一般的 SemVer |
- 1.0.0 代表公開介面穩定，由人決定：升版的計算永遠不會到 1.0.0，要發 1.0.0 時依 3.3 指定版號。
- 0.x 期間，`.upToNextMinor(from:)` 引用的 App 只會自動拿到不破壞的更新（`major` 升 MINOR，其他升 PATCH）。

### 3.3 指定版號

- 開一個 PR，把 `LKAIKitInfo.version` 改成想要的版號，條件是這個版號還沒有 tag，而且比所有版本 tag 都大。例如要發 `1.0.0`。
- 合併後，因為這個版號沒有 tag，計畫是照原樣發佈：不問 AI 升級等級、不建立 commit，直接在合併後的 `HEAD` 打這個 tag；AI 只撰寫 Release Notes，範圍是 `HEAD` 的祖先中最高的版本 tag 到 `HEAD`。
- 版號比現有的某個 tag 小時，這次執行會在「讀取版號」失敗，訊息寫出最高的 tag。版號和現有的 tag 相同時，視為那個版號已經發佈：tag 之後有不發版的檔案（見 3.1）以外的變更就升版，否則沒有可發佈的變更。
- `LKAIKitInfo.swift` 中宣告版號的那一行必須維持原本的寫法（`public static let version: String = "<版號>"`，整個檔案剛好一行）；寫法改變時 `release.sh` 會在「讀取版號」失敗，PR 的 CI 也會先失敗。

### 3.4 試跑（dry run）

試跑會印出計畫與 Release Notes，不改任何東西；但會送出 AI 請求，**會花費用**。

- **GitHub 上**：以 3.1 的 `dry_run` 輸入執行。結果在這次 run 的 job summary 與 log。
- **本機**：
  - 前置條件：
    - `PATH` 上有 `lkai`。例如先建置，再把 `--show-bin-path` 的資料夾加進 `PATH`。
    - 設定所選供應商的金鑰環境變數（對照見 3.5），例如 `LKAI_ANTHROPIC_API_KEY`。不要把金鑰寫在命令列引數或檔案裡。
    - `gh` 已登入（`gh auth status`）。版號已經有 tag 時，script 會執行 `gh release list`；沒有登入時，會在「檢查 Release」失敗。
    - 在 repo 的根目錄執行。
  - 本機看的是目前的 `HEAD` 與本機的 tag，不是 GitHub 上的狀態。執行前先切到最新的 `main` 並取回 tag（`git fetch --tags`）。工作目錄中還沒有 commit 的修改不會被讀到，也不會被改。
  - 指令：

    ```bash
    swift build -c release --product lkai
    export PATH="$(swift build -c release --product lkai --show-bin-path):$PATH"
    gh auth status
    bash .github/scripts/release/release.sh
    ```

    不設定 `LKAI_RELEASE_DRY_RUN`（或設成 `true`）就是試跑。要指定本次的供應商與模型時，另外設定 `LKAI_RELEASE_PROVIDER` 與 `LKAI_RELEASE_MODEL`。
  - 本機把 `LKAI_RELEASE_DRY_RUN` 設成 `false` 會被拒絕：正式發版只在 GitHub Actions 中執行。其他不認得的值（例如 `TRUE`、`1`）也會被拒絕，訊息寫出那個值。

### 3.5 切換供應商與模型

- **選擇的優先順序**（由 `release.sh` 決定）：
  - 供應商：本次的輸入 → repository 的預設值 → `anthropic`。
  - 模型：本次指定了供應商時，只看本次的模型；否則本次的模型 → repository 的預設模型 → 兩個預設值都沒有設定時用 `claude-opus-5-5`。
  - 找不到模型時，在送出請求之前失敗（步驟「解析供應商與模型」），訊息寫出 `LKAI_RELEASE_MODEL` 與 `LKAI_RELEASE_DEFAULT_MODEL`。所以只設定預設供應商、沒有設定預設模型時會失敗；手動觸發時指定了 `provider`，也一定要同時指定 `model`。
  - script 不檢查供應商的值，也不檢查金鑰，原樣交給 `lkai`；不認得的供應商或缺少金鑰時，`lkai` 在送出請求前就拒絕，這次執行失敗，還沒有改任何東西。
- **改 repository 的預設值**（push 觸發的正式發版用這組）：

  ```bash
  gh variable set LKAI_RELEASE_DEFAULT_PROVIDER --body openai
  gh variable set LKAI_RELEASE_DEFAULT_MODEL --body <模型>

  # 改回預設（anthropic 與 claude-opus-5-5）
  gh variable delete LKAI_RELEASE_DEFAULT_PROVIDER
  gh variable delete LKAI_RELEASE_DEFAULT_MODEL
  ```
- **供應商與金鑰**：`--provider` 的值要是 `lkai` 認得的值。每個供應商讀不同的環境變數，在 workflow 中對應同名的 repository secret：

  | `--provider` 的值 | 金鑰的環境變數（與 repository secret 同名） |
  | --- | --- |
  | `anthropic` | `LKAI_ANTHROPIC_API_KEY` |
  | `openai` | `LKAI_OPENAI_API_KEY` |
  | `google` | `LKAI_GEMINI_API_KEY` |

  用到的供應商要先有對應的 secret。`gh secret set` 從標準輸入讀值，不要把金鑰放在命令列引數：

  ```bash
  # 互動式輸入，不會顯示
  gh secret set LKAI_OPENAI_API_KEY
  # 或從剪貼簿（macOS）
  pbpaste | gh secret set LKAI_OPENAI_API_KEY
  ```
- **新增一家供應商**：`lkai` 要先支援它（見 `docs/adding-a-provider.md`）。發版這邊要改的有三處：`release.yml` 的 `env` 加上這家的 secret、release-automation spec 中列出 secret 的那一句，以及 GitHub 上的 repository secret。
- 供應商與模型的變數都原樣傳進 `release.sh`，workflow 不組合也不給預設值。

### 3.6 看報告

模式選定之後，每次執行（沒有可發佈的變更、試跑、發佈成功、失敗）都會印出一份報告，並附加到這次 run 的 job summary（Actions 的 run 頁面）。每一行是「名稱：值」（job summary 中每行前面多一個「- 」成為清單），不知道的行不印：

| 行 | 內容 |
| --- | --- |
| 模式 | `release` 或 `dry-run` |
| 供應商、模型 | 這次實際使用的值 |
| 計畫 | `nothing-to-release`、`version-bump` 或 `release-as-is` |
| 升級等級 | 升版時 AI 回答的 `major`、`minor` 或 `patch` |
| 上一版、新版號 | 照原樣發佈而且沒有上一版時，上一版寫「（無）」；沒有可發佈的變更時兩行都不印 |
| 補建的 Release | 這次補建（試跑時是「將會補建」）的 Release 的 tag |
| 失敗的步驟 | 失敗時才有，名稱見第 2 章的步驟表 |

- 沒有可發佈的變更時，各行之後有一行「沒有可發佈的變更。」。
- 以 0 結束的報告，在各行之後依序接「補建的 Release Notes（<tag>）：」與補建的文字（有補建時），以及「Release Notes：」與這次的 Release Notes（有的話）。失敗的報告沒有 Release Notes。
- job log 中，AI 的文字（Release Notes、被拒絕的回答，以及 `lkai` 的 stderr）前後各有一行 `::stop-commands::<token>` 與 `::<token>::`：這是為了讓 GitHub 不去執行文字裡可能出現的 workflow command，不是錯誤。job summary 不加這兩行。`lkai` 的 stderr 整段都包起來（模型拒答時，裡面有模型寫的拒答文字），所以缺少金鑰、逾時這類一般的錯誤旁邊也會看到這兩行；`lkai` 的訊息不會成為 annotation，而且要等 `lkai` 結束才印出。失敗的原因看 `release.sh` 自己寫的 `::error::` 那一行與報告的「失敗的步驟」。本機執行時照原樣印出，不加這兩行。
- 模式還沒選定就失敗時（例如 `LKAI_RELEASE_DRY_RUN` 的值不認得）沒有報告，只有錯誤訊息。

## 4. 失敗與回退

### 4.1 各種失敗時怎麼接手

先看 job summary 的「失敗的步驟」與 log 中的錯誤訊息（`::error::` 開頭），再依下表處理。

| 失敗的步驟 | repo 的狀態 | 接手的方式 |
| --- | --- | --- |
| 解析供應商與模型、讀取版號、檢查 Release、判斷升級等級、撰寫 Release Notes、修改版號、重新建置、建立 commit 與 tag（這次沒有補建時） | 沒有任何改變 | 修正原因（例如補上金鑰、改正版號）後以 `workflow_dispatch` 重跑，或等下一次會觸發的合併（見 3.1） |
| 補建 Release 成功之後，上一列的任一步失敗 | 多了補建的 Release，其他沒有改變 | 同上；下一次執行不會再補建 |
| 補建 Release | 沒有任何改變（那個 tag 還是沒有 Release） | 下一次執行會再試一次；一直失敗時見 4.2 |
| 推送 | remote 沒有任何改變（補建的 Release 除外）：atomic push 讓 commit 與 tag 一起成功或一起失敗，被拒絕通常是 `main` 在執行期間有新的 commit | 下一個等待中的 run 會處理最新的 `main`；中間的 push 只改了不發版的檔案（見 3.1）、沒有等待中的 run 時，以 `workflow_dispatch` 重跑 |
| 建立 Release | 升版時 remote 多了版號 commit 與 tag，照原樣發佈時多了 tag；沒有 Release。SwiftPM 只看 tag，App 不受影響 | 下一次執行會先補建這個 Release；一直失敗時見 4.2 |

- 除了最後一列，失敗時 remote 的 `main` 與 tag 都沒有動，重跑是安全的；最後一列重跑時，會先補建那個 Release，再照常判斷之後的計畫。
- AI 請求失敗（`lkai` 以非 0 結束，包含逾時、輸出被截斷、不認得的供應商、缺少金鑰）、AI 的升級等級回答不是三個字之一，或 Release Notes 是空的，都算這一步失敗，stderr 會保留 `lkai` 的訊息（在 GitHub Actions 中包在標記之間，見 3.6）。
- 版本 tag 沒有指向 commit（例如指向 tree），或列不出 tag（`git tag --list` 失敗）時，在「讀取版號」失敗；補建 Release 時找上一版遇到這種 tag，失敗的步驟是「補建 Release」。修正那個 tag 後重跑。
- 被拒絕的升級等級回答最多印出前 200 bytes；在 GitHub Actions 中，它包在 `::stop-commands::<token>` 與 `::<token>::` 之間。

### 4.2 補建 Release 一直失敗

某個 tag 沒有 Release，而補建一直失敗（例如 AI 拒絕處理那段 diff）時，之後每次執行都會停在「補建 Release」，不會發新版。由 owner 手動為那個 tag 建立 Release 即可解除：

```bash
gh release create <tag> --verify-tag --title <tag> --notes "<說明>"
```

舊的 tag 少了 Release 時也手動建立：「檢查 Release」只檢查目前版號的 tag，而且只看最近 100 個 Release，不會補建更舊的。

### 4.3 發錯時怎麼退

例如 AI 判斷的升級等級不對，或發出了不該發的版號。

**要先擋住 release workflow，再刪 tag。** 刪掉 tag 之後，到修正版號的 PR 合併之前，`main` 上的版號仍是發錯的那一個，而且已經沒有 tag。這段期間只要有任何會觸發 release workflow 的合併（或手動觸發），就會照原樣把那個錯誤的版號再發一次。

1. 先停用 release workflow（見 4.4）：

   ```bash
   gh workflow disable release.yml
   ```

   停用只擋住之後的觸發，不保證已經在排隊或執行中的 run 會被取消。先用 `gh run list --workflow release.yml` 確認沒有這樣的 run；有的話，等它結束，或以 `gh run cancel <run id>` 取消，再繼續。

   不想停用時，也可以確認修正版號的 PR 就是下一個合併：PR 已經通過檢查、隨時可以合併，沒有別的 PR 會排在它前面，也沒有排隊中的 run，刪掉 tag 之後馬上合併它。這個做法只要中間出一點差錯，就會再發一次錯的版號，所以建議停用。
2. 刪除 Release 與 tag，再改版號：tag 還在時，比它小的版號會在「讀取版號」被擋下。

   ```bash
   gh release delete <tag> --cleanup-tag
   ```

   `--cleanup-tag` 會一併刪除 remote 的 tag。`gh release delete` 預設會詢問確認；加 `--yes` 可略過。
3. 開 PR，把 `LKAIKitInfo.version` 改成正確的版號（見 3.3；要比刪除之後最高的 tag 大），確認檢查都通過後合併。版號 commit 已經在 `main` 上，不需要 revert。
4. PR 合併之後，恢復 release workflow，並以 `workflow_dispatch` 觸發一次：

   ```bash
   gh workflow enable release.yml
   gh workflow run release.yml
   ```

   停用期間的合併不會觸發 release workflow，恢復時也不會補跑，所以要手動觸發一次。這次執行看到的版號是修正後的那一個，它沒有 tag，所以照原樣發佈。想先確認時，加 `-f dry_run=true` 試跑，再正式觸發。
5. 本機的舊 tag 要自己刪：`git tag -d <tag>`（或 `git fetch --prune --prune-tags`）。
6. 已經用 SwiftPM 解析過那個 tag 的 App，要重新解析套件版本（例如在 Xcode 執行 Reset Package Caches），否則仍會留著舊的解析結果。

只是 Release Notes 寫得不好、版號沒有錯時，不必退版，也不必停用 workflow，直接修改那個 Release 的內容：`gh release edit <tag> --notes-file <檔案>`。

### 4.4 停用與恢復

```bash
gh workflow disable release.yml
gh workflow enable release.yml
```

- 停用之後，push 不會再觸發它，所以停用期間合併的變更不會發版；恢復時不會補跑停用期間錯過的 push。恢復之後，以 `workflow_dispatch` 觸發一次，或等下一次會觸發的合併（見 3.1），都會處理 `main` 最新的 commit（每個 run 都處理最新的 `main`，停用期間合併的變更也包含在內）。
- 停用只擋住之後的觸發，不保證已經在排隊或執行中的 run 會被取消。停用之後用 `gh run list --workflow release.yml` 確認；有的話等它結束，或以 `gh run cancel <run id>` 取消。
- 發錯版要退版時，一定要先停用，見 4.3。

## 5. 需要知道的限制

### 5.1 `main` 加上 branch protection 之後

`main` 加上 branch protection 或 required status check 之後，`GITHUB_TOKEN` 直接推上 `main` 的版號 commit 會被拒絕：它沒有 CI 的結果。GitHub 的文件沒有寫明能不能讓 `GITHUB_TOKEN` 例外，這個 repo 也沒有實測過。處理方式：

1. 加保護之前，先在 sandbox repo 實測 `GITHUB_TOKEN` 能不能例外。
2. 不行時，改用 GitHub App 的 installation token 或 PAT，並把對應的對象加進 bypass。bypass 能加哪些對象以實測時 GitHub 提供的為準（官方 API 的描述目前列出 App、角色、team、deploy key 與使用者）：用 App 的 token 時加那個 App，用 PAT 時加 PAT 的擁有者或他的角色。
3. 不論哪一種，都要在 `release.yml` 的 checkout 以 `token:` 傳入，`git push` 才會用到它。
4. 改用這類 token 之後，版號 commit 的 push 會再觸發一次 release workflow，它會以「沒有可發佈的變更」結束。
5. 改用其他 token 是對 `release.yml` 的修改，要另開 change：同時更新 release-automation「Release workflow trigger」中只描述 `GITHUB_TOKEN` 的情境「A push by the release workflow itself」，並補上「以其他 token 推送時會再觸發一次，並以沒有可發佈的變更結束」的情境。

### 5.2 其他限制

- 以 `GITHUB_TOKEN` 建立的 Release 不會觸發其他 workflow。
- 第一個 tag 之後，`docs/spectra/config.yaml` 的「API 演進規則」開始生效。例如公開 enum 的 case 增減 associated value，會破壞 App 建立與比對那個 case 的寫法，第一個 release tag 之後要加資料時，改用 struct 帶資料。
- 不發版的檔案（見 3.1）以外的文件，例如這份手冊，改了也會觸發發版。之後要再排除其他路徑時，一起修改：
  - spec：release-automation「Release-neutral files」的定義，以及它的兩張範例表（「changed files and whether the workflow runs」與「changed file and plan」）。
  - `release.yml` 的 `paths-ignore` 與 `release.sh` 的 `release_neutral_patterns`：兩處逐字相同、順序相同。只有兩種形狀可以照抄：不含 `*`、`?`、`+`、`[`、`]`、`!` 的完整路徑，以及以 `/**` 結尾的資料夾。其他形狀在 GitHub 與 git 的語意不同或沒有查證（例如 GitHub 的 `?` 是「前一個字元出現零或一次」，git 的 `?` 是任意一個字元），要另外換算 `release.sh` 的寫法，並擴充 `test-release.sh` 讀取 `paths-ignore` 的規則。
  - 這份手冊 3.1 的清單。
  - `test-release.sh` 會讀出 `paths-ignore` 的每一條，逐條確認 `release.sh` 判斷為沒有可發佈的變更；只改了 `paths-ignore`、忘了改 `release.sh` 時，這個測試會失敗，並寫出是哪一條與要改的地方。`paths-ignore` 的清單中不放註解與空行，寫成同一行的清單（`paths-ignore: [...]`）或測試認不得的寫法時，測試也會失敗。
- 「檢查 Release」只看目前版號的 tag，而且只看最近 100 個 Release。建立 Release 失敗後，下一次會觸發的合併（見 3.1）剛好是人工指定版號的 PR（照原樣發佈）時，舊 tag 的 Release 不會再被補建，由 owner 手動建立（4.2）。
- 同一次執行最多建立兩個 Release：補建的那一個，以及這次發佈的版號。
- `release.sh` 依賴 `lkai` 的介面：它以 `lkai --provider <供應商> --model <模型> --prompt-file <檔案> --timeout 180` 送出請求（Release Notes 另加 `--max-output-tokens 8192`），並只看退出碼判斷成敗：0 是成功，其他都是失敗。`lkai` 改了這些選項或退出碼時，要一起檢查 `release.sh` 的 `ask_lkai` 與它的三個呼叫處（補建 Release、判斷升級等級、撰寫 Release Notes）。bash 測試用的是假的 `lkai`，抓不到這種改變，要到下一次發版才會失敗；失敗時還沒有改任何東西（4.1 的第一列）。
- `--timeout 180`、`--max-output-tokens 8192` 與 diff 的上限 200,000 bytes 都是估計值，輸入比 `lkai` 的實際 API 測試大很多。逾時（`lkai` 以 1 結束）或輸出被截斷（以 2 結束）時，這次執行失敗，不會發出不完整的 Release Notes；調整的地方：`--timeout` 在 `release.sh` 的 `ask_lkai`，`--max-output-tokens` 在撰寫 Release Notes 與補建 Release 的兩個呼叫處，diff 的上限是 `make-prompt.sh` 的預設值（讀 `LKAI_RELEASE_DIFF_LIMIT`，預設 200000；測試以它改小）。

## 6. 第一次發版後的確認

合併進 `main` 的那次 push 就是 release workflow 的第一次執行，直接照原樣發佈 `0.1.0`。下列項目在合併前只經過內容審查、`actionlint` 與本機試跑，沒有實際執行過：`GITHUB_TOKEN` 的 push 權限、atomic push、`gh release create`、`paths-ignore`、dispatch 的輸入，以及 push 觸發時 `inputs` 的取值。合併前先確認 repository secret `LKAI_ANTHROPIC_API_KEY` 已經設定（`gh secret list`）；沒有設定時，第一次發版會在送出請求之前失敗，設定後以 `workflow_dispatch` 重跑即可。

合併後逐項確認：

1. **tag**：`0.1.0` 指向 release workflow 開始時 `main` 最新的 commit（沒有其他合併時，就是合併後 `main` 的最新 commit）：

   ```bash
   git fetch --tags
   git rev-parse '0.1.0^{commit}'
   git rev-parse origin/main
   ```
2. **Release**：標題是 `0.1.0`，內容是依全部 commit 標題撰寫的 Release Notes：`gh release view 0.1.0`。
3. **job summary**：Actions 這次 run 的 summary，「模式」是 `release`（這也確認 push 觸發時 `inputs.dry_run` 是空的，模式是正式發版），計畫是 `release-as-is`，上一版是「（無）」，新版號是 `0.1.0`。
4. **`main` 沒有多出 commit**：照原樣發佈不建立 commit，`git log origin/main` 的最新 commit 還是合併的那一個。

失敗時以 `workflow_dispatch` 重跑；原因在程式時另開 change 修正。

照原樣發佈只推 tag，所以版號 commit 與 atomic push 要到第一次升版才會實際執行。第一次升版之後也確認：`main` 多一個 `chore: 版本號更新為 <版號>` 的 commit，author 與 committer 都是 `github-actions[bot]`，只改 `Sources/LKAICore/LKAIKitInfo.swift` 的版號那一行；新的 tag 指向它；`git show <tag>:Sources/LKAICore/LKAIKitInfo.swift` 中的版號等於 tag；Release 已建立。
