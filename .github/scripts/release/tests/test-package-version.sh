#!/usr/bin/env bash
# test-package-version.sh：package-version.sh 的測試。
# 由 run-tests.sh 載入，不單獨執行。
#
# package-version.sh get <file> 與 set <file> <version> 以同一個規則找 LKAIKitInfo.swift 裡
# public static let version: String = "<版號>" 這一行：剛好一行才算找到，否則失敗。
# 這個任務沒有直接對應的 spec 情境或範例表（「Release plan」的「Read the version at HEAD」由
# release.sh 的測試涵蓋），所以不加 spectra-scenario 標記。
#
# 測試以本 repo 真正的 Sources/LKAICore/LKAIKitInfo.swift 的複本進行：宣告的寫法改變時，
# 複本的準備就會失敗，提醒要一起修改 package-version.sh 與這些測試。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

PACKAGE_VERSION_SCRIPT="$RELEASE_DIR/package-version.sh"

# 複本裡宣告的版號固定成這個值：真正的檔案之後會被發版流程升版，測試的預期不能跟著變
BASELINE_VERSION="0.1.0"
DECLARATION_PREFIX='public static let version: String = '

# prepare_version_files：準備兩份檔案，都放在 $TEST_TMP 底下各自的資料夾
#   BASELINE_FILE      真正的 LKAIKitInfo.swift，只把宣告的版號固定成 BASELINE_VERSION，之後不再修改
#   VERSION_FILE       和 BASELINE_FILE 相同的複本，交給 package-version.sh 讀寫
#   DECLARATION_LINE   BASELINE_FILE 裡宣告那一行的完整內容
# 兩份檔案各自一個資料夾，之後才能確認 set 沒有在複本旁邊留下暫存檔。
prepare_version_files() {
  local source_file="$REPO_ROOT/Sources/LKAICore/LKAIKitInfo.swift"
  BASELINE_FILE="$TEST_TMP/baseline/LKAIKitInfo.swift"
  VERSION_FILE="$TEST_TMP/version-files/LKAIKitInfo.swift"
  mkdir -p "$TEST_TMP/baseline" "$TEST_TMP/version-files"

  sed 's/\('"$DECLARATION_PREFIX"'\)"[^"]*"/\1"'"$BASELINE_VERSION"'"/' "$source_file" >"$BASELINE_FILE" ||
    fail "無法讀取 $source_file"
  assert_equals "1" "$(grep -c -F "$DECLARATION_PREFIX\"$BASELINE_VERSION\"" "$BASELINE_FILE")" \
    "找不到剛好一行 $DECLARATION_PREFIX\"…\"：LKAIKitInfo.swift 宣告的寫法改了，package-version.sh 與這個測試要一起修改"
  DECLARATION_LINE="$(grep -F "$DECLARATION_PREFIX\"$BASELINE_VERSION\"" "$BASELINE_FILE")"
  cp "$BASELINE_FILE" "$VERSION_FILE" || fail "無法建立複本"
}

# remember_current_content：把 VERSION_FILE 目前的內容當成「不該被改動的內容」。
# 測試先把複本改成宣告不存在、出現兩次等情況，再呼叫它，之後 assert_version_file_unchanged
# 比對的就是這個改過的內容。
remember_current_content() {
  cp "$VERSION_FILE" "$BASELINE_FILE" || fail "無法記下 $VERSION_FILE 的內容"
}

# assert_version_file_unchanged：VERSION_FILE 逐 byte 等於 BASELINE_FILE，而且資料夾裡沒有多出其他檔案
assert_version_file_unchanged() {
  if ! cmp -s "$BASELINE_FILE" "$VERSION_FILE"; then
    fail "檔案被修改了：$VERSION_FILE" "預期（cat -v）：$(show_file "$BASELINE_FILE")" "實際（cat -v）：$(show_file "$VERSION_FILE")"
  fi
  assert_equals "LKAIKitInfo.swift" "$(ls -1 "$TEST_TMP/version-files")" "資料夾內不該有其他檔案（暫存檔要清掉）"
}

