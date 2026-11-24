#!/usr/bin/env bash
# test-release.sh：release.sh 的測試，目前涵蓋流程的第 1 到 5 步（任務 1.4）：選擇模式、解析供應商與模型、
# 讀取版號與選擇計畫、判斷升級等級、撰寫 Release Notes，以及 AI 請求失敗的處理。
# 由 run-tests.sh 載入，不單獨執行。
#
# 以假的 lkai、gh、swift 與暫存的 git repo 測試（bare repo 作為 origin），不連網、不送 AI 請求。
#
# 報告（write_report）向 stdout 印出下列各行，每行「名稱：值」，不知道的行不印：
#   模式：dry-run 或 release
#   供應商：<供應商>
#   模型：<模型>
#   計畫：release-as-is、version-bump 或 nothing-to-release
#   升級等級：major、minor 或 patch（只有升版、回答被接受之後）
#   上一版：<版號>，照原樣發佈而沒有上一版時是「上一版：（無）」；沒有可發佈的變更時不印
#   新版號：<版號>；沒有可發佈的變更時不印
#   失敗的步驟：<design 固定清單中的名稱>（只有失敗時）
# 沒有可發佈的變更時，報告之後再印一行「沒有可發佈的變更。」，以 0 結束。
# 這一階段第 5 步之後暫時印出報告與 Release Notes 就以 1 結束（之後的任務取代），
# 所以「會繼續發版」的測試只斷言報告的行，不斷言退出碼。
#
# 失敗時 release.sh 保證：工作目錄沒有改變、沒有新的 commit、remote 沒有新的 commit 與 tag、
# 假的 gh 沒有收到 release create；每個失敗類的測試都用 assert_repo_untouched 與
# assert_no_release_created 檢查。
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

RELEASE_SCRIPT="$RELEASE_DIR/release.sh"
VERSION_FILE_PATH="Sources/LKAICore/LKAIKitInfo.swift"

# set_var 用的「沒有設定」：run-tests.sh 在每個測試開始前已經清掉相關變數，這個值表示維持沒有設定
NOT_SET="<not set>"

# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

# set_var <名稱> <值>：值是 NOT_SET 時 unset 這個變數，否則 export（空字串也是一個值）
set_var() {
  if [ "$2" = "$NOT_SET" ]; then
    unset "$1"
  else
    export "$1=$2"
  fi
}

# set_provider_variables <PROVIDER> <MODEL> <DEFAULT_PROVIDER> <DEFAULT_MODEL>：依序設定四個變數
set_provider_variables() {
  set_var LKAI_RELEASE_PROVIDER "$1"
  set_var LKAI_RELEASE_MODEL "$2"
  set_var LKAI_RELEASE_DEFAULT_PROVIDER "$3"
  set_var LKAI_RELEASE_DEFAULT_MODEL "$4"
}

# run_release：在暫存 repo 的根目錄執行 release.sh，結果同 run_cmd
run_release() {
  run_script "$RELEASE_SCRIPT"
}

# assert_has_line <檔案> <完整的一行> [<說明>]：檔案裡有一行逐字等於它
assert_has_line() {
  if ! grep -x -F -q -- "$2" "$1" 2>/dev/null; then
    fail "${3:-檔案裡沒有這一行}：$2" "檔案（cat -v）：$(show_file "$1")"
  fi
}

# assert_lacks_line <檔案> <完整的一行> [<說明>]：檔案裡沒有逐字等於它的一行
assert_lacks_line() {
  if grep -x -F -q -- "$2" "$1" 2>/dev/null; then
    fail "${3:-檔案裡不該有這一行}：$2" "檔案（cat -v）：$(show_file "$1")"
  fi
}

# call_count <假指令的記錄行>：calls.log 裡逐字等於這一行的行數；沒有 calls.log 時是 0
call_count() {
  if [ ! -f "$FAKE_LOG_DIR/calls.log" ]; then
    echo 0
    return
  fi
  grep -c -x -F -- "$1" "$FAKE_LOG_DIR/calls.log"
}

# lkai_request_count：送出幾次 AI 請求（升級等級加 Release Notes）
lkai_request_count() {
  echo $(($(call_count "lkai bump-level") + $(call_count "lkai release-notes")))
}

# assert_no_lkai_request：一次 AI 請求都沒有送
assert_no_lkai_request() {
  assert_equals "0" "$(lkai_request_count)" "不該送出任何 AI 請求"
}

# assert_no_release_created：假的 gh 沒有收到 release create
assert_no_release_created() {
  local count=0
  if [ -f "$FAKE_LOG_DIR/calls.log" ]; then
    count="$(grep -c '^gh release-create' "$FAKE_LOG_DIR/calls.log")"
  fi
  assert_equals "0" "$count" "不該建立任何 Release"
}

# snapshot_repo_state：記下暫存 repo 與 origin 目前的狀態，assert_repo_untouched 拿來比對
snapshot_repo_state() {
  repo_git rev-parse HEAD >"$TEST_TMP/state-head.txt"
  git ls-remote "$TEST_REMOTE" >"$TEST_TMP/state-remote.txt"
  repo_git tag --list >"$TEST_TMP/state-tags.txt"
}

# assert_repo_untouched：和 snapshot_repo_state 當時相比，HEAD、origin 的 main 與 tag、本機的 tag 都沒有改變，
# 工作目錄是乾淨的（LKAIKitInfo.swift 沒有被修改）
assert_repo_untouched() {
  repo_git rev-parse HEAD >"$TEST_TMP/after-head.txt"
  git ls-remote "$TEST_REMOTE" >"$TEST_TMP/after-remote.txt"
  repo_git tag --list >"$TEST_TMP/after-tags.txt"
  assert_files_equal "$TEST_TMP/state-head.txt" "$TEST_TMP/after-head.txt" "HEAD 被改變了"
  assert_files_equal "$TEST_TMP/state-remote.txt" "$TEST_TMP/after-remote.txt" "origin 的 main 或 tag 被改變了"
  assert_files_equal "$TEST_TMP/state-tags.txt" "$TEST_TMP/after-tags.txt" "本機的 tag 被改變了"
  assert_equals "" "$(repo_git status --porcelain)" "工作目錄要是乾淨的"
}

