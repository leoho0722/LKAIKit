#!/usr/bin/env bash
# make-prompt.sh <bump-level|release-notes> <previous-version> <target-ref> [<version>]
#
# 組出送給 lkai 的完整 prompt，印到 stdout：
#
#   範本 + 版號行 + 變更資料
#
# - 範本是 prompts/<種類>.md（以這個 script 所在的資料夾定位），原樣印在最前面，不做任何字串代入，
#   所以輸出的第一行就是範本的標記。
# - <previous-version> 是空字串表示沒有上一版：範圍從空的 tree 開始，包含第一個 commit。
#   不是空字串時要符合 MAJOR.MINOR.PATCH 的格式，範圍從 refs/tags/<previous-version> 開始
#   （寫成 refs/tags/ 免得和同名的分支混淆）。bump-level 一定要有上一版。
# - <target-ref> 是範圍的終點，要能解析成 commit：一般是 HEAD，補建 Release 時是被補建的 tag。
# - <version> 是要發佈的版號，只用於 release-notes（必填、格式同上）；bump-level 不收，
#   因為新版號是由 AI 的回答算出來的，prompt 不能先帶。
# - 版號行：
#     bump-level     上一版：<previous-version>
#     release-notes  要發佈的版號：<version>，再接「上一版：<previous-version>」或第一次發版的說明
# - 變更資料是三個區塊，每個標記各自獨立一行：
#     <commits>  範圍內非 merge commit 的標題（git log --no-merges --format=%s），一行一個
#     <stat>     整個範圍的 git diff --stat=200（不限路徑；寬度 200 才不會把長路徑截成 .../ 開頭）
#     <diff>     Sources、Package.swift、Package.resolved、action.yml 的 git diff
#   diff 超過 LKAI_RELEASE_DIFF_LIMIT（預設 200000）bytes 時，<diff> 內不放 diff，改放一句說明；
#   剛好等於上限時放進去。
# - 所有檢查與 git 指令都在印出任何東西之前完成：失敗時 stdout 為空、stderr 有訊息、退出碼 1。
# - 訊息以正體中文寫到 stderr：GITHUB_ACTIONS 是 true 時以 ::error:: 開頭成為 annotation，
#   其他情況以 Error: （冒號後有一個空格）開頭。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
default_diff_limit=200000
# 上限最多幾位：超過時 [ -gt ] 的比較可能溢位
max_limit_digits=18

# 沒有上一版時，release-notes prompt 裡固定的說明（測試用同一個字串）
first_release_statement='這是 LKAIKit 的第一次發版，沒有上一版。'

# 暫存資料夾：放三個區塊的內容，任何結束的路徑都要刪掉它
work_dir=""
cleanup() {
  if [ -n "$work_dir" ]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# printable <值>：把 LF 與 CR 換成可見的 <LF>、<CR> 再印出，免得訊息裡帶進去的值多出一行，
# 被當成另一條 workflow command
printable() {
  local value="$1" lf=$'\n' cr=$'\r'
  value="${value//$cr/<CR>}"
  value="${value//$lf/<LF>}"
  printf '%s' "$value"
}

# fail <訊息>：把訊息寫到 stderr 並以 1 結束（EXIT 的 trap 會刪掉暫存資料夾），stdout 不印任何東西
fail() {
  local prefix="Error: "
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    prefix="::error::"
  fi
  printf '%s%s\n' "$prefix" "$1" >&2
  exit 1
}

usage() {
  fail "用法：make-prompt.sh <bump-level|release-notes> <上一版> <target-ref> [<版號>]；上一版可以是空字串，版號只用於 release-notes"
}

# ---------------------------------------------------------------------------
# 檢查引數
# ---------------------------------------------------------------------------

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  usage
fi

kind="$1"
previous_version="$2"
target_ref="$3"
version=""
if [ "$#" -eq 4 ]; then
  version="$4"
fi

case "$kind" in
  bump-level)
    if [ "$#" -ne 3 ]; then
      fail "bump-level 不收要發佈的版號：新版號由 AI 的回答算出來，prompt 不能先帶"
    fi
    if [ -z "$previous_version" ]; then
      fail "bump-level 一定要有上一版"
    fi
    ;;
  release-notes)
    if [ "$#" -ne 4 ]; then
      fail "release-notes 一定要有要發佈的版號"
    fi
    if ! [[ "$version" =~ $version_pattern ]]; then
      fail "要發佈的版號不符合 MAJOR.MINOR.PATCH 的格式：$(printable "$version")"
    fi
    ;;
  *)
    fail "不認得的種類：$(printable "$kind")，只能是 bump-level 或 release-notes"
    ;;
