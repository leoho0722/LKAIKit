#!/usr/bin/env bash
# test-script-style.sh：發版 script、假指令、測試與 workflow 的寫法檢查。
# 由 run-tests.sh 載入，不單獨執行。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

# 變數名稱後面緊接著中文或全形標點時，要把變數寫成 ${名稱}。
#
# 原因：macOS 的 bash 3.2 在 UTF-8 語系（GitHub 的 macOS runner 預設就是）下，會把變數名稱後面緊接著的
# 非 ASCII 位元組當成變數名稱的一部分。例如 v=abc 時，"$v，後" 展開成「另一個沒有設定的變數」加上殘缺的位元組，
# abc 不見了，輸出也變成亂碼；寫成 "${v}，後" 才正確。語系是 C 時看不出來，bash 4 以上也不會，
# 所以本機與 CI 的結果可能不同，只能以寫法的規則檢查。
#
# 掃描的檔案：.github/scripts/release/ 底下所有的 script（*.sh 與 tests/fakes/ 的檔案，不含 prompts/*.md），
# 以及 .github/workflows/*.yml 與 action.yml。之後新增的 workflow 也會被掃到。
#
# 規則（以 LC_ALL=C 掃描，一個字元一個 byte）：一行裡出現「$ 加上變數名稱，後面緊接著一個不是可見 ASCII、
# 空格或 Tab 的 byte」就違規；第一個非空白字元是 # 的行（註解）不算。$1、$#、${名稱}、$(…) 都不受影響。
test_scripts_brace_variable_names_before_non_ascii_text() {
  local pattern=$'\\$[A-Za-z_][A-Za-z0-9_]*[^ -~\t]'
  local violations="$TEST_TMP/style-violations.txt"
  local scanned_files="$TEST_TMP/style-scanned-files.txt"
  local file relative
  : >"$violations"
  : >"$scanned_files"

  for file in \
    "$RELEASE_DIR"/*.sh \
    "$RELEASE_DIR"/tests/*.sh \
    "$RELEASE_DIR"/tests/fakes/* \
    "$REPO_ROOT"/.github/workflows/*.yml \
    "$REPO_ROOT/action.yml"; do
    if [ ! -f "$file" ]; then
      continue
    fi
    relative="${file#"$REPO_ROOT"/}"
    printf '%s\n' "$relative" >>"$scanned_files"
    LC_ALL=C grep -nE "$pattern" "$file" |
      LC_ALL=C grep -vE '^[0-9]+:[[:space:]]*#' |
      awk -v name="$relative" '{ print name ":" $0 }' >>"$violations"
  done

  # 掃描的範圍沒有寫錯：幾個一定要在裡面的檔案
  assert_file_contains "$scanned_files" ".github/scripts/release/release.sh" "要掃描 release.sh"
  assert_file_contains "$scanned_files" ".github/scripts/release/tests/fakes/gh" "要掃描 tests/fakes 的檔案"
  assert_file_contains "$scanned_files" ".github/workflows/ci.yml" "要掃描 workflow"
  assert_file_contains "$scanned_files" "action.yml" "要掃描 action.yml"

  if [ -s "$violations" ]; then
    fail "變數名稱後面緊接著中文或全形標點，要寫成 \${名稱}（檔案:行號:內容）" "$(cat "$violations")"
  fi
}