# assert_files_equal <預期的檔案> <實際的檔案> <說明>：兩個檔案逐 byte 相同
assert_files_equal() {
  if ! cmp -s "$1" "$2"; then
    fail "$3" "預期（cat -v）：$(show_file "$1")" "實際（cat -v）：$(show_file "$2")"
  fi
}

# assert_nothing_to_release_report：沒有可發佈的變更時，報告之後有一行「沒有可發佈的變更。」，
# 而且沒有任何以「上一版：」或「新版號：」開頭的行（這兩項在這種情況下都沒有值）
assert_nothing_to_release_report() {
  assert_has_line "$TEST_STDOUT" "計畫：nothing-to-release"
  assert_has_line "$TEST_STDOUT" "沒有可發佈的變更。"
  assert_equals "0" "$(grep -c '^上一版：' "$TEST_STDOUT")" "沒有可發佈的變更時不該有「上一版：」那一行"
  assert_equals "0" "$(grep -c '^新版號：' "$TEST_STDOUT")" "沒有可發佈的變更時不該有「新版號：」那一行"
}

# assert_failed_with_step <失敗的步驟>：以 1 結束，stdout 的報告有「失敗的步驟：<名稱>」，stderr 有訊息，
# 沒有任何改變、沒有建立 Release
assert_failed_with_step() {
  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：$1" "報告要寫出失敗的步驟"
  assert_file_not_empty "$TEST_STDERR" "失敗時 stderr 要有訊息"
  assert_repo_untouched
  assert_no_release_created
}

# ---------------------------------------------------------------------------
# 情境：暫存 repo，結束時已經推上 origin，並記下狀態（snapshot_repo_state）
# ---------------------------------------------------------------------------

# new_release_repo <HEAD 的版號>：use_fakes、make_test_repo，再把 HEAD 的版號固定成 <版號>
new_release_repo() {
  use_fakes
  make_test_repo
  commit_version "$1"
}

# finish_fixture：把 main 推上 origin，記下狀態
finish_fixture() {
  push_main
  snapshot_repo_state
}

# fixture_first_release：版號 0.1.0，沒有任何 tag
fixture_first_release() {
  new_release_repo 0.1.0
  finish_fixture
}

# fixture_nothing_to_release：版號 0.1.0，tag 0.1.0（有 Release）就在 HEAD
fixture_nothing_to_release() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  finish_fixture
}

# fixture_version_bump：版號 0.1.0，tag 0.1.0（有 Release）之後有一個改 Sources/ 的 commit
fixture_version_bump() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 新增公開介面" "Sources/LKAICore/Feature.swift"
  finish_fixture
}

# ---------------------------------------------------------------------------
# Release mode
# ---------------------------------------------------------------------------

# assert_mode_accepted <LKAI_RELEASE_DRY_RUN> <GITHUB_ACTIONS> <預期的模式>：
# 用沒有可發佈的變更的 repo，所以之後的步驟再怎麼增加，結果都不變：報告有「模式：…」，退出碼 0，沒有 AI 請求
assert_mode_accepted() {
  fixture_nothing_to_release
  set_var LKAI_RELEASE_DRY_RUN "$1"
  set_var GITHUB_ACTIONS "$2"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "模式：$3"
  assert_has_line "$TEST_STDOUT" "沒有可發佈的變更。"
  assert_no_lkai_request
  assert_repo_untouched
}

