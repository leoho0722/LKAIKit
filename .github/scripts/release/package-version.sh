#!/usr/bin/env bash
# package-version.sh get <file>
# package-version.sh set <file> <version>
#
# 讀寫 LKAIKitInfo.swift 裡 public static let version: String = "<版號>" 宣告的版號。
#
# - get <file>：印出宣告的版號加 LF，退出碼 0。
# - set <file> <version>：把宣告的值換成 <version>，寫到同一個資料夾的暫存檔再 mv，檔案的權限不變。
# - get 與 set 以同一個規則定位宣告：整行只有（前後可以有空白）
#   public static let version: String = "<任何值>"，而且整個檔案剛好一行才算找到。
#   所以 /// 註解裡提到這個寫法的文字不會被當成宣告。
# - 版號要符合 MAJOR.MINOR.PATCH：三段非負整數，除了 0 本身，每一段都不可以有前導的 0。
#   get 找到之後，檢查值的格式；set 在做任何事之前，先檢查 <version> 的格式，
#   通過之後才會放進替換，所以替換文字裡不會有 sed 有特殊意義的字元。
# - 找不到剛好一行、版號不合格式、檔案不存在、引數不對時：不修改檔案、不留下暫存檔，
#   stdout 為空、stderr 有訊息、退出碼 1。
# - 訊息以正體中文寫到 stderr：GITHUB_ACTIONS 是 true 時以 ::error:: 開頭成為 annotation，
#   其他情況以 Error: （冒號後有一個空格）開頭。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法（寫到暫存檔再 mv，不用原地修改檔案的 sed 選項）。

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# 宣告那一行的樣式：grep -E 與 sed 都能用（只用 [ ]、*、^、$ 與字元類別）
declaration_pattern='^[[:space:]]*public static let version: String = "[^"]*"[[:space:]]*$'

# set 建立的暫存檔；任何結束的路徑都要刪掉它
temp_file=""
cleanup() {
  if [ -n "$temp_file" ]; then
    rm -f "$temp_file"
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

# fail <訊息>：把訊息寫到 stderr 並以 1 結束（EXIT 的 trap 會刪掉暫存檔），stdout 不印任何東西
fail() {
  local prefix="Error: "
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    prefix="::error::"
  fi
  printf '%s%s\n' "$prefix" "$1" >&2
  exit 1
}

usage() {
  fail "用法：package-version.sh get <檔案>，或 package-version.sh set <檔案> <版號>"
}

# locate_declaration <檔案>：get 與 set 共用的定位規則。檔案裡剛好有一行宣告時，
# 把宣告的值放進 declared_version；否則失敗。
declared_version=""
locate_declaration() {
  local file="$1" count
  if [ ! -f "$file" ]; then
    fail "找不到檔案：$(printable "$file")"
  fi
  if [ ! -r "$file" ]; then
    fail "讀不到檔案：$(printable "$file")"
  fi
  count="$(grep -c -E -- "$declaration_pattern" "$file")"
  if [ "$count" != "1" ]; then
    fail "在 $(printable "$file") 找到 $count 行版號的宣告，必須剛好一行（public static let version: String = \"…\"）"
  fi
  declared_version="$(sed -n 's/^[[:space:]]*public static let version: String = "\([^"]*\)"[[:space:]]*$/\1/p' "$file")"
}

# check_version_format <版號> <說明>：版號不符合 MAJOR.MINOR.PATCH 的格式時失敗
check_version_format() {
  if ! [[ "$1" =~ $version_pattern ]]; then
    fail "$2不符合 MAJOR.MINOR.PATCH 的格式：$(printable "$1")"
  fi
}

command_get() {
  if [ "$#" -ne 1 ]; then
    usage
  fi
  locate_declaration "$1"
  check_version_format "$declared_version" "宣告的版號"
  printf '%s\n' "$declared_version"
}

command_set() {
  if [ "$#" -ne 2 ]; then
    usage
  fi
  local file="$1" version="$2" directory base
  check_version_format "$version" "要設定的版號"
  locate_declaration "$file"

  # 暫存檔放在同一個資料夾，mv 才是同一個檔案系統內的取代；先複製原檔的權限，再寫入內容
  directory="$(dirname "$file")"
  base="$(basename "$file")"
  temp_file="$(mktemp "$directory/.$base.XXXXXX")" || fail "無法在 $(printable "$directory") 建立暫存檔"
  cp -p "$file" "$temp_file" || fail "無法準備暫存檔"
  # 原檔是唯讀時，暫存檔也跟著唯讀、寫不進去；mv 取代檔案只需要資料夾可寫，所以讓暫存檔可以寫入
  chmod u+w "$temp_file" || fail "無法準備暫存檔"
  # $version 已經通過格式檢查，只有數字與句點，放進替換是安全的
  sed 's/^\([[:space:]]*public static let version: String = \)"[^"]*"\([[:space:]]*\)$/\1"'"$version"'"\2/' "$file" >"$temp_file" ||
    fail "無法寫入暫存檔"

  # 取代之前，確認暫存檔裡剛好一行宣告，而且值是要設定的版號
  locate_declaration "$temp_file"
  if [ "$declared_version" != "$version" ]; then
    fail "替換的結果不符：預期 ${version}，實際 $(printable "$declared_version")"
  fi

  mv "$temp_file" "$file" || fail "無法取代 $(printable "$file")"
  temp_file=""
}

subcommand="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi
case "$subcommand" in
  get) command_get "$@" ;;
  set) command_set "$@" ;;
  *) usage ;;
esac
