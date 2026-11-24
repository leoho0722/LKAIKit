#!/usr/bin/env bash
# release.sh：合併到 main 之後的自動發版流程。不收引數，在 git repo 的根目錄執行。
# 退出碼 0 表示已發佈、沒有可發佈的變更或 dry run 完成，1 表示失敗。
#
# 目前實作流程的第 1 到 5 步（任務 1.4）：
#   1. 選擇模式，解析供應商與模型。
#   2. 讀取 HEAD 的版號，列出版本 tag，版號不合格式或有更大的 tag 時失敗。
#   3. 目前版號的 tag 存在時：沒有新的 commit，或 tag 之後只有 docs/spectra/ 的變更，就沒有可發佈的變更；
#      否則是升版。tag 不存在時照原樣發佈。（「檢查 Release」之後的任務才加。）
#   4. 升版時請 AI 判斷升級等級，由 next-version.sh 算出新版號。
#   5. 請 AI 撰寫 Release Notes。
# 第 5 步之後暫時印出報告與 Release Notes，以 1 結束；之後的任務取代這一段。
#
# 環境變數：
#   LKAI_RELEASE_DRY_RUN                 沒有設定、空字串或 true：dry run；false：正式發版，只在 GitHub Actions 中允許
#   LKAI_RELEASE_PROVIDER、LKAI_RELEASE_MODEL                本次的供應商與模型
#   LKAI_RELEASE_DEFAULT_PROVIDER、LKAI_RELEASE_DEFAULT_MODEL  repository 的預設值
#   GITHUB_ACTIONS                       true 時訊息以 ::error:: 開頭
#   API 金鑰（LKAI_*_API_KEY）由 lkai 自己讀取，這個 script 不讀、不印、不放進引數。
#
# 報告（write_report）向 stdout 印出下列各行，每行「名稱：值」，不知道的行不印：
#   模式、供應商、模型、計畫、升級等級、上一版、新版號、失敗的步驟
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
version_file="Sources/LKAICore/LKAIKitInfo.swift"
# 去掉 AI 回答前後的字元：空格、Tab、CR、LF
answer_whitespace=$' \t\r\n'
# 被拒絕的回答最多印出幾個 bytes
answer_preview_bytes=200

# 寫法的提醒：變數後面緊接著中文或全形標點時一定要寫成 ${名稱}。macOS 的 bash 3.2 會把非 ASCII 的位元組
# 當成變數名稱的一部分，$provider，模型 會被當成另一個（沒有設定的）變數，訊息就缺了值而且變成亂碼。

# 狀態：報告與失敗時的訊息會用到。current_step 在每一步開始前設定，失敗時就是失敗的步驟
mode=""
provider=""
model=""
plan=""
bump_level=""
previous_version=""
next_version=""
current_step=""
failed_step=""

# 暫存資料夾：放 prompt、lkai 的 stdout 與讀出的版號檔；結束時刪除
work_dir=""