esac

if [ -n "$previous_version" ] && ! [[ "$previous_version" =~ $version_pattern ]]; then
  fail "上一版不符合 MAJOR.MINOR.PATCH 的格式：$(printable "$previous_version")"
fi

diff_limit="${LKAI_RELEASE_DIFF_LIMIT:-$default_diff_limit}"
if ! [[ "$diff_limit" =~ ^[1-9][0-9]*$ ]] || [ "${#diff_limit}" -gt "$max_limit_digits" ]; then
  fail "LKAI_RELEASE_DIFF_LIMIT 要是不超過 $max_limit_digits 位的正整數：$(printable "$diff_limit")"
fi

template="$script_dir/prompts/$kind.md"
if [ ! -r "$template" ]; then
  fail "讀不到範本：$(printable "$template")"
fi

# ---------------------------------------------------------------------------
# 範圍：起點與終點都先換成 commit（或 tree）的 hash，之後的 git 指令不會被名稱的寫法影響
# ---------------------------------------------------------------------------

if [ -z "$target_ref" ]; then
  fail "target-ref 不能是空字串"
fi
case "$target_ref" in
  -*) fail "target-ref 不能以 - 開頭：$(printable "$target_ref")" ;;
esac
target_commit="$(git rev-parse --verify --quiet "$target_ref^{commit}")" ||
  fail "target-ref 解析不了成 commit：$(printable "$target_ref")"

if [ -n "$previous_version" ]; then
  start="$(git rev-parse --verify --quiet "refs/tags/$previous_version^{commit}")" ||
    fail "找不到上一版的 tag：$(printable "$previous_version")"
  log_range="$start..$target_commit"
else
  start="$(git hash-object -t tree /dev/null)" || fail "無法取得空的 tree"
  log_range="$target_commit"
fi

# ---------------------------------------------------------------------------
# 變更資料：先全部算好寫進暫存檔，確認每個 git 指令都成功，才開始印
# ---------------------------------------------------------------------------

work_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lkai-make-prompt.XXXXXX")" || fail "無法建立暫存資料夾"

git log --no-merges --format=%s "$log_range" -- >"$work_dir/commits.txt" ||
  fail "無法取得 commit 的標題（範圍 $(printable "$log_range")）"
git diff --no-color --no-ext-diff --stat=200 "$start" "$target_commit" -- >"$work_dir/stat.txt" ||
  fail "無法取得變更統計"
git diff --no-color --no-ext-diff "$start" "$target_commit" -- Sources Package.swift Package.resolved action.yml >"$work_dir/diff.txt" ||
  fail "無法取得程式碼的 diff"

# wc -c 在 BSD 上輸出的數字前面有空白，tr 去掉
diff_size="$(wc -c <"$work_dir/diff.txt" | tr -d ' ')"

# ---------------------------------------------------------------------------
# 印出
# ---------------------------------------------------------------------------

cat "$template"
# 範本的結尾沒有 LF 時補一個，下一段才不會接在範本的最後一行後面
if [ -n "$(tail -c 1 "$template")" ]; then
  printf '\n'
fi
printf '\n'

if [ "$kind" = "release-notes" ]; then
  printf '要發佈的版號：%s\n' "$version"
  if [ -n "$previous_version" ]; then
    printf '上一版：%s\n' "$previous_version"
  else
    printf '%s\n' "$first_release_statement"
  fi
else
  printf '上一版：%s\n' "$previous_version"
fi
printf '\n'

printf '<commits>\n'
cat "$work_dir/commits.txt"
printf '</commits>\n'

printf '<stat>\n'
cat "$work_dir/stat.txt"
printf '</stat>\n'

printf '<diff>\n'
if [ "$diff_size" -gt "$diff_limit" ]; then
  printf '程式碼的 diff 有 %s bytes，超過 %s bytes 的上限，因大小而省略。\n' "$diff_size" "$diff_limit"
else
  cat "$work_dir/diff.txt"
fi
printf '</diff>\n'
