#!/usr/bin/env bash
# next-version.sh <version> <level>
#
# 依目前的版號與升級等級，算出新版號。
#
# - <version> 要符合 MAJOR.MINOR.PATCH 的格式：三段非負整數，除了 0 本身，每一段都不可以有前導的 0，
#   也不加 v 前綴。
# - <level> 只能是 major、minor 或 patch。
# - MAJOR 至少是 1 時照一般的 SemVer：major 升 MAJOR 並把 MINOR、PATCH 歸 0，minor 升 MINOR 並把
#   PATCH 歸 0，patch 升 PATCH。
# - MAJOR 是 0 時：major 升 MINOR 並把 PATCH 歸 0，minor 與 patch 都升 PATCH，所以升版的計算
#   永遠不會到 1.0.0；要發 1.0.0 時由人在 PR 中把版號改成 1.0.0。
# - 成功時 stdout 是新版號加 LF，退出碼 0。引數數量不對、版號或等級不合法時，stdout 為空、
#   stderr 有訊息、退出碼 1。
# - 訊息以正體中文寫到 stderr：GITHUB_ACTIONS 是 true 時以 ::error:: 開頭成為 annotation，
#   其他情況以 Error: （冒號後有一個空格）開頭。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# 一段數字最多幾位：超過時 $((...)) 可能溢位，寧可拒絕也不印出錯的版號
max_digits=18

# printable <值>：把 LF 與 CR 換成可見的 <LF>、<CR> 再印出，免得訊息裡帶進去的值多出一行，
# 被當成另一條 workflow command
printable() {
  local value="$1" lf=$'\n' cr=$'\r'
  value="${value//$cr/<CR>}"
  value="${value//$lf/<LF>}"
  printf '%s' "$value"
}

# fail <訊息>：把訊息寫到 stderr 並以 1 結束，stdout 不印任何東西
fail() {
  local prefix="Error: "
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    prefix="::error::"
  fi
  printf '%s%s\n' "$prefix" "$1" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  fail "用法：next-version.sh <版號> <等級>，等級是 major、minor 或 patch；收到 $# 個引數"
fi

version="$1"
level="$2"

if ! [[ "$version" =~ $version_pattern ]]; then
  fail "版號不符合 MAJOR.MINOR.PATCH 的格式：$(printable "$version")"
fi

# 要在其他指令之前取出：BASH_REMATCH 會被後面的 [[ =~ ]] 蓋掉
major_text="${BASH_REMATCH[1]}"
minor_text="${BASH_REMATCH[2]}"
patch_text="${BASH_REMATCH[3]}"

case "$level" in
  major | minor | patch) ;;
  *) fail "等級只能是 major、minor 或 patch：$(printable "$level")" ;;
esac

for part in "$major_text" "$minor_text" "$patch_text"; do
  if [ "${#part}" -gt "$max_digits" ]; then
    fail "版號的數字超過 $max_digits 位，無法計算：$(printable "$version")"
  fi
done

# 10# 讓 bash 一律當成十進位；格式已經擋掉前導的 0，這裡是第二道保險
major=$((10#$major_text))
minor=$((10#$minor_text))
patch=$((10#$patch_text))

if [ "$major" -ge 1 ]; then
  case "$level" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
  esac
else
  case "$level" in
    major)
      minor=$((minor + 1))
      patch=0
      ;;
    minor | patch)
      patch=$((patch + 1))
      ;;
  esac
fi

printf '%s.%s.%s\n' "$major" "$minor" "$patch"