# 清掉暫存資料夾。寫成函式，之後的 EXIT trap 可以和別的收尾一起呼叫
# shellcheck disable=SC2329  # 由下面的 trap 呼叫
cleanup() {
  if [ -n "$work_dir" ]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# ---------------------------------------------------------------------------
# 訊息與報告
# ---------------------------------------------------------------------------

# printable <值>：把 LF 與 CR 換成可見的 <LF>、<CR> 再印出，免得訊息裡帶進去的值多出一行，
# 被當成另一條 workflow command
printable() {
  local value="$1" lf=$'\n' cr=$'\r'
  value="${value//$cr/<CR>}"
  value="${value//$lf/<LF>}"
  printf '%s' "$value"
}

# error_line <訊息>：把一行錯誤訊息寫到 stderr。GITHUB_ACTIONS 是 true 時以 ::error:: 開頭成為 annotation，
# 其他情況以 Error: （冒號後有一個空格）開頭
error_line() {
  local prefix="Error: "
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    prefix="::error::"
  fi
  printf '%s%s\n' "$prefix" "$1" >&2
}

# print_ai_text <文字>：印出 AI 的文字（被拒絕的回答、Release Notes）。AI 的文字一律經過這個函式寫出，
# 之後的任務在這裡加上 GitHub Actions 的保護
print_ai_text() {
  printf '%s\n' "$1"
}

# write_report：向 stdout 印出報告，每行「名稱：值」，不知道的行不印
write_report() {
  printf '模式：%s\n' "$mode"
  if [ -n "$provider" ]; then
    printf '供應商：%s\n' "$provider"
  fi
  if [ -n "$model" ]; then
    printf '模型：%s\n' "$model"
  fi
  if [ -n "$plan" ]; then
    printf '計畫：%s\n' "$plan"
  fi
  if [ -n "$bump_level" ]; then
    printf '升級等級：%s\n' "$bump_level"
  fi
  # 沒有可發佈的變更時，上一版與新版號都沒有值，不印
  if [ "$plan" = "release-as-is" ] || [ "$plan" = "version-bump" ]; then
    if [ -n "$previous_version" ]; then
      printf '上一版：%s\n' "$previous_version"
    else
      printf '上一版：（無）\n'
    fi
  fi
  if [ -n "$next_version" ]; then
    printf '新版號：%s\n' "$next_version"
  fi
  if [ -n "$failed_step" ]; then
    printf '失敗的步驟：%s\n' "$failed_step"
  fi
  return 0
}

# fail_before_mode <訊息>：模式還沒選定時失敗：只寫錯誤訊息，沒有報告（spec 規定選定模式之後才有報告）
fail_before_mode() {
  error_line "$1"
  exit 1
}

# fail <訊息>：失敗：錯誤訊息寫到 stderr，報告（含失敗的步驟）印到 stdout，以 1 結束
fail() {
  error_line "$1"
  failed_step="$current_step"
  write_report
  exit 1
}

# fail_with_ai_text <訊息> <AI 的文字>：同 fail，但先把 AI 的文字寫在錯誤訊息後面。
# 錯誤訊息那一行不含 AI 的文字
fail_with_ai_text() {
  error_line "$1"
  print_ai_text "$2" >&2
  failed_step="$current_step"
  write_report
  exit 1
}

# ---------------------------------------------------------------------------
# 版號的比較
# ---------------------------------------------------------------------------

# version_greater <版號 a> <版號 b>：a 比 b 大（逐段以整數比較）。兩個版號都要符合版號格式
version_greater() {
  local a_major a_minor a_patch b_major b_minor b_patch
  IFS=. read -r a_major a_minor a_patch <<<"$1"
  IFS=. read -r b_major b_minor b_patch <<<"$2"
  if [ "$((10#$a_major))" -ne "$((10#$b_major))" ]; then
    [ "$((10#$a_major))" -gt "$((10#$b_major))" ]
    return
  fi
  if [ "$((10#$a_minor))" -ne "$((10#$b_minor))" ]; then
    [ "$((10#$a_minor))" -gt "$((10#$b_minor))" ]
    return
  fi
  [ "$((10#$a_patch))" -gt "$((10#$b_patch))" ]
}

# ---------------------------------------------------------------------------
# 呼叫 lkai
# ---------------------------------------------------------------------------

# ask_lkai <prompt 檔> <輸出檔> [<額外的 lkai 選項>...]：以選定的供應商與模型送出一個請求，
# stdout 寫到輸出檔。lkai 的 stderr 直接流到這個 script 的 stderr。不加 --stream 與 --apiKey，
# API 金鑰由 lkai 從環境變數讀。lkai 以非 0 結束時回傳 1。
ask_lkai() {
  local prompt_file="$1" output_file="$2"
  shift 2
  lkai --provider "$provider" --model "$model" --prompt-file "$prompt_file" --timeout 180 "$@" >"$output_file"
}

# ---------------------------------------------------------------------------
# 第 1 步：選擇模式，解析供應商與模型
# ---------------------------------------------------------------------------

# 模式依 LKAI_RELEASE_DRY_RUN 決定，在讀版號與送出任何 AI 請求之前
dry_run_value="${LKAI_RELEASE_DRY_RUN-}"
case "$dry_run_value" in
  "" | true)
    mode="dry-run"
    ;;
  false)
    if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
      fail_before_mode "LKAI_RELEASE_DRY_RUN 是 false 時要正式發版，但正式發版只能在 GitHub Actions 中執行"
    fi
    mode="release"
    ;;
  *)
    fail_before_mode "LKAI_RELEASE_DRY_RUN 的值不認得：$(printable "$dry_run_value")；只能是 true、false，或沒有設定、空字串"
    ;;
