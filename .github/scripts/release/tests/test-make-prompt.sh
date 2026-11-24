#!/usr/bin/env bash
# test-make-prompt.sh：make-prompt.sh 的測試（release-automation「Change data in prompts」，以及
# 「AI bump level answer」「Release notes generation」中對 prompt 的要求）。
# 由 run-tests.sh 載入，不單獨執行。
#
# make-prompt.sh <bump-level|release-notes> <previous-version> <target-ref> [<version>]
#
# 測試的前提（都是 design 的 Implementation Contract 中 make-prompt.sh 那一列的規則）：
# - 範本原樣輸出在最前面，所以輸出的第一行就是範本的標記；範本是 prompts/<種類>.md，
#   這裡直接比對 design 規定的標記字串。
# - bump-level 接「上一版：<previous-version>」，不帶新版號；release-notes 接「要發佈的版號：<version>」，
#   以及「上一版：<previous-version>」或固定的第一次發版說明。
# - 變更資料是 <commits>、<stat>、<diff> 三個區塊，每個標記各自獨立一行：
#   <commits> 是範圍內非 merge commit 的標題（git log --no-merges --format=%s），
#   <stat> 是整個範圍的 git diff --stat=200（不限路徑；寬度 200 才不會把長路徑截斷），
#   <diff> 是 git diff -- Sources Package.swift Package.resolved action.yml。
#   git diff 都加 --no-color --no-ext-diff（測試與 script 用同一個指令）。
#   diff 超過 LKAI_RELEASE_DIFF_LIMIT（預設 200000）bytes 時，<diff> 內不放 diff，改放一句說明。
# - 範圍的起點是 refs/tags/<previous-version>；沒有上一版（空字串）時是空的 tree，包含第一個 commit。
# - 失敗時 stdout 為空、stderr 有訊息、退出碼 1。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

MAKE_PROMPT_SCRIPT="$RELEASE_DIR/make-prompt.sh"

BUMP_MARKER='<!-- lkai-release-prompt: bump-level -->'
NOTES_MARKER='<!-- lkai-release-prompt: release-notes -->'
# 沒有上一版時 release-notes prompt 裡固定的說明，之後的實作要用同一個字串
FIRST_RELEASE_STATEMENT='這是 LKAIKit 的第一次發版，沒有上一版。'
# diff 因為太大而省略時，prompt 裡說明的句子一定含有這幾個字
OMITTED_KEYWORD='因大小而省略'

SOURCES_PATH="Sources/LKAICore/LKAIKitInfo.swift"
TESTS_PATH="Tests/LKAICoreTests/LKAIKitInfoTests.swift"

# ---------------------------------------------------------------------------
# 情境與工具
# ---------------------------------------------------------------------------

# setup_bump_repo：升版的情境。tag 0.1.0（在第一個 commit）之後兩個 commit，
# 一個改 Sources/LKAICore/LKAIKitInfo.swift，一個只改 Tests/LKAICoreTests/LKAIKitInfoTests.swift。
# git 的輸出一律用 C 語系，變更統計的文字（例如 files changed）才不會因為執行的機器而不同。
setup_bump_repo() {
  export LC_ALL=C
  make_test_repo
  make_version_tag 0.1.0 no-release
  commit_change "feat: 新增版號的說明" "$SOURCES_PATH"
  commit_change "test: 補上版號的測試" "$TESTS_PATH"
}

# setup_first_release_repo：第一次發版的情境。沒有任何 tag，第一個 commit 之後再三個 commit。
setup_first_release_repo() {
  export LC_ALL=C
  make_test_repo
  commit_change "feat: 第一個功能" "Sources/LKAICore/FirstFeature.swift"
  commit_change "fix: 修正一個問題" "Sources/LKAICore/FirstFix.swift"
  commit_change "docs: 更新說明" "docs/readme.md"
}

# empty_tree：空的 tree 的名稱（git hash-object -t tree /dev/null）
empty_tree() {
  git -C "$TEST_REPO" hash-object -t tree /dev/null
}

# run_make_prompt <引數>...：在暫存 repo 內執行 make-prompt.sh，結果同 run_cmd
run_make_prompt() {
  run_script "$MAKE_PROMPT_SCRIPT" "$@"
}

# assert_prompt_succeeded：最近一次執行以 0 結束、stderr 為空、stdout 有內容
assert_prompt_succeeded() {
  assert_exit_code 0 "make-prompt.sh 的退出碼"
  assert_file_empty "$TEST_STDERR" "成功時 stderr 要是空的"
  assert_file_not_empty "$TEST_STDOUT" "成功時 stdout 是完整的 prompt"
}

