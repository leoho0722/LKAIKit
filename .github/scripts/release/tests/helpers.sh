#!/usr/bin/env bash
# helpers.sh：發版 script 的測試共用的函式，由 run-tests.sh 在每個測試的 subshell 內載入，不單獨執行。
#
# - 斷言失敗時，fail 把說明印到 stderr 並以 1 結束目前的 subshell：run-tests.sh 以這個退出碼判斷
#   測試失敗，說明會連同測試的其他輸出，一起在失敗時印出。所以斷言要直接寫在測試函式裡，
#   不要放在 $(...) 或管線中（那樣只會結束那一層的 subshell）。
# - 測試函式最後一個指令的退出碼就是測試的結果，結尾不要留會失敗的指令（例如結果為 false 的 [ ]）。
# - 這裡的函式不以 test_ 開頭，才不會被 run-tests.sh 當成測試。
# - 不印出任何環境變數的值。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# .github/scripts/release：受測的 script 所在的資料夾
RELEASE_DIR="$(cd "$TESTS_DIR/.." && pwd)"
# 本 repo 的根目錄：暫存 git repo 以這裡真正的 LKAIKitInfo.swift 建立
REPO_ROOT="$(cd "$RELEASE_DIR/../../.." && pwd)"
FAKES_DIR="$TESTS_DIR/fakes"

# 測試用的 git 身分：只用於建立測試的 commit，不用 GIT_AUTHOR_* 等環境變數，
# 免得蓋過受測的 script 自己指定的身分
TEST_GIT_NAME="Test User"
TEST_GIT_EMAIL="test@example.invalid"

# ---------------------------------------------------------------------------
# 斷言
# ---------------------------------------------------------------------------

# fail <說明> [<補充的行>...]：把斷言失敗的說明與補充的行印到 stderr，並以 1 結束目前的 subshell
fail() {
  local line
  printf '斷言失敗：%s\n' "$1" >&2
  shift
  for line in "$@"; do
    printf '  %s\n' "$line" >&2
  done
  exit 1
}

# assert_equals <預期> <實際> [<說明>]
assert_equals() {
  if [ "$1" != "$2" ]; then
    fail "${3:-兩個值不相等}" "預期：$1" "實際：$2"
  fi
}

# assert_contains <內容> <片段> [<說明>]：內容含有片段
assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "${3:-內容不含指定的片段}" "片段：$2" "內容：$1" ;;
  esac
}

# assert_not_contains <內容> <片段> [<說明>]：內容不含片段
assert_not_contains() {
  case "$1" in
    *"$2"*) fail "${3:-內容含有不該出現的片段}" "片段：$2" "內容：$1" ;;
  esac
}

# assert_exit_code <預期的退出碼> [<說明>]：和最近一次 run_cmd 的退出碼（RC）比對
assert_exit_code() {
  assert_equals "$1" "$RC" "${2:-退出碼不符}"
}

# assert_exit_code_nonzero [<說明>]：最近一次 run_cmd 的退出碼不是 0
assert_exit_code_nonzero() {
  if [ "$RC" -eq 0 ]; then
    fail "${1:-退出碼應該不是 0}" "實際：$RC"
  fi
}

# show_file <檔案>：把檔案的前 2000 個 byte 轉成可見的字元（cat -v），失敗時附在說明後面
show_file() {
  if [ -f "$1" ]; then
    head -c 2000 "$1" | cat -v
  else
    printf '（檔案不存在）'
  fi
}

# assert_file_equals <檔案> <預期的內容>：逐 byte 比對。預期的內容以 printf 的 %b 解讀，
# 所以可以寫 '0.2.0\n'、'a\r\n'
assert_file_equals() {
  local expected_file="$TEST_TMP/expected-content"
  printf '%b' "$2" >"$expected_file"
  if ! cmp -s "$1" "$expected_file"; then
    fail "檔案的內容不符：$1" "預期（cat -v）：$(show_file "$expected_file")" "實際（cat -v）：$(show_file "$1")"
  fi
}

# assert_file_empty <檔案> [<說明>]：檔案存在而且沒有內容
assert_file_empty() {
  if [ ! -f "$1" ] || [ -s "$1" ]; then
    fail "${2:-檔案應該是空的}：$1" "實際（cat -v）：$(show_file "$1")"
  fi
}

# assert_file_not_empty <檔案> [<說明>]：檔案存在而且有內容
assert_file_not_empty() {
  if [ ! -s "$1" ]; then
    fail "${2:-檔案應該有內容}：$1"
  fi
}

# assert_file_contains <檔案> <片段> [<說明>]：檔案含有片段（原樣比對，不是正規表示式）
assert_file_contains() {
  if ! grep -F -q -- "$2" "$1" 2>/dev/null; then
    fail "${3:-檔案不含指定的片段}：$1" "片段：$2" "內容（cat -v）：$(show_file "$1")"
  fi
}

# assert_file_not_contains <檔案> <片段> [<說明>]：檔案不含片段（檔案不存在也算不含）
assert_file_not_contains() {
  if grep -F -q -- "$2" "$1" 2>/dev/null; then
    fail "${3:-檔案含有不該出現的片段}：$1" "片段：$2" "內容（cat -v）：$(show_file "$1")"
  fi
}

# ---------------------------------------------------------------------------
# 執行受測的指令
# ---------------------------------------------------------------------------