# assert_failed_cleanly <說明>：最近一次 run_script 以 1 結束，stdout 為空、stderr 有訊息
assert_failed_cleanly() {
  assert_exit_code 1 "$1 的退出碼"
  assert_file_empty "$TEST_STDOUT" "$1：失敗時 stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "$1：失敗時 stderr 要有訊息"
}

test_package_version_get_prints_the_declared_version() {
  prepare_version_files

  run_script "$PACKAGE_VERSION_SCRIPT" get "$VERSION_FILE"

  assert_exit_code 0
  assert_file_equals "$TEST_STDOUT" '0.1.0\n'
  assert_version_file_unchanged
}

test_package_version_set_changes_only_the_declaration_line() {
  prepare_version_files

  run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE" 0.1.1
  assert_exit_code 0 "set 0.1.1 的退出碼"

  # 和原檔的 diff：只有一行被刪、一行被加，內容分別是舊、新的宣告
  run_cmd diff "$BASELINE_FILE" "$VERSION_FILE"
  assert_exit_code 1 "diff 的退出碼（1 表示有差異）"
  assert_equals "1" "$(grep -c '^< ' "$TEST_STDOUT")" "被刪掉的行數"
  assert_equals "1" "$(grep -c '^> ' "$TEST_STDOUT")" "被加上的行數"
  assert_file_contains "$TEST_STDOUT" "< $DECLARATION_LINE" "被刪掉的是舊的宣告"
  assert_file_contains "$TEST_STDOUT" "> ${DECLARATION_LINE/$BASELINE_VERSION/0.1.1}" "被加上的是新的宣告"
  assert_equals "LKAIKitInfo.swift" "$(ls -1 "$TEST_TMP/version-files")" "資料夾內不該有其他檔案（暫存檔要清掉）"

  run_script "$PACKAGE_VERSION_SCRIPT" get "$VERSION_FILE"
  assert_exit_code 0 "set 之後 get 的退出碼"
  assert_file_equals "$TEST_STDOUT" '0.1.1\n'
}

test_package_version_get_fails_when_the_declaration_is_missing() {
  prepare_version_files
  grep -v -F "$DECLARATION_PREFIX" "$BASELINE_FILE" >"$VERSION_FILE"
  remember_current_content

  run_script "$PACKAGE_VERSION_SCRIPT" get "$VERSION_FILE"

  assert_failed_cleanly "宣告不存在時 get"
  assert_version_file_unchanged
}

test_package_version_set_fails_when_the_declaration_is_missing() {
  prepare_version_files
  grep -v -F "$DECLARATION_PREFIX" "$BASELINE_FILE" >"$VERSION_FILE"
  remember_current_content

  run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE" 0.1.1

  assert_failed_cleanly "宣告不存在時 set"
  assert_version_file_unchanged
}

test_package_version_get_fails_when_the_declaration_appears_twice() {
  prepare_version_files
  printf '%s\n' "$DECLARATION_LINE" >>"$VERSION_FILE"
  remember_current_content

  run_script "$PACKAGE_VERSION_SCRIPT" get "$VERSION_FILE"

  assert_failed_cleanly "宣告出現兩次時 get"
  assert_version_file_unchanged
}

test_package_version_set_fails_when_the_declaration_appears_twice() {
  prepare_version_files
  printf '%s\n' "$DECLARATION_LINE" >>"$VERSION_FILE"
  remember_current_content

  run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE" 0.1.1

  assert_failed_cleanly "宣告出現兩次時 set"
  assert_version_file_unchanged
}

test_package_version_set_rejects_a_version_with_a_v_prefix() {
  prepare_version_files

  run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE" v0.1.1

  assert_failed_cleanly "set v0.1.1"
  assert_version_file_unchanged
}