# block_of <檔案> <名稱>：印出 <名稱> 那一行與 </名稱> 那一行之間的內容（不含這兩行）。
# 找不到這兩行時什麼都不印。
block_of() {
  awk -v tag="$2" '
    $0 == "<" tag ">" { inside = 1; next }
    $0 == "</" tag ">" { inside = 0; next }
    inside { print }
  ' "$1"
}

# assert_has_data_blocks：stdout 裡 <commits>、<stat>、<diff> 的開頭與結尾各自獨立一行，各出現一次
assert_has_data_blocks() {
  local tag
  for tag in commits stat diff; do
    assert_equals "1" "$(grep -c -x -F "<$tag>" "$TEST_STDOUT")" "<$tag> 那一行出現的次數"
    assert_equals "1" "$(grep -c -x -F "</$tag>" "$TEST_STDOUT")" "</$tag> 那一行出現的次數"
  done
}

# assert_files_equal <預期的檔案> <實際的檔案> <說明>：兩個檔案逐 byte 相同
assert_files_equal() {
  if ! cmp -s "$1" "$2"; then
    fail "$3" "預期（cat -v）：$(show_file "$1")" "實際（cat -v）：$(show_file "$2")"
  fi
}

# assert_make_prompt_fails <說明> <引數>...：以這些引數執行 make-prompt.sh，要失敗：
# 退出碼 1、stdout 為空、stderr 有訊息
assert_make_prompt_fails() {
  local description="$1"
  shift
  run_make_prompt "$@"
  assert_exit_code 1 "$description 的退出碼"
  assert_file_empty "$TEST_STDOUT" "${description}：失敗時 stdout 要是空的"
  assert_file_not_empty "$TEST_STDERR" "${description}：失敗時 stderr 要有訊息"
}

# assert_bump_change_data：升版情境（setup_bump_repo）的變更資料：兩個 commit 的標題與變更統計，
# 有 Sources/ 的 diff、沒有 Tests/ 的 diff；tag 之前的 commit 標題不出現
assert_bump_change_data() {
  local commits_block stat_block diff_block
  commits_block="$(block_of "$TEST_STDOUT" commits)"
  stat_block="$(block_of "$TEST_STDOUT" stat)"
  diff_block="$(block_of "$TEST_STDOUT" diff)"

  assert_has_data_blocks
  assert_contains "$commits_block" "feat: 新增版號的說明" "<commits> 要有改 Sources/ 的 commit 的標題"
  assert_contains "$commits_block" "test: 補上版號的測試" "<commits> 要有只改 Tests/ 的 commit 的標題"
  assert_not_contains "$commits_block" "chore: 建立測試用的 repo" "tag 之前的 commit 標題不該出現"
  assert_contains "$stat_block" "$SOURCES_PATH" "<stat> 要有 Sources/ 的檔名"
  assert_contains "$stat_block" "$TESTS_PATH" "<stat> 不限路徑，要有 Tests/ 的檔名"
  assert_contains "$stat_block" "2 files changed" "<stat> 要有變更統計的總結"
  assert_contains "$diff_block" "diff --git a/$SOURCES_PATH" "<diff> 要有 Sources/ 的 diff"
  assert_not_contains "$diff_block" "diff --git a/$TESTS_PATH" "<diff> 不該有 Tests/ 的 diff"
  assert_file_not_contains "$TEST_STDOUT" "diff --git a/$TESTS_PATH" "整個 prompt 都不該有 Tests/ 的 diff"
}

# ---------------------------------------------------------------------------
# Change data in prompts
# ---------------------------------------------------------------------------

# spectra-scenario: release-automation / Change data for a version bump
test_make_prompt_bump_level_for_a_version_bump_has_the_change_data() {
  setup_bump_repo

  run_make_prompt bump-level 0.1.0 HEAD

  assert_prompt_succeeded
  assert_bump_change_data
}

# spectra-scenario: release-automation / Change data for a version bump
test_make_prompt_release_notes_for_a_version_bump_has_the_change_data() {
  setup_bump_repo

  run_make_prompt release-notes 0.1.0 HEAD 0.1.1

  assert_prompt_succeeded
  assert_bump_change_data
}