# run_cmd <指令> [<引數>...]：執行指令，stdout 與 stderr 各收進檔案，不印出來。
# 結果放在 TEST_STDOUT、TEST_STDERR（檔案路徑）與 RC（退出碼）。
run_cmd() {
  mkdir -p "$TEST_TMP/out"
  TEST_STDOUT="$TEST_TMP/out/stdout"
  TEST_STDERR="$TEST_TMP/out/stderr"
  RC=0
  "$@" >"$TEST_STDOUT" 2>"$TEST_STDERR" || RC=$?
}

# run_script <script> [<引數>...]：以執行這些測試的 bash 執行 script，結果同 run_cmd
run_script() {
  local script="$1"
  shift
  run_cmd "$BASH" "$script" "$@"
}

# ---------------------------------------------------------------------------
# 假的指令
# ---------------------------------------------------------------------------

# use_fakes：建立這個測試專用的 FAKE_LOG_DIR（假的 lkai、gh、swift 把引數、prompt 與 Release 紀錄
# 寫在那裡）。fakes 資料夾本來就由 run-tests.sh 放在每個測試的 PATH 最前面，這裡只在它不在的時候補上。
use_fakes() {
  FAKE_LOG_DIR="$TEST_TMP/fake-log"
  mkdir -p "$FAKE_LOG_DIR/releases"
  export FAKE_LOG_DIR
  case ":$PATH:" in
    ":$FAKES_DIR:"*) ;;
    *)
      PATH="$FAKES_DIR:$PATH"
      export PATH
      ;;
  esac
}

# write_release_record <tag>：在 FAKE_LOG_DIR 寫下這個 tag 的 Release 紀錄，
# 假的 gh release list 會列出它
write_release_record() {
  [ -n "${FAKE_LOG_DIR:-}" ] || fail "FAKE_LOG_DIR 沒有設定，請先呼叫 use_fakes"
  mkdir -p "$FAKE_LOG_DIR/releases/$1" || fail "無法建立 Release 紀錄：$1"
  printf '%s\n' "$1" >"$FAKE_LOG_DIR/releases/$1/title"
  : >"$FAKE_LOG_DIR/releases/$1/notes"
}

# ---------------------------------------------------------------------------
# 暫存的 git repo
# ---------------------------------------------------------------------------

# repo_git <git 的引數>...：在暫存 repo（TEST_REPO）內以測試用的身分執行 git
repo_git() {
  git -C "$TEST_REPO" -c user.name="$TEST_GIT_NAME" -c user.email="$TEST_GIT_EMAIL" "$@"
}

# make_test_repo：建立暫存的 git repo 與作為 origin 的 bare repo。
#   TEST_REPO   = $TEST_TMP/work，第一個 commit 只有本 repo 真正的 Sources/LKAICore/LKAIKitInfo.swift
#   TEST_REMOTE = $TEST_TMP/origin.git，已推上 main
# 分支一律是 main。結束時目前的資料夾是 TEST_REPO（release.sh 在 repo 的根目錄執行）。
make_test_repo() {
  TEST_REPO="$TEST_TMP/work"
  TEST_REMOTE="$TEST_TMP/origin.git"
  local source_file="Sources/LKAICore/LKAIKitInfo.swift"

  git -c init.defaultBranch=main init -q --bare "$TEST_REMOTE" || fail "無法建立 bare repo"
  git -C "$TEST_REMOTE" symbolic-ref HEAD refs/heads/main || fail "無法設定 bare repo 的 HEAD"
  git -c init.defaultBranch=main init -q "$TEST_REPO" || fail "無法建立暫存 repo"
  git -C "$TEST_REPO" symbolic-ref HEAD refs/heads/main || fail "無法設定暫存 repo 的 HEAD"

  mkdir -p "$TEST_REPO/$(dirname "$source_file")"
  cp "$REPO_ROOT/$source_file" "$TEST_REPO/$source_file" || fail "找不到 $REPO_ROOT/$source_file"
  repo_git add -- "$source_file" || fail "git add 失敗"
  repo_git commit -q -m "chore: 建立測試用的 repo" || fail "第一個 commit 失敗"
  repo_git remote add origin "$TEST_REMOTE" || fail "無法加入 origin"
  repo_git push -q origin main || fail "無法把 main 推上 origin"
  cd "$TEST_REPO" || fail "無法進入暫存 repo"
}

# commit_change <訊息> <路徑>：在暫存 repo 內把一行文字附加到 <路徑>（不存在就建立，包含上層資料夾），
# 再以測試用的身分 commit。不推到 origin；需要時呼叫 push_main。
commit_change() {
  mkdir -p "$TEST_REPO/$(dirname "$2")"
  printf '%s\n' "$1" >>"$TEST_REPO/$2"
  repo_git add -- "$2" || fail "git add 失敗：$2"
  repo_git commit -q -m "$1" || fail "git commit 失敗：$1"
}

# push_main：把暫存 repo 的 main 推到 origin
push_main() {
  repo_git push -q origin main || fail "無法把 main 推上 origin"
}

# make_version_tag <版本> [with-release|no-release]：在暫存 repo 的 HEAD 建立 tag <版本> 並推到 origin。
# 預設（with-release）同時在 FAKE_LOG_DIR 寫下這個 tag 的 Release 紀錄，需要先呼叫 use_fakes；
# 第二個引數是 no-release 時不寫（測試補建 Release 的情境）。
make_version_tag() {
  local release_mode="${2:-with-release}"
  case "$release_mode" in
    with-release | no-release) ;;
    *) fail "make_version_tag 的第二個引數只能是 with-release 或 no-release：$release_mode" ;;
  esac
  repo_git tag "$1" || fail "無法建立 tag：$1"
  repo_git push -q origin "$1" || fail "無法推送 tag：$1"
  if [ "$release_mode" = "with-release" ]; then
    write_release_record "$1"
  fi
}
