#!/usr/bin/env bash
# run-tests.sh：執行同一個資料夾內 test-*.sh 的每個 test_ 開頭的函式。
#
# - 每個函式在自己的 subshell 與暫存資料夾中執行，互不影響。
# - 執行前設定 GIT_CONFIG_GLOBAL=/dev/null 與 GIT_CONFIG_NOSYSTEM=1，測試不受本機的 git 設定影響。
# - 每個測試開始前，清掉 GitHub Actions 的變數、GH_*、LKAI_RELEASE_* 與 LKAI_*_API_KEY，
#   由測試自己設定需要的值，這樣在 GitHub Actions 內外的結果相同。
# - 每個測試的輸出（stdout 與 stderr）都收進檔案，失敗時才印出，而且每一行前面加兩個空格，
#   不讓任何一行以 :: 開頭而成為 job log 的 workflow command。
# - 每個測試的 PATH 最前面都是 fakes 資料夾（假的 lkai、gh、swift）：忘了呼叫 use_fakes 的測試
#   也不會碰到真的指令；假指令在沒有 FAKE_LOG_DIR 時一律失敗，不會送出請求或改動 GitHub。
# - 全部通過時以 0 結束；有任何失敗，或找不到任何測試時，以 1 結束。
#
# 用法：bash .github/scripts/release/tests/run-tests.sh
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法，不用 bash 4 才有的功能。

# shellcheck source-path=SCRIPTDIR
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TESTS_DIR

# 受測的 script 與 fakes 都以 #!/usr/bin/env bash 開頭：把執行這個 runner 的 bash 所在的資料夾放到
# PATH 最前面，它們才會用和 runner 同一個 bash（以 /bin/bash 3.2 執行時，也用 3.2 測 script）。
case "$BASH" in
  /*)
    PATH="$(dirname "$BASH"):$PATH"
    export PATH
    ;;
esac

# 不受本機與系統的 git 設定影響
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

results_dir="$(mktemp -d "${TMPDIR:-/tmp}/lkai-release-tests.XXXXXX")" || {
  echo "無法建立暫存資料夾" >&2
  exit 1
}
trap 'rm -rf "$results_dir"' EXIT

# 清掉會影響測試結果的環境變數。LKAI_RELEASE_* 與 LKAI_*_API_KEY 以樣式比對 env 列出的名稱，
# 不逐一列出，新增供應商時這裡不必修改。
clear_test_environment() {
  local name
  unset GITHUB_ACTIONS GITHUB_STEP_SUMMARY GH_REPO GH_TOKEN
  for name in $(env | sed -n \
    -e 's/^\(LKAI_RELEASE_[A-Za-z0-9_]*\)=.*$/\1/p' \
    -e 's/^\(LKAI_[A-Za-z0-9_]*_API_KEY\)=.*$/\1/p'); do
    unset "$name"
  done
}

# 載入 helpers.sh 與一個測試檔：兩者都定義函式，要在呼叫端的 subshell 內執行，不留在 runner 裡
load_test_file() {
  # shellcheck source=helpers.sh
  . "$TESTS_DIR/helpers.sh" || return 1
  # shellcheck source=/dev/null
  . "$1" || return 1
}

# 列出一個測試檔載入後所有的函式名稱，一行一個（包含 helpers.sh 的函式，呼叫端再篩 test_ 開頭的）。
# 在 command substitution 的 subshell 內呼叫，載入的內容不會留在 runner 裡。
list_test_functions() {
  load_test_file "$1" || return 1
  compgen -A function
}

# 在自己的 subshell 與暫存資料夾中執行一個測試函式，stdout 與 stderr 收進檔案。
# 測試通過與否取決於 subshell 的退出碼：斷言失敗時 helpers.sh 的 fail 會以 1 結束。
run_one_test() {
  local test_file="$1" name="$2" output_file="$3"
  (
    TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lkai-release-test.XXXXXX")" || exit 1
    # TMPDIR 以 / 結尾時路徑會有 //，換成 cd 後的 pwd，測試比對路徑時才不會因為多一個 / 而不同
    TEST_TMP="$(cd "$TEST_TMP" && pwd)" || exit 1
    export TEST_TMP
    trap 'rm -rf "$TEST_TMP"' EXIT
    cd "$TEST_TMP" || exit 1
    clear_test_environment
    PATH="$TESTS_DIR/fakes:$PATH"
    export PATH
    load_test_file "$test_file" || exit 1
    "$name"
  ) >"$output_file" 2>&1
}

# 印出檔案內容，每一行前面加兩個空格；沒有內容時什麼都不印。
# 以 LC_ALL=C 執行 sed，任何 byte 都原樣輸出：測試的輸出可能有被截斷的多位元組字元（例如 show_file 只取前
# 2000 bytes），UTF-8 語系下的 sed 會把它當成錯誤（illegal byte sequence）並丟掉那一行
print_indented() {
  [ -s "$1" ] || return 0
  LC_ALL=C sed 's/^/  /' "$1"
}

total=0
passed=0
failed=0

for test_file in "$TESTS_DIR"/test-*.sh; do
  [ -f "$test_file" ] || continue

  # 載入檔案、列出函式都在 subshell 內進行，檔案的內容不會留在這個 runner 裡
  load_error_file="$results_dir/load-error.txt"
  if ! all_functions="$(list_test_functions "$test_file" 2>"$load_error_file")"; then
    total=$((total + 1))
    failed=$((failed + 1))
    echo "FAIL $(basename "$test_file")（無法載入）"
    print_indented "$load_error_file"
    continue
  fi

  function_names="$(printf '%s\n' "$all_functions" | grep '^test_' | sort)"
  for name in $function_names; do
    total=$((total + 1))
    output_file="$results_dir/output.txt"
    if run_one_test "$test_file" "$name" "$output_file"; then
      passed=$((passed + 1))
      echo "PASS $name"
    else
      failed=$((failed + 1))
      echo "FAIL $name"
      print_indented "$output_file"
    fi
  done
done

if [ "$total" -eq 0 ]; then
  echo "找不到任何測試：$TESTS_DIR 內沒有 test-*.sh，或裡面沒有 test_ 開頭的函式" >&2
  exit 1
fi

echo "共 $total 個測試，通過 $passed 個，失敗 $failed 個"
[ "$failed" -eq 0 ]
