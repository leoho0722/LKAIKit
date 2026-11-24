#!/usr/bin/env bash
# test-next-version.sh：next-version.sh 的測試（release-automation「Next version computation」）。
# 由 run-tests.sh 載入，不單獨執行；範例表「next versions」的 11 列各有一個測試函式。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

NEXT_VERSION_SCRIPT="$RELEASE_DIR/next-version.sh"

# assert_next_version <版號> <等級> <預期的新版號>：stdout 正好是新版號加 LF，退出碼 0
assert_next_version() {
  run_script "$NEXT_VERSION_SCRIPT" "$1" "$2"
  assert_exit_code 0 "next-version.sh $1 $2 的退出碼"
  assert_file_equals "$TEST_STDOUT" "$3\n"
}

# assert_next_version_rejected <版號> <等級>：被拒絕，stdout 為空、stderr 有訊息、退出碼不是 0
assert_next_version_rejected() {
  run_script "$NEXT_VERSION_SCRIPT" "$1" "$2"
  assert_exit_code_nonzero "next-version.sh $1 $2 應該被拒絕"
  assert_file_empty "$TEST_STDOUT" "被拒絕時 stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "被拒絕時 stderr 要有訊息"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_0_1_0_major() {
  assert_next_version "0.1.0" "major" "0.2.0"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_0_1_3_major() {
  assert_next_version "0.1.3" "major" "0.2.0"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_0_1_0_minor() {
  assert_next_version "0.1.0" "minor" "0.1.1"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_0_1_0_patch() {
  assert_next_version "0.1.0" "patch" "0.1.1"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_0_9_9_major() {
  assert_next_version "0.9.9" "major" "0.10.0"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_1_2_3_major() {
  assert_next_version "1.2.3" "major" "2.0.0"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_1_2_3_minor() {
  assert_next_version "1.2.3" "minor" "1.3.0"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_1_2_3_patch() {
  assert_next_version "1.2.3" "patch" "1.2.4"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_rejects_v1_2_3_patch() {
  assert_next_version_rejected "v1.2.3" "patch"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_rejects_1_02_3_patch() {
  assert_next_version_rejected "1.02.3" "patch"
}

# spectra-scenario: release-automation / Compute the next version
# spectra-scenario: release-automation / Compute the next version / next versions
test_next_version_rejects_1_2_3_huge() {
  assert_next_version_rejected "1.2.3" "huge"
}