# 三個區塊的內容逐行等於 git 本身的輸出（預期值由測試直接執行 git 得到，不呼叫受測的 script）。
# 變更統計用 --stat=200：預設的寬度會把長路徑截成 .../ 開頭，AI 就看不出變更在哪個模組
test_make_prompt_data_blocks_equal_the_git_output_for_a_version_bump() {
  setup_bump_repo
  git -C "$TEST_REPO" log --no-merges --format=%s refs/tags/0.1.0..HEAD >"$TEST_TMP/expected-commits.txt"
  git -C "$TEST_REPO" diff --no-color --no-ext-diff --stat=200 refs/tags/0.1.0 HEAD >"$TEST_TMP/expected-stat.txt"
  git -C "$TEST_REPO" diff --no-color --no-ext-diff refs/tags/0.1.0 HEAD -- Sources Package.swift Package.resolved action.yml >"$TEST_TMP/expected-diff.txt"

  run_make_prompt bump-level 0.1.0 HEAD

  assert_prompt_succeeded
  block_of "$TEST_STDOUT" commits >"$TEST_TMP/actual-commits.txt"
  block_of "$TEST_STDOUT" stat >"$TEST_TMP/actual-stat.txt"
  block_of "$TEST_STDOUT" diff >"$TEST_TMP/actual-diff.txt"
  assert_files_equal "$TEST_TMP/expected-commits.txt" "$TEST_TMP/actual-commits.txt" "<commits> 的內容不等於 git log --no-merges --format=%s"
  assert_files_equal "$TEST_TMP/expected-stat.txt" "$TEST_TMP/actual-stat.txt" "<stat> 的內容不等於 git diff --stat=200"
  assert_files_equal "$TEST_TMP/expected-diff.txt" "$TEST_TMP/actual-diff.txt" "<diff> 的內容不等於 Sources、Package.swift、Package.resolved、action.yml 的 git diff"
}

# spectra-scenario: release-automation / Change data for the first release
test_make_prompt_release_notes_for_the_first_release_omits_a_diff_that_is_too_large() {
  setup_first_release_repo

  LKAI_RELEASE_DIFF_LIMIT=100 run_make_prompt release-notes "" HEAD 0.1.0

  assert_prompt_succeeded
  assert_has_data_blocks
  local commits_block diff_block
  commits_block="$(block_of "$TEST_STDOUT" commits)"
  diff_block="$(block_of "$TEST_STDOUT" diff)"
  assert_contains "$commits_block" "chore: 建立測試用的 repo" "從空的 tree 開始，要有第一個 commit 的標題"
  assert_contains "$commits_block" "feat: 第一個功能"
  assert_contains "$commits_block" "fix: 修正一個問題"
  assert_contains "$commits_block" "docs: 更新說明"
  assert_contains "$diff_block" "$OMITTED_KEYWORD" "<diff> 要說明 diff 因為太大而省略"
  assert_file_not_contains "$TEST_STDOUT" "diff --git" "超過上限時，整段 diff 都不放"
}

# 上限夠大時，從空的 tree 開始的 diff 有放進去（包含第一個 commit 加入的 LKAIKitInfo.swift）
test_make_prompt_release_notes_for_the_first_release_includes_the_diff_within_the_limit() {
  setup_first_release_repo

  run_make_prompt release-notes "" HEAD 0.1.0

  assert_prompt_succeeded
  assert_has_data_blocks
  local diff_block
  diff_block="$(block_of "$TEST_STDOUT" diff)"
  assert_contains "$diff_block" "diff --git a/$SOURCES_PATH" "第一個 commit 加入的檔案也在 diff 裡"
  assert_contains "$diff_block" "diff --git a/Sources/LKAICore/FirstFeature.swift"
  assert_not_contains "$diff_block" "docs/readme.md" "docs/ 的變更不放進 diff"
  assert_file_not_contains "$TEST_STDOUT" "$OMITTED_KEYWORD" "沒有超過上限時不該說省略"
}