esac

current_step="解析供應商與模型"

# 供應商：本次的值 → repository 的預設值 → anthropic
provider="${LKAI_RELEASE_PROVIDER:-}"
if [ -z "$provider" ]; then
  provider="${LKAI_RELEASE_DEFAULT_PROVIDER:-}"
fi
if [ -z "$provider" ]; then
  provider="anthropic"
fi

# 模型：本次指定了供應商時，只看本次的模型；否則本次的模型 → repository 的預設模型 →
# 兩個預設值都沒有設定時用 claude-opus-5-5。供應商與模型的值都原樣交給 lkai，這裡不檢查。
if [ -n "${LKAI_RELEASE_PROVIDER:-}" ]; then
  model="${LKAI_RELEASE_MODEL:-}"
else
  model="${LKAI_RELEASE_MODEL:-}"
  if [ -z "$model" ]; then
    model="${LKAI_RELEASE_DEFAULT_MODEL:-}"
  fi
  if [ -z "$model" ] && [ -z "${LKAI_RELEASE_DEFAULT_PROVIDER:-}" ]; then
    model="claude-opus-5-5"
  fi
fi
if [ -z "$model" ]; then
  fail "沒有可用的模型：請設定 LKAI_RELEASE_MODEL 或 LKAI_RELEASE_DEFAULT_MODEL"
fi

# ---------------------------------------------------------------------------
# 第 2 步：讀取版號
# ---------------------------------------------------------------------------

current_step="讀取版號"

work_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lkai-release.XXXXXX")" ||
  fail "無法建立暫存資料夾"

# 目前的版號是 HEAD 的檔案內容，不是工作目錄的；讀法和 package-version.sh 修改它時用同一個規則
git show "HEAD:$version_file" >"$work_dir/LKAIKitInfo.swift" ||
  fail "無法讀取 HEAD 的 $version_file"
current_version="$("$BASH" "$script_dir/package-version.sh" get "$work_dir/LKAIKitInfo.swift")" ||
  fail "讀不到 HEAD 的版號（${version_file}）"

# 版本 tag：名稱符合版號格式的 tag。有比目前版號更大的就失敗，訊息寫出最高的那一個
highest_tag=""
for tag in $(git tag --list); do
  if ! [[ "$tag" =~ $version_pattern ]]; then
    continue
  fi
  if [ -z "$highest_tag" ] || version_greater "$tag" "$highest_tag"; then
    highest_tag="$tag"
  fi
done
if [ -n "$highest_tag" ] && version_greater "$highest_tag" "$current_version"; then
  fail "有比目前的版號 ${current_version} 更大的版本 tag：${highest_tag}（最高的 tag）"
fi

# ---------------------------------------------------------------------------
# 第 3 步：選擇計畫
# ---------------------------------------------------------------------------