# assert_mode_rejected <LKAI_RELEASE_DRY_RUN> <GITHUB_ACTIONS> <訊息要含有的字>：
# 用還沒有 tag 的 repo（沒有被拒絕的話會送出 AI 請求）：退出碼 1，stderr 有那個字，
# 假的 lkai、gh、swift 一個都沒有被呼叫（calls.log 不存在），也就是沒有讀版號、沒有送請求
assert_mode_rejected() {
  fixture_first_release
  set_var LKAI_RELEASE_DRY_RUN "$1"
  set_var GITHUB_ACTIONS "$2"

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_file_contains "$TEST_STDERR" "$3" "訊息要含有「$3」"
  if [ -e "$FAKE_LOG_DIR/calls.log" ]; then
    fail "模式被拒絕時，不該呼叫任何假指令" "calls.log（cat -v）：$(show_file "$FAKE_LOG_DIR/calls.log")"
  fi
  assert_repo_untouched
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_not_set_and_not_in_actions_is_a_dry_run() {
  assert_mode_accepted "$NOT_SET" "$NOT_SET" "dry-run"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_empty_in_actions_is_a_dry_run() {
  assert_mode_accepted "" "true" "dry-run"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_true_in_actions_is_a_dry_run() {
  assert_mode_accepted "true" "true" "dry-run"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_false_in_actions_is_a_release() {
  assert_mode_accepted "false" "true" "release"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_false_outside_actions_is_rejected() {
  assert_mode_rejected "false" "$NOT_SET" "GitHub Actions"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_uppercase_true_is_rejected() {
  assert_mode_rejected "TRUE" "true" "TRUE"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_one_is_rejected() {
  assert_mode_rejected "1" "$NOT_SET" "1"
}

# ---------------------------------------------------------------------------
# Release provider and model selection
# ---------------------------------------------------------------------------

# assert_provider_resolved <PROVIDER> <MODEL> <DEFAULT_PROVIDER> <DEFAULT_MODEL> <預期的供應商> <預期的模型>：
# 用沒有可發佈的變更的 repo，報告有「供應商：…」與「模型：…」，退出碼 0，沒有 AI 請求
assert_provider_resolved() {
  fixture_nothing_to_release
  set_provider_variables "$1" "$2" "$3" "$4"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "供應商：$5"
  assert_has_line "$TEST_STDOUT" "模型：$6"
  assert_has_line "$TEST_STDOUT" "沒有可發佈的變更。"
  assert_no_lkai_request
}

# assert_provider_rejected <PROVIDER> <MODEL> <DEFAULT_PROVIDER> <DEFAULT_MODEL>：
# 用還沒有 tag 的 repo（沒有被擋下的話會送出 AI 請求）：退出碼 1，訊息寫出 LKAI_RELEASE_MODEL 與
# LKAI_RELEASE_DEFAULT_MODEL，沒有 AI 請求，報告的失敗步驟是「解析供應商與模型」
assert_provider_rejected() {
  fixture_first_release
  set_provider_variables "$1" "$2" "$3" "$4"

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_file_contains "$TEST_STDERR" "LKAI_RELEASE_MODEL" "訊息要寫出 LKAI_RELEASE_MODEL"
  assert_file_contains "$TEST_STDERR" "LKAI_RELEASE_DEFAULT_MODEL" "訊息要寫出 LKAI_RELEASE_DEFAULT_MODEL"
  assert_no_lkai_request
  assert_has_line "$TEST_STDOUT" "失敗的步驟：解析供應商與模型"
  assert_repo_untouched
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_provider_and_model_default_to_anthropic_and_claude_opus() {
  assert_provider_resolved "$NOT_SET" "$NOT_SET" "$NOT_SET" "$NOT_SET" "anthropic" "claude-opus-5-5"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_provider_and_model_use_the_repository_defaults() {
  assert_provider_resolved "" "" "openai" "gpt-6-luna" "openai" "gpt-6-luna"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_provider_of_this_run_without_a_model_is_rejected() {
  assert_provider_rejected "google" "" "anthropic" "claude-sonnet-5-5"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_provider_and_model_of_this_run_win_over_the_defaults() {
  assert_provider_resolved "openai" "gpt-6-luna" "anthropic" "claude-sonnet-5-5" "openai" "gpt-6-luna"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_model_of_this_run_with_the_default_provider() {
  assert_provider_resolved "" "claude-sonnet-5-5" "$NOT_SET" "$NOT_SET" "anthropic" "claude-sonnet-5-5"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_default_model_alone_is_used_with_the_default_provider() {
  assert_provider_resolved "$NOT_SET" "$NOT_SET" "$NOT_SET" "claude-sonnet-5-5" "anthropic" "claude-sonnet-5-5"
}

# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
test_release_default_provider_without_any_model_is_rejected() {
  assert_provider_rejected "$NOT_SET" "$NOT_SET" "openai" "$NOT_SET"
}

# release.sh 不檢查供應商的值，原樣交給 lkai：lkai 以 64 拒絕時，release.sh 以 1 結束，並保留 lkai 的 stderr。
# 用還沒有 tag 的 repo，第一個 AI 請求是 Release Notes。
# spectra-scenario: release-automation / Resolve the provider and the model
# spectra-scenario: release-automation / Resolve the provider and the model / provider and model resolution
# spectra-scenario: release-automation / lkai rejects the provider
test_release_unknown_provider_is_passed_to_lkai_and_its_rejection_fails_the_run() {
  fixture_first_release
  set_provider_variables "gemini" "x" "$NOT_SET" "$NOT_SET"
  export FAKE_LKAI_NOTES_EXIT=64
  export FAKE_LKAI_NOTES_STDERR="Error: unknown provider gemini"

  run_release

  assert_exit_code 1 "release.sh 的退出碼，不沿用 lkai 的 64"
  assert_has_line "$TEST_STDOUT" "供應商：gemini"
  assert_has_line "$TEST_STDOUT" "模型：x"
  assert_has_line "$FAKE_LOG_DIR/lkai-release-notes-1.args" "--provider"
  assert_has_line "$FAKE_LOG_DIR/lkai-release-notes-1.args" "gemini"
  assert_has_line "$FAKE_LOG_DIR/lkai-release-notes-1.args" "--model"
  assert_has_line "$FAKE_LOG_DIR/lkai-release-notes-1.args" "x"
  assert_file_contains "$TEST_STDERR" "Error: unknown provider gemini" "要保留 lkai 的 stderr"
  assert_failed_with_step "撰寫 Release Notes"
}

# ---------------------------------------------------------------------------
# Release plan
# ---------------------------------------------------------------------------

# assert_plan <計畫> <上一版的那一行的值> <新版號>：報告的計畫、上一版與新版號三行。
# 上一版沒有時寫「（無）」。
assert_plan() {
  assert_has_line "$TEST_STDOUT" "計畫：$1"
  assert_has_line "$TEST_STDOUT" "上一版：$2"
  assert_has_line "$TEST_STDOUT" "新版號：$3"
}

# assert_plan_rejected <訊息要含有的最高 tag>：以 1 結束，訊息寫出最高的 tag，沒有送出 AI 請求，
# 報告的失敗步驟是「讀取版號」，沒有任何改變
assert_plan_rejected() {
  assert_exit_code 1 "release.sh 的退出碼"
  assert_file_contains "$TEST_STDERR" "$1" "訊息要寫出最高的 tag $1"
  assert_no_lkai_request
  assert_has_line "$TEST_STDOUT" "失敗的步驟：讀取版號"
  assert_repo_untouched
  assert_no_release_created
}

# 沒有 tag，版號 0.1.0：照原樣發佈，沒有上一版
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_without_tags_releases_as_is() {
  fixture_first_release

  run_release

  assert_plan "release-as-is" "（無）" "0.1.0"
}

# tag 0.1.0 之後有 3 個改 Sources/ 的 commit：升版，上一版 0.1.0，新版號由假的 lkai 的預設回答 patch 算出 0.1.1
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_source_changes_after_the_tag_is_a_version_bump() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 第一個變更" "Sources/LKAICore/ChangeA.swift"
  commit_change "feat: 第二個變更" "Sources/LKAICore/ChangeB.swift"
  commit_change "fix: 第三個變更" "Sources/LKAICore/ChangeC.swift"
  finish_fixture

  run_release

  assert_plan "version-bump" "0.1.0" "0.1.1"
  assert_equals "1" "$(call_count "lkai bump-level")" "升版要送出一次升級等級的請求"
}

# tag 就在 HEAD：沒有 commit，沒有可發佈的變更，以 0 結束，沒有 AI 請求
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_no_commit_after_the_tag_has_nothing_to_release() {
  fixture_nothing_to_release

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_nothing_to_release_report
  assert_no_lkai_request
  assert_repo_untouched
}

# tag 之後只有 docs/spectra/ 的變更：沒有可發佈的變更
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_only_spectra_changes_after_the_tag_has_nothing_to_release() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "docs: 更新 tasks" "docs/spectra/changes/x/tasks.md"
  commit_change "docs: 更新 spec" "docs/spectra/specs/cli-chat/spec.md"
  finish_fixture

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_nothing_to_release_report
  assert_no_lkai_request
  assert_repo_untouched
}

# 版號 1.0.0，tag 0.1.0 與 0.2.0（都在 HEAD 的祖先）：照原樣發佈，上一版是最高的 0.2.0
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_a_hand_set_major_version_releases_as_is_after_the_highest_tag() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 0.2.0 的功能" "Sources/LKAICore/Feature.swift"
  make_version_tag 0.2.0
  commit_version 1.0.0
  finish_fixture

  run_release

  assert_plan "release-as-is" "0.2.0" "1.0.0"
}

# 版號 0.1.5，tag 0.1.0 與 0.2.0：有比現在版號更大的 tag，被拒絕，訊息寫出 0.2.0
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_a_greater_tag_than_the_version_is_rejected() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 0.2.0 的功能" "Sources/LKAICore/Feature.swift"
  make_version_tag 0.2.0
  commit_version 0.1.5
  finish_fixture

  run_release

  assert_plan_rejected "0.2.0"
}

# 版號 0.1.0 與它的 tag，tag 之後有 3 個改 Sources/ 的 commit，另外有比較大的 tag 0.2.0：被拒絕（在送出 AI 請求之前）
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_with_a_greater_tag_is_rejected_before_any_ai_request() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 第一個變更" "Sources/LKAICore/ChangeA.swift"
  commit_change "feat: 第二個變更" "Sources/LKAICore/ChangeB.swift"
  commit_change "fix: 第三個變更" "Sources/LKAICore/ChangeC.swift"
  make_version_tag 0.2.0
  finish_fixture

  run_release

  assert_plan_rejected "0.2.0"
}

# 版號 0.10.0，tag 0.9.0：版號逐段以整數比較（0.10.0 比 0.9.0 大），照原樣發佈，上一版 0.9.0
# spectra-scenario: release-automation / Choose the plan
# spectra-scenario: release-automation / Choose the plan / plans
test_release_plan_compares_versions_part_by_part_as_integers() {
  new_release_repo 0.1.0
  make_version_tag 0.9.0
  commit_version 0.10.0
  finish_fixture

  run_release

  assert_plan "release-as-is" "0.9.0" "0.10.0"
}

# 最新的 tag 是 0.4.2（有 Release），PR 把版號手動改成 1.0.0：照原樣發佈 1.0.0，上一版 0.4.2，沒有建立版號 commit
# spectra-scenario: release-automation / Choose a version by hand
test_release_plan_for_a_hand_set_version_creates_no_version_commit() {
  new_release_repo 0.1.0
  make_version_tag 0.4.2
  commit_version 1.0.0
  finish_fixture

  run_release

  assert_plan "release-as-is" "0.4.2" "1.0.0"
  assert_repo_untouched
}

# HEAD 的版號是 0.1.0，工作目錄有還沒 commit 的修改把它改成 0.9.0：目前版號是 0.1.0，而且工作目錄的修改原封不動
# spectra-scenario: release-automation / Read the version at HEAD
test_release_plan_reads_the_version_at_head_not_the_working_tree() {
  fixture_first_release
  "$BASH" "$RELEASE_DIR/package-version.sh" set "$TEST_REPO/$VERSION_FILE_PATH" 0.9.0 ||
    fail "無法修改工作目錄的版號"

  run_release

  assert_has_line "$TEST_STDOUT" "新版號：0.1.0"
  assert_lacks_line "$TEST_STDOUT" "新版號：0.9.0" "不該讀工作目錄的版號"
  assert_equals "0.9.0" "$("$BASH" "$RELEASE_DIR/package-version.sh" get "$TEST_REPO/$VERSION_FILE_PATH")" "工作目錄的修改要原封不動"
  repo_git rev-parse HEAD >"$TEST_TMP/after-head.txt"
  assert_files_equal "$TEST_TMP/state-head.txt" "$TEST_TMP/after-head.txt" "HEAD 被改變了"
}

# ---------------------------------------------------------------------------
# AI bump level answer
# ---------------------------------------------------------------------------

# assert_answer_accepted <lkai 的 stdout> <預期的等級>：升版（0.1.0 的 tag 之後有改 Sources/ 的 commit），
# 回答被接受，報告有「升級等級：…」，0.x 的 minor 與 patch 都只升 PATCH，所以新版號是 0.1.1
assert_answer_accepted() {
  fixture_version_bump
  export FAKE_LKAI_BUMP_REPLY="$1"

  run_release

  assert_has_line "$TEST_STDOUT" "升級等級：$2"
  assert_has_line "$TEST_STDOUT" "新版號：0.1.1"
  assert_equals "1" "$(call_count "lkai release-notes")" "回答被接受之後要送出 Release Notes 的請求"
}

# assert_answer_rejected <lkai 的 stdout> [<stderr 要含有的回答文字>]：回答被拒絕：以 1 結束，
# stderr 有錯誤訊息（有回答文字時，含它的前 200 bytes），沒有送出 Release Notes 的請求，
# 報告的失敗步驟是「判斷升級等級」，沒有任何改變
assert_answer_rejected() {
  fixture_version_bump
  export FAKE_LKAI_BUMP_REPLY="$1"

  run_release

  assert_failed_with_step "判斷升級等級"
  if [ -n "${2:-}" ]; then
    assert_file_contains "$TEST_STDERR" "$2" "stderr 要含有被拒絕的回答"
  fi
  assert_equals "0" "$(call_count "lkai release-notes")" "回答被拒絕時不該送出 Release Notes 的請求"
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_answer_minor_with_a_line_feed_is_accepted() {
  assert_answer_accepted $'minor\n' "minor"
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_answer_patch_with_spaces_and_a_carriage_return_is_accepted() {
  assert_answer_accepted $'  patch\r\n' "patch"
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_answer_with_a_capital_letter_is_rejected() {
  assert_answer_rejected $'Major\n' "Major"
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_answer_with_a_trailing_period_is_rejected() {
  assert_answer_rejected $'minor.\n' "minor."
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_answer_with_an_explanation_line_is_rejected() {
  assert_answer_rejected $'patch\nbecause the change only fixes a bug\n' "because the change only fixes a bug"
}

# spectra-scenario: release-automation / Read the AI answer
# spectra-scenario: release-automation / Read the AI answer / answers
test_release_empty_answer_is_rejected() {
  assert_answer_rejected ""
}

# 被拒絕的回答是 67 個每個 3 bytes 的 CJK 字元：錯誤訊息只含前 66 個（200 bytes 截在第 67 個字元的中間，
# 不完整的字元要去掉），不含第 67 個；去掉不完整的字元時，工具不能在 stderr 留下訊息（iconv:）。
# 前 66 個是「甲」，第 67 個是「乙」，才分辨得出來。
# spectra-scenario: release-automation / Shorten a long rejected answer
test_release_long_rejected_answer_is_cut_at_a_whole_character() {
  local first_66="" count=0
  while [ "$count" -lt 66 ]; do
    first_66="${first_66}甲"
    count=$((count + 1))
  done
  fixture_version_bump
  export FAKE_LKAI_BUMP_REPLY="${first_66}乙"

  run_release

  assert_failed_with_step "判斷升級等級"
  assert_file_contains "$TEST_STDERR" "$first_66" "要含有回答的前 66 個字元"
  assert_file_not_contains "$TEST_STDERR" "乙" "不該含有第 67 個字元"
  assert_file_not_contains "$TEST_STDERR" "iconv:" "去掉不完整字元的工具不能在 stderr 留下訊息"
  if ! iconv -f UTF-8 -t UTF-8 "$TEST_STDERR" >/dev/null 2>&1; then
    fail "stderr 不是合法的 UTF-8：不完整的字元沒有去掉" "stderr（cat -v）：$(show_file "$TEST_STDERR")"
  fi
}

# ---------------------------------------------------------------------------
# Release notes generation 與 Failed AI request
# ---------------------------------------------------------------------------

# 還沒有 tag，lkai 以 0 結束、Release Notes 只有空格與 LF：失敗，沒有任何改變，沒有 tag 或 Release
# spectra-scenario: release-automation / The release notes are blank
test_release_blank_release_notes_fail_the_run() {
  fixture_first_release
  export FAKE_LKAI_NOTES=$'   \n'

  run_release

  assert_failed_with_step "撰寫 Release Notes"
}

# 升版，升級等級的請求以 1 結束並在 stderr 寫「Error: test failure」：失敗，stderr 保留 lkai 的訊息，
# 沒有送出 Release Notes 的請求，沒有任何改變
# spectra-scenario: release-automation / The AI service rejects the request
test_release_failed_bump_level_request_fails_the_run_and_keeps_the_error() {
  fixture_version_bump
  export FAKE_LKAI_BUMP_EXIT=1
  export FAKE_LKAI_BUMP_STDERR="Error: test failure"

  run_release

  assert_failed_with_step "判斷升級等級"
  assert_file_contains "$TEST_STDERR" "Error: test failure" "要保留 lkai 的 stderr"
  assert_equals "0" "$(call_count "lkai release-notes")" "升級等級失敗時不該送出 Release Notes 的請求"
}

# 升版，Release Notes 的請求以 2 結束（回答被截斷）：release.sh 以 1 結束（不沿用 2），沒有 tag 或 Release
# spectra-scenario: release-automation / The release notes are cut off
test_release_cut_off_release_notes_fail_the_run() {
  fixture_version_bump
  export FAKE_LKAI_NOTES_EXIT=2

  run_release

  assert_failed_with_step "撰寫 Release Notes"
}

# ---------------------------------------------------------------------------
# 呼叫 lkai 的方式
# ---------------------------------------------------------------------------

# 升版：先送升級等級，再送 Release Notes（calls.log 的順序）；兩次都帶供應商、模型、--prompt-file 與
# --timeout 180；Release Notes 另外帶 --max-output-tokens 8192；都不帶 --stream 與 --apiKey；
# Release Notes 的 prompt 含新版號，升級等級的 prompt 沒有
test_release_invokes_lkai_with_the_documented_arguments() {
  fixture_version_bump
  set_provider_variables "anthropic" "claude-opus-5-5" "$NOT_SET" "$NOT_SET"

  run_release

  local bump_args="$FAKE_LOG_DIR/lkai-bump-level-1.args"
  local notes_args="$FAKE_LOG_DIR/lkai-release-notes-1.args"
  local first_bump_call first_notes_call
  first_bump_call="$(grep -n -x -F "lkai bump-level" "$FAKE_LOG_DIR/calls.log" | head -n 1 | cut -d: -f1)"
  first_notes_call="$(grep -n -x -F "lkai release-notes" "$FAKE_LOG_DIR/calls.log" | head -n 1 | cut -d: -f1)"
  if [ -z "$first_bump_call" ] || [ -z "$first_notes_call" ] || [ "$first_bump_call" -ge "$first_notes_call" ]; then
    fail "要先送升級等級，再送 Release Notes" "calls.log（cat -v）：$(show_file "$FAKE_LOG_DIR/calls.log")"
  fi

  local args_file
  for args_file in "$bump_args" "$notes_args"; do
    assert_has_line "$args_file" "--provider"
    assert_has_line "$args_file" "anthropic"
    assert_has_line "$args_file" "--model"
    assert_has_line "$args_file" "claude-opus-5-5"
    assert_has_line "$args_file" "--prompt-file"
    assert_has_line "$args_file" "--timeout"
    assert_has_line "$args_file" "180"
    assert_lacks_line "$args_file" "--stream" "不加 --stream"
    assert_lacks_line "$args_file" "--apiKey" "不加 --apiKey：金鑰只從環境變數給 lkai"
  done
  assert_lacks_line "$bump_args" "--max-output-tokens" "升級等級用預設的輸出上限"
  assert_has_line "$notes_args" "--max-output-tokens"
  assert_has_line "$notes_args" "8192"

  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "要發佈的版號：0.1.1" "Release Notes 的 prompt 要有新版號"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "上一版：0.1.0"
  assert_file_not_contains "$FAKE_LOG_DIR/lkai-bump-level-1.prompt" "0.1.1" "升級等級的 prompt 不能先帶新版號"
}

# ---------------------------------------------------------------------------
# 任務 1.5：報告只印一次、dry run、job summary、AI 文字的保護、API 金鑰
# ---------------------------------------------------------------------------

# use_step_summary：建立 GITHUB_STEP_SUMMARY 指向的暫存檔（先放一行「已有的內容」，附加時不能蓋掉它）
use_step_summary() {
  SUMMARY_FILE="$TEST_TMP/step-summary.md"
  printf '已有的內容\n' >"$SUMMARY_FILE"
  export GITHUB_STEP_SUMMARY="$SUMMARY_FILE"
}

# line_number <檔案> <完整的一行>：這一行第一次出現的行號；沒有這一行時什麼都不印
line_number() {
  grep -n -x -F -- "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1
}

# assert_line_before <檔案> <行 a> <行 b>：兩行都在檔案裡，而且 a 在 b 之前
assert_line_before() {
  local a_number b_number
  a_number="$(line_number "$1" "$2")"
  b_number="$(line_number "$1" "$3")"
  if [ -z "$a_number" ] || [ -z "$b_number" ] || [ "$a_number" -ge "$b_number" ]; then
    fail "要先有「$2」，再有「$3」" "「$2」的行號：${a_number:-沒有}" "「$3」的行號：${b_number:-沒有}" \
      "檔案（cat -v）：$(show_file "$1")"
  fi
}

# assert_line_count <檔案> <完整的一行> <預期的次數>：這一行在檔案裡出現幾次
assert_line_count() {
  local count
  count="$(grep -c -x -F -- "$2" "$1" 2>/dev/null)"
  assert_equals "$3" "$count" "「$2」出現的次數"
}

# assert_wrapped_in_stop_commands <檔案> <被保護的那一行>：檔案裡有一行 ::stop-commands::<token>，
# token 是至少 32 個十六進位字元，之後有一行 ::<token>::，而被保護的那一行在這兩行之間（同一個檔案，也就是同一個流）
assert_wrapped_in_stop_commands() {
  local file="$1" text="$2" start_number token end_number text_number
  start_number="$(grep -n '^::stop-commands::' "$file" | head -n 1 | cut -d: -f1)"
  if [ -z "$start_number" ]; then
    fail "沒有 ::stop-commands::<token> 那一行" "檔案（cat -v）：$(show_file "$file")"
  fi
  token="$(sed -n "${start_number}p" "$file" | sed 's/^::stop-commands:://')"
  if ! printf '%s\n' "$token" | grep -q -E '^[0-9a-fA-F]{32,}$'; then
    fail "token 要是至少 32 個十六進位字元" "token（cat -v）：$(printf '%s' "$token" | cat -v)"
  fi
  end_number="$(line_number "$file" "::${token}::")"
  text_number="$(line_number "$file" "$text")"
  if [ -z "$end_number" ]; then
    fail "沒有對應的 ::<token>:: 那一行" "token：${token}" "檔案（cat -v）：$(show_file "$file")"
  fi
  if [ -z "$text_number" ]; then
    fail "沒有被保護的那一行：$text" "檔案（cat -v）：$(show_file "$file")"
  fi
  if [ "$start_number" -ge "$text_number" ] || [ "$text_number" -ge "$end_number" ]; then
    fail "「${text}」要在 ::stop-commands::<token> 與 ::<token>:: 之間" \
      "::stop-commands:: 的行號：${start_number}" "「${text}」的行號：${text_number}" "::<token>:: 的行號：${end_number}" \
      "檔案（cat -v）：$(show_file "$file")"
  fi
}

# assert_has_no_api_key <檔案>：檔案不含測試用的 API 金鑰。失敗訊息不印出金鑰
assert_has_no_api_key() {
  if grep -F -q -- "$TEST_API_KEY" "$1" 2>/dev/null; then
    fail "檔案含有 API 金鑰：$1"
  fi
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------

# tag 0.1.0（有 Release）之後有一個改 Sources/ 的 commit，AI 的回答是 patch，dry run：stdout 有計畫、
# 上一版、新版號、供應商與模型，接著是「Release Notes：」與 Release Notes；工作目錄、remote 的 main、
# tag 都沒有改變，沒有建立 Release，退出碼 0；報告只印一次。
# spectra-scenario: release-automation / Dry run a version bump
test_release_dry_run_of_a_version_bump_prints_the_plan_and_the_release_notes() {
  fixture_version_bump
  export LKAI_RELEASE_DRY_RUN=true
  export FAKE_LKAI_BUMP_REPLY=$'patch\n'
  export FAKE_LKAI_NOTES=$'## 新功能\n- 測試用的項目\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "模式：dry-run"
  assert_plan "version-bump" "0.1.0" "0.1.1"
  assert_has_line "$TEST_STDOUT" "供應商：anthropic"
  assert_has_line "$TEST_STDOUT" "模型：claude-opus-5-5"
  assert_line_count "$TEST_STDOUT" "模式：dry-run" 1
  assert_line_count "$TEST_STDOUT" "Release Notes：" 1
  assert_line_before "$TEST_STDOUT" "新版號：0.1.1" "Release Notes："
  assert_line_before "$TEST_STDOUT" "Release Notes：" "- 測試用的項目"
  assert_repo_untouched
  assert_no_release_created
}

# ---------------------------------------------------------------------------
# Run report：job summary
# ---------------------------------------------------------------------------

# 正式發版的版本（建立 commit、push 與 Release）要等任務 1.6；這裡先以 dry run 代替：
# GITHUB_ACTIONS=true、LKAI_RELEASE_DRY_RUN=true，job summary 要有模式、計畫、上一版、新版號、供應商、模型與
# Release Notes。summary 是 Markdown，各行寫成清單（前面加「- 」）；Release Notes 原樣接在後面；
# job summary 不是 job log，不加 stop-commands 的標記。1.6 會把這個測試改成正式發版的版本。
# spectra-scenario: release-automation / Report a release in the job summary
test_release_job_summary_reports_a_dry_run_release() {
  fixture_version_bump
  use_step_summary
  export GITHUB_ACTIONS=true
  export LKAI_RELEASE_DRY_RUN=true
  export FAKE_LKAI_NOTES=$'## 新功能\n- 測試用的項目\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "已有的內容" "附加到 summary，不能蓋掉原有的內容"
  assert_has_line "$SUMMARY_FILE" "- 模式：dry-run"
  assert_has_line "$SUMMARY_FILE" "- 計畫：version-bump"
  assert_has_line "$SUMMARY_FILE" "- 上一版：0.1.0"
  assert_has_line "$SUMMARY_FILE" "- 新版號：0.1.1"
  assert_has_line "$SUMMARY_FILE" "- 供應商：anthropic"
  assert_has_line "$SUMMARY_FILE" "- 模型：claude-opus-5-5"
  assert_file_contains "$SUMMARY_FILE" "Release Notes" "summary 要有 Release Notes 的標示"
  assert_has_line "$SUMMARY_FILE" "## 新功能" "Release Notes 原樣接在後面"
  assert_has_line "$SUMMARY_FILE" "- 測試用的項目" "Release Notes 原樣接在後面"
  assert_line_count "$SUMMARY_FILE" "- 模式：dry-run" 1
  assert_file_not_contains "$SUMMARY_FILE" "::stop-commands::" "job summary 不加 stop-commands 的標記"
}

# spectra-scenario: release-automation / Report nothing to release
test_release_job_summary_says_there_is_nothing_to_release() {
  fixture_nothing_to_release
  use_step_summary

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "已有的內容"
  assert_has_line "$SUMMARY_FILE" "- 模式：dry-run"
  assert_has_line "$SUMMARY_FILE" "- 計畫：nothing-to-release"
  assert_file_contains "$SUMMARY_FILE" "沒有可發佈的變更。"
  assert_line_count "$SUMMARY_FILE" "- 模式：dry-run" 1
}

# spectra-scenario: release-automation / Report a failed run
test_release_job_summary_names_the_failed_bump_level_request() {
  fixture_version_bump
  use_step_summary
  export FAKE_LKAI_BUMP_EXIT=1

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "已有的內容"
  assert_has_line "$SUMMARY_FILE" "- 模式：dry-run"
  assert_has_line "$SUMMARY_FILE" "- 計畫：version-bump"
  assert_has_line "$SUMMARY_FILE" "- 失敗的步驟：判斷升級等級"
  assert_line_count "$SUMMARY_FILE" "- 模式：dry-run" 1
}

# spectra-scenario: release-automation / Report a failure before the version is read
test_release_job_summary_names_the_failed_provider_resolution() {
  fixture_first_release
  use_step_summary
  export LKAI_RELEASE_PROVIDER=google
  export LKAI_RELEASE_MODEL=""

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "已有的內容"
  assert_has_line "$SUMMARY_FILE" "- 模式：dry-run"
  assert_has_line "$SUMMARY_FILE" "- 失敗的步驟：解析供應商與模型"
  assert_line_count "$SUMMARY_FILE" "- 模式：dry-run" 1
}

# 模式還沒選定就失敗（DRY_RUN 的值不認得）：沒有報告，也不寫 job summary
test_release_rejected_mode_prints_no_report_and_leaves_the_summary_alone() {
  fixture_first_release
  use_step_summary
  export LKAI_RELEASE_DRY_RUN=1

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_equals "0" "$(grep -c '^模式：' "$TEST_STDOUT")" "模式還沒選定時 stdout 不該有報告"
  assert_file_equals "$SUMMARY_FILE" '已有的內容\n'
}

# 每個結束點的報告只印一次：失敗的路徑（Release Notes 只有空白）與沒有可發佈的變更各一個
test_release_prints_the_report_once_when_the_run_fails() {
  fixture_first_release
  export FAKE_LKAI_NOTES=$'  \n'

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_equals "1" "$(grep -c '^模式：' "$TEST_STDOUT")" "報告的「模式：」行出現的次數"
  assert_equals "1" "$(grep -c '^失敗的步驟：' "$TEST_STDOUT")" "報告的「失敗的步驟：」行出現的次數"
}

test_release_prints_the_report_once_when_there_is_nothing_to_release() {
  fixture_nothing_to_release

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_equals "1" "$(grep -c '^模式：' "$TEST_STDOUT")" "報告的「模式：」行出現的次數"
  assert_line_count "$TEST_STDOUT" "沒有可發佈的變更。" 1
}

# ---------------------------------------------------------------------------
# AI text in the job log
# ---------------------------------------------------------------------------

# GITHUB_ACTIONS 是 true，Release Notes 含一行 ::error::injected：那一行在 stdout 的
# ::stop-commands::<token> 與 ::<token>:: 之間，token 至少 32 個十六進位字元
# spectra-scenario: release-automation / Release notes contain a workflow command
test_release_notes_with_a_workflow_command_are_wrapped_in_stop_commands() {
  fixture_first_release
  export GITHUB_ACTIONS=true
  export LKAI_RELEASE_DRY_RUN=true
  export FAKE_LKAI_NOTES=$'前言\n::error::injected\n結尾\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "::error::injected"
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "前言"
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "結尾"
  assert_equals "1" "$(grep -c '^::stop-commands::' "$TEST_STDOUT")" "token 一次執行只選一次，Release Notes 只包一次"
}

# GITHUB_ACTIONS 沒有設定（例如本機執行）時不加標記，輸出才不會多出看不懂的行
test_release_notes_are_not_wrapped_outside_github_actions() {
  fixture_first_release
  export LKAI_RELEASE_DRY_RUN=true
  export FAKE_LKAI_NOTES=$'前言\n::error::injected\n結尾\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "::error::injected" "Release Notes 照常印出"
  assert_equals "0" "$(grep -c '^::stop-commands::' "$TEST_STDOUT")" "不該有 ::stop-commands:: 那一行"
  assert_equals "0" "$(grep -c -E '^::[0-9a-fA-F]{32,}::$' "$TEST_STDOUT")" "不該有 ::<token>:: 那一行"
}

# 被拒絕的回答是 upgrade LF ::add-mask::x，GITHUB_ACTIONS 是 true：stderr 的 ::error:: 行不含回答的任何文字，
# 回答放在後面，在 ::stop-commands::<token> 與 ::<token>:: 之間（同一個流）
# spectra-scenario: release-automation / A rejected answer contains a workflow command
test_release_rejected_answer_with_a_workflow_command_is_wrapped_in_stop_commands() {
  fixture_version_bump
  export GITHUB_ACTIONS=true
  export FAKE_LKAI_BUMP_REPLY=$'upgrade\n::add-mask::x\n'

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  local error_lines
  error_lines="$(grep '^::error::' "$TEST_STDERR")"
  if [ -z "$error_lines" ]; then
    fail "stderr 要有 ::error:: 開頭的一行" "stderr（cat -v）：$(show_file "$TEST_STDERR")"
  fi
  assert_not_contains "$error_lines" "upgrade" "::error:: 那一行不能含 AI 的文字"
  assert_not_contains "$error_lines" "::add-mask::x" "::error:: 那一行不能含 AI 的文字"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "::add-mask::x"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "upgrade"
}

# ---------------------------------------------------------------------------
# API keys stay in the environment
# ---------------------------------------------------------------------------

# LKAI_ANTHROPIC_API_KEY 是 sk-test-secret，升版的 dry run：lkai 收到的引數、prompt 檔，以及 stdout、stderr、
# job summary 與假指令留下的所有記錄，都不含這個金鑰（金鑰只從環境變數交給 lkai）
# spectra-scenario: release-automation / Inspect the lkai invocation
test_release_never_writes_the_api_key_anywhere() {
  TEST_API_KEY="sk-test-secret"
  fixture_version_bump
  use_step_summary
  export LKAI_ANTHROPIC_API_KEY="$TEST_API_KEY"
  export LKAI_RELEASE_PROVIDER=anthropic
  export LKAI_RELEASE_MODEL=claude-opus-5-5

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "- 新版號：0.1.1" "確認有跑到最後，summary 才有內容可以檢查"
  assert_has_no_api_key "$TEST_STDOUT"
  assert_has_no_api_key "$TEST_STDERR"
  assert_has_no_api_key "$SUMMARY_FILE"
  local record
  for record in "$FAKE_LOG_DIR"/* "$FAKE_LOG_DIR"/releases/*/*; do
    if [ -f "$record" ]; then
      assert_has_no_api_key "$record"
    fi
  done
  assert_file_not_empty "$FAKE_LOG_DIR/lkai-bump-level-1.args" "lkai 的引數檔要在，才有東西可檢查"
  assert_file_not_empty "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "prompt 檔要在，才有東西可檢查"
}