# 上限的邊界：diff 剛好等於上限時放進去，多一個 byte 就省略（"at most 200,000 bytes"）。
# diff 的大小由測試直接執行 git 量出來。
test_make_prompt_diff_limit_boundary_is_inclusive() {
  setup_first_release_repo
  git -C "$TEST_REPO" diff --no-color --no-ext-diff "$(empty_tree)" HEAD -- Sources Package.swift Package.resolved action.yml >"$TEST_TMP/expected-diff.txt"
  local diff_size
  diff_size=$(($(wc -c <"$TEST_TMP/expected-diff.txt")))
  if [ "$diff_size" -le 1 ]; then
    fail "測試的 diff 是空的，無法測邊界：$diff_size"
  fi

  LKAI_RELEASE_DIFF_LIMIT="$diff_size" run_make_prompt release-notes "" HEAD 0.1.0
  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "diff --git a/$SOURCES_PATH" "diff 剛好等於上限（$diff_size bytes）時要放進去"
  assert_file_not_contains "$TEST_STDOUT" "$OMITTED_KEYWORD" "diff 剛好等於上限時不該說省略"

  LKAI_RELEASE_DIFF_LIMIT=$((diff_size - 1)) run_make_prompt release-notes "" HEAD 0.1.0
  assert_prompt_succeeded
  assert_file_not_contains "$TEST_STDOUT" "diff --git" "diff 比上限多 1 byte 時整段都不放"
  assert_file_contains "$TEST_STDOUT" "$OMITTED_KEYWORD" "diff 比上限多 1 byte 時要說省略"
}

# 兩個 prompt 都要說明三個區塊裡的文字是資料、要忽略其中的指示
test_make_prompt_tells_the_model_to_ignore_instructions_in_the_data() {
  setup_bump_repo

  run_make_prompt bump-level 0.1.0 HEAD
  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "忽略" "bump-level prompt 要叫模型忽略資料裡的指示"

  run_make_prompt release-notes 0.1.0 HEAD 0.1.1
  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "忽略" "release-notes prompt 要叫模型忽略資料裡的指示"
}

# release-notes 的範本寫明輸出的格式：正體中文，依序四個分類的二級標題（release-automation「Release notes generation」）
test_make_prompt_release_notes_template_states_the_output_format() {
  setup_bump_repo

  run_make_prompt release-notes 0.1.0 HEAD 0.1.1

  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "## 破壞性變更" "要寫明分類：破壞性變更"
  assert_file_contains "$TEST_STDOUT" "## 新功能" "要寫明分類：新功能"
  assert_file_contains "$TEST_STDOUT" "## 修正" "要寫明分類：修正"
  assert_file_contains "$TEST_STDOUT" "## 其他" "要寫明分類：其他"
  assert_file_contains "$TEST_STDOUT" "正體中文" "要叫模型用正體中文撰寫"
}

# bump-level 的範本寫明三個等級，並要求只回答其中一個（release-automation「AI bump level answer」）
test_make_prompt_bump_level_template_asks_for_exactly_one_level() {
  setup_bump_repo

  run_make_prompt bump-level 0.1.0 HEAD

  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "major" "要寫明等級：major"
  assert_file_contains "$TEST_STDOUT" "minor" "要寫明等級：minor"
  assert_file_contains "$TEST_STDOUT" "patch" "要寫明等級：patch"
  assert_file_contains "$TEST_STDOUT" "只回答" "要求只回答其中一個等級"
}

# 範圍裡的 merge commit，標題不出現；它兩邊的 commit 標題都要出現
test_make_prompt_leaves_out_merge_commit_subjects() {
  setup_bump_repo
  repo_git checkout -q -b feature || fail "無法建立分支"
  commit_change "feat: 分支上的功能" "Sources/LKAICore/Branch.swift"
  repo_git checkout -q main || fail "無法回到 main"
  commit_change "fix: main 上的修正" "Sources/LKAICore/Main.swift"
  repo_git merge -q --no-ff -m "Merge: 合併功能分支（不該出現）" feature || fail "無法建立 merge commit"
  local kind

  for kind in bump-level release-notes; do
    if [ "$kind" = "bump-level" ]; then
      run_make_prompt bump-level 0.1.0 HEAD
    else
      run_make_prompt release-notes 0.1.0 HEAD 0.1.1
    fi
    assert_prompt_succeeded
    assert_file_contains "$TEST_STDOUT" "feat: 分支上的功能" "${kind}：分支上的 commit 標題要出現"
    assert_file_contains "$TEST_STDOUT" "fix: main 上的修正" "${kind}：main 上的 commit 標題要出現"
    assert_file_not_contains "$TEST_STDOUT" "Merge: 合併功能分支（不該出現）" "${kind}：merge commit 的標題不該出現"
  done
}