# 其他不合格式的版號：少一段、多一段、前導的 0、空字串、前後的空白或 LF，以及 sed 的替換文字裡有特殊意義的
# & 與 /（用 sed 把值代入、又沒有先檢查格式的寫法會被它們弄壞）
test_package_version_set_rejects_other_malformed_versions() {
  prepare_version_files
  local malformed_version count=0
  for malformed_version in "0.1" "0.1.1.1" "01.1.1" "0.01.1" "" "0.1.1 " " 0.1.1" $'0.1.1\n' "0.1.1&" "0.1.1/x" "x.y.z" "-1.0.0"; do
    count=$((count + 1))
    run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE" "$malformed_version"
    assert_failed_cleanly "set 第 $count 個不合格式的版號（$malformed_version）"
    assert_version_file_unchanged
  done
}

# get 讀到的值不合格式時也失敗（定位規則找到剛好一行之後，還要檢查值的格式）：
# 複本的宣告值換成 v0.1.0、少一段、多一段、前導的 0、空字串
test_package_version_get_rejects_a_malformed_declared_value() {
  prepare_version_files
  local malformed_value count=0
  for malformed_value in "v0.1.0" "0.1" "0.1.0.1" "01.1.0" ""; do
    count=$((count + 1))
    sed 's/\('"$DECLARATION_PREFIX"'\)"[^"]*"/\1"'"$malformed_value"'"/' "$BASELINE_FILE" >"$VERSION_FILE"
    remember_current_content
    assert_equals "1" "$(grep -c -F "$DECLARATION_PREFIX\"$malformed_value\"" "$VERSION_FILE")" \
      "第 $count 個複本的準備：宣告的值要換成「$malformed_value」"

    run_script "$PACKAGE_VERSION_SCRIPT" get "$VERSION_FILE"

    assert_failed_cleanly "get 讀到不合格式的值（第 $count 個：$malformed_value）"
    assert_version_file_unchanged
  done
}

# 引數不對、檔案不存在：失敗，stdout 為空、stderr 有訊息（退出碼只要求不是 0）
test_package_version_rejects_wrong_usage() {
  prepare_version_files

  run_script "$PACKAGE_VERSION_SCRIPT"
  assert_exit_code_nonzero "沒有任何引數"
  assert_file_empty "$TEST_STDOUT" "沒有任何引數：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "沒有任何引數：stderr 要有訊息"

  run_script "$PACKAGE_VERSION_SCRIPT" get
  assert_exit_code_nonzero "get 沒有檔案"
  assert_file_empty "$TEST_STDOUT" "get 沒有檔案：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "get 沒有檔案：stderr 要有訊息"

  run_script "$PACKAGE_VERSION_SCRIPT" get "$TEST_TMP/does-not-exist.swift"
  assert_exit_code_nonzero "get 的檔案不存在"
  assert_file_empty "$TEST_STDOUT" "get 的檔案不存在：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "get 的檔案不存在：stderr 要有訊息"

  run_script "$PACKAGE_VERSION_SCRIPT" set "$VERSION_FILE"
  assert_exit_code_nonzero "set 沒有版號"
  assert_file_empty "$TEST_STDOUT" "set 沒有版號：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "set 沒有版號：stderr 要有訊息"
  assert_version_file_unchanged

  run_script "$PACKAGE_VERSION_SCRIPT" set "$TEST_TMP/does-not-exist.swift" 0.1.1
  assert_exit_code_nonzero "set 的檔案不存在"
  assert_file_empty "$TEST_STDOUT" "set 的檔案不存在：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "set 的檔案不存在：stderr 要有訊息"
  assert_equals "no" "$([ -e "$TEST_TMP/does-not-exist.swift" ] && echo yes || echo no)" "set 不該建立不存在的檔案"

  run_script "$PACKAGE_VERSION_SCRIPT" bogus "$VERSION_FILE"
  assert_exit_code_nonzero "不認得的子指令"
  assert_file_empty "$TEST_STDOUT" "不認得的子指令：stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "不認得的子指令：stderr 要有訊息"
  assert_version_file_unchanged
}