current_tag_commit="$(git rev-parse --verify --quiet "refs/tags/$current_version^{commit}")" || current_tag_commit=""
if [ -n "$current_tag_commit" ]; then
  # 目前版號的 tag 已存在：沒有新的 commit，或 tag 之後只有 docs/spectra/ 的變更時，沒有可發佈的變更
  commits_after_tag="$(git rev-list --count "$current_tag_commit..HEAD")" ||
    fail "無法比較 tag $current_version 與 HEAD"
  changed_files="$(git diff --name-only "$current_tag_commit" HEAD -- . ':(exclude)docs/spectra')" ||
    fail "無法比較 tag $current_version 與 HEAD 的檔案"
  if [ "$commits_after_tag" = "0" ] || [ -z "$changed_files" ]; then
    plan="nothing-to-release"
    write_report
    echo "沒有可發佈的變更。"
    exit 0
  fi
  plan="version-bump"
  previous_version="$current_version"
else
  # 目前版號還沒有 tag：照原樣發佈。上一版是 HEAD 的祖先中最高的版本 tag，沒有就是沒有上一版
  plan="release-as-is"
  next_version="$current_version"
  for tag in $(git tag --list); do
    if ! [[ "$tag" =~ $version_pattern ]]; then
      continue
    fi
    if ! git merge-base --is-ancestor "refs/tags/$tag" HEAD; then
      continue
    fi
    if [ -z "$previous_version" ] || version_greater "$tag" "$previous_version"; then
      previous_version="$tag"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 第 4 步：判斷升級等級（只有升版）
# ---------------------------------------------------------------------------

if [ "$plan" = "version-bump" ]; then
  current_step="判斷升級等級"

  "$BASH" "$script_dir/make-prompt.sh" bump-level "$previous_version" HEAD >"$work_dir/bump-level.md" ||
    fail "無法產生升級等級的 prompt"
  ask_lkai "$work_dir/bump-level.md" "$work_dir/bump-level.out" ||
    fail "lkai 的升級等級請求失敗（供應商 ${provider}，模型 ${model}）"

  # 回答是 lkai 的 stdout 去掉前後的空格、Tab、CR、LF，剛好是 major、minor、patch 才接受
  answer="$(cat "$work_dir/bump-level.out")"
  answer="${answer#"${answer%%[!"$answer_whitespace"]*}"}"
  answer="${answer%"${answer##*[!"$answer_whitespace"]}"}"
  case "$answer" in
    major | minor | patch)
      bump_level="$answer"
      ;;
    *)
      # 被拒絕的回答只印前 200 bytes：截在字元中間時，iconv -c 去掉不完整的字元；
      # 結尾不完整時 iconv 的退出碼是 1，還會在 stderr 印一行訊息，所以要吞掉
      answer_preview="$(printf '%s' "$answer" | head -c "$answer_preview_bytes" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true)"
      fail_with_ai_text "AI 回答的升級等級不是 major、minor 或 patch，回答的前 $answer_preview_bytes bytes 如下：" "$answer_preview"
      ;;
  esac

  next_version="$("$BASH" "$script_dir/next-version.sh" "$current_version" "$bump_level")" ||
    fail "無法由 $current_version 與 $bump_level 計算新版號"
fi

# ---------------------------------------------------------------------------
# 第 5 步：撰寫 Release Notes
# ---------------------------------------------------------------------------

current_step="撰寫 Release Notes"

"$BASH" "$script_dir/make-prompt.sh" release-notes "$previous_version" HEAD "$next_version" >"$work_dir/release-notes.md" ||
  fail "無法產生 Release Notes 的 prompt"
ask_lkai "$work_dir/release-notes.md" "$work_dir/release-notes.out" --max-output-tokens 8192 ||
  fail "lkai 的 Release Notes 請求失敗（供應商 ${provider}，模型 ${model}）"

release_notes="$(cat "$work_dir/release-notes.out")"
case "$release_notes" in
  *[![:space:]]*) ;;
  *) fail "Release Notes 是空的：lkai 的回答只有空白" ;;
esac

# ---------------------------------------------------------------------------
# 暫時的結尾（任務 1.5、1.6 取代）：印出報告與 Release Notes，以 1 結束
# ---------------------------------------------------------------------------

write_report
echo "Release Notes："
print_ai_text "$release_notes"
error_line "發版流程第 6 步之後還沒有實作，暫時印出報告與 Release Notes 就結束"
exit 1