# <target-ref> 是 tag（補建 Release 的情況）時，範圍到那個 tag 為止：tag 之後的 commit 標題、統計、diff 都不出現
test_make_prompt_stops_at_the_target_tag() {
  setup_bump_repo
  make_version_tag 0.1.1 no-release
  commit_change "feat: 0.1.1 之後的變更" "Sources/LKAICore/Later.swift"
  local kind

  for kind in bump-level release-notes; do
    if [ "$kind" = "bump-level" ]; then
      run_make_prompt bump-level 0.1.0 0.1.1
    else
      run_make_prompt release-notes 0.1.0 0.1.1 0.1.1
    fi
    assert_prompt_succeeded
    assert_file_contains "$TEST_STDOUT" "feat: 新增版號的說明" "${kind}：tag 之前的 commit 標題要出現"
    assert_file_contains "$TEST_STDOUT" "test: 補上版號的測試" "${kind}：tag 之前的 commit 標題要出現"
    assert_file_contains "$TEST_STDOUT" "diff --git a/$SOURCES_PATH" "${kind}：到 tag 為止的 diff 要出現"
    assert_file_not_contains "$TEST_STDOUT" "feat: 0.1.1 之後的變更" "${kind}：tag 之後的 commit 標題不該出現"
    assert_file_not_contains "$TEST_STDOUT" "Later.swift" "${kind}：tag 之後的檔案不該出現在統計或 diff"
  done
}

# ---------------------------------------------------------------------------
# Release notes generation / AI bump level answer：對 prompt 的要求
# ---------------------------------------------------------------------------

# spectra-scenario: release-automation / Build the release notes prompt for a version bump
test_make_prompt_release_notes_for_a_version_bump_names_both_versions() {
  setup_bump_repo

  run_make_prompt release-notes 0.1.0 HEAD 0.1.1

  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "要發佈的版號：0.1.1" "要有要發佈的版號"
  assert_file_contains "$TEST_STDOUT" "上一版：0.1.0" "要有上一版"
  assert_file_not_contains "$TEST_STDOUT" "$FIRST_RELEASE_STATEMENT" "有上一版時不該說這是第一次發版"
}

# spectra-scenario: release-automation / Build the release notes prompt for the first release
test_make_prompt_release_notes_for_the_first_release_says_so() {
  setup_first_release_repo

  run_make_prompt release-notes "" HEAD 0.1.0

  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "要發佈的版號：0.1.0" "要有要發佈的版號"
  assert_file_contains "$TEST_STDOUT" "$FIRST_RELEASE_STATEMENT" "要說明這是第一次發版"
  assert_file_not_contains "$TEST_STDOUT" "上一版：" "沒有上一版時不該有「上一版：」那一行"
}

# bump-level prompt：有上一版，沒有要發佈的版號（新版號由 AI 的回答算出來，prompt 不能先帶）
test_make_prompt_bump_level_has_the_previous_version_and_no_next_version() {
  setup_bump_repo

  run_make_prompt bump-level 0.1.0 HEAD

  assert_prompt_succeeded
  assert_file_contains "$TEST_STDOUT" "上一版：0.1.0" "要有上一版"
  assert_file_not_contains "$TEST_STDOUT" "要發佈的版號" "bump-level prompt 不該有要發佈的版號"
  assert_file_not_contains "$TEST_STDOUT" "$FIRST_RELEASE_STATEMENT" "bump-level prompt 不該有第一次發版的說明"
}

# 範本原樣輸出在最前面：輸出的第一行就是範本的標記，也等於範本檔的第一行
test_make_prompt_keeps_the_template_marker_on_the_first_line() {
  setup_bump_repo

  run_make_prompt bump-level 0.1.0 HEAD
  assert_prompt_succeeded
  assert_equals "$BUMP_MARKER" "$(head -n 1 "$TEST_STDOUT")" "bump-level prompt 的第一行"
  assert_equals "$(head -n 1 "$RELEASE_DIR/prompts/bump-level.md")" "$(head -n 1 "$TEST_STDOUT")" "bump-level prompt 的第一行要等於範本檔的第一行"

  run_make_prompt release-notes 0.1.0 HEAD 0.1.1
  assert_prompt_succeeded
  assert_equals "$NOTES_MARKER" "$(head -n 1 "$TEST_STDOUT")" "release-notes prompt 的第一行"
  assert_equals "$(head -n 1 "$RELEASE_DIR/prompts/release-notes.md")" "$(head -n 1 "$TEST_STDOUT")" "release-notes prompt 的第一行要等於範本檔的第一行"

  run_make_prompt release-notes "" HEAD 0.1.0
  assert_prompt_succeeded
  assert_equals "$NOTES_MARKER" "$(head -n 1 "$TEST_STDOUT")" "第一次發版的 release-notes prompt 的第一行"
}

# ---------------------------------------------------------------------------
# 用法錯誤
# ---------------------------------------------------------------------------

# 每一種用法錯誤都以 1 結束，stdout 為空（不能先輸出一半的 prompt），stderr 有訊息
test_make_prompt_rejects_wrong_usage() {
  setup_bump_repo

  assert_make_prompt_fails "沒有任何引數"
  assert_make_prompt_fails "只有種類" bump-level
  assert_make_prompt_fails "不認得的種類" bogus 0.1.0 HEAD
  assert_make_prompt_fails "bump-level 的上一版有 v 前綴" bump-level v0.1.0 HEAD
  assert_make_prompt_fails "release-notes 的上一版少一段" release-notes 0.1 HEAD 0.1.1
  assert_make_prompt_fails "上一版有前導的 0" bump-level 0.01.0 HEAD
  assert_make_prompt_fails "bump-level 沒有上一版" bump-level "" HEAD
  assert_make_prompt_fails "release-notes 沒有版號" release-notes 0.1.0 HEAD
  assert_make_prompt_fails "release-notes 的版號有 v 前綴" release-notes 0.1.0 HEAD v0.1.1
  assert_make_prompt_fails "release-notes 的版號是空字串" release-notes 0.1.0 HEAD ""
  assert_make_prompt_fails "bump-level 多給了版號" bump-level 0.1.0 HEAD 0.1.1
  assert_make_prompt_fails "引數太多" release-notes 0.1.0 HEAD 0.1.1 extra
  assert_make_prompt_fails "target-ref 解析不了" bump-level 0.1.0 no-such-ref
  assert_make_prompt_fails "target-ref 是空字串" bump-level 0.1.0 ""
  assert_make_prompt_fails "上一版的 tag 不存在" bump-level 0.9.9 HEAD
}

# assert_first_line_starts_with <檔案> <前綴> [<說明>]：檔案的第一行以這個前綴開頭。
# 用 case 比對，不用 cut -c：GNU 的 cut -c 以 byte 計算，BSD 的以字元計算，訊息有中文時兩邊的結果不同
assert_first_line_starts_with() {
  local first_line
  first_line="$(head -n 1 "$1")"
  case "$first_line" in
    "$2"*) ;;
    *) fail "${3:-第一行的開頭不符}" "預期以「$2」開頭" "實際（cat -v）：$(printf '%s' "$first_line" | cat -v)" ;;
  esac
}

# 訊息的前綴：GITHUB_ACTIONS 是 true 時以 ::error:: 開頭，其他情況以 Error: （冒號後有一個空格）開頭
test_make_prompt_error_message_prefix() {
  setup_bump_repo

  run_make_prompt bogus 0.1.0 HEAD
  assert_exit_code 1
  assert_first_line_starts_with "$TEST_STDERR" "Error: " "沒有 GITHUB_ACTIONS 時的前綴"

  GITHUB_ACTIONS=true run_make_prompt bogus 0.1.0 HEAD
  assert_exit_code 1
  assert_first_line_starts_with "$TEST_STDERR" "::error::" "GITHUB_ACTIONS 是 true 時的前綴"

  GITHUB_ACTIONS=false run_make_prompt bogus 0.1.0 HEAD
  assert_exit_code 1
  assert_first_line_starts_with "$TEST_STDERR" "Error: " "GITHUB_ACTIONS 是 false 時的前綴"
}

# 訊息裡帶進去的值若含 LF，不能讓 stderr 多出一行（多出來的行可能以 :: 開頭，被當成 workflow command）
test_make_prompt_error_message_stays_on_one_line() {
  setup_bump_repo

  GITHUB_ACTIONS=true run_make_prompt $'bogus\n::warning::x' 0.1.0 HEAD
  assert_exit_code 1
  assert_file_empty "$TEST_STDOUT"
  assert_equals "1" "$(($(wc -l <"$TEST_STDERR")))" "stderr 的行數"

  GITHUB_ACTIONS=true run_make_prompt bump-level $'0.1.0\n::warning::x' HEAD
  assert_exit_code 1
  assert_file_empty "$TEST_STDOUT"
  assert_equals "1" "$(($(wc -l <"$TEST_STDERR")))" "版號含 LF 時 stderr 的行數"
}
