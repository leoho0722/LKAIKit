#!/usr/bin/env bash
# test-release.sh：release.sh 的測試，涵蓋流程的第 1 到 9 步與補建 Release：選擇模式、解析供應商與模型、
# 讀取版號、檢查 Release 與補建、選擇計畫、判斷升級等級、撰寫 Release Notes、dry run、修改版號、重新建置、
# 建立 commit 與 tag、推送、建立 Release，以及 AI 請求失敗與各步驟失敗時的處理。
# 由 run-tests.sh 載入，不單獨執行。
#
# 以假的 lkai、gh、swift 與暫存的 git repo 測試（bare repo 作為 origin），不連網、不送 AI 請求。
# 不設定任何模式變數時是 dry run，到第 6 步以 0 結束，不改任何東西；正式發版的測試一律以 release_mode
# （GITHUB_ACTIONS=true、LKAI_RELEASE_DRY_RUN=false）執行，push 真的推進 bare repo。
#
# 報告（write_report）向 stdout 印出下列各行，每行「名稱：值」，不知道的行不印：
#   模式：dry-run 或 release
#   供應商：<供應商>
#   模型：<模型>
#   計畫：release-as-is、version-bump 或 nothing-to-release
#   升級等級：major、minor 或 patch（只有升版、回答被接受之後）
#   上一版：<版號>，照原樣發佈而沒有上一版時是「上一版：（無）」；沒有可發佈的變更時不印；
#           找上一版失敗時（上一版是未知的，不是沒有）也不印
#   新版號：<版號>；沒有可發佈的變更時不印
#   補建的 Release：<tag>（補建了，或 dry run 時將會補建 Release 的 tag）
#   失敗的步驟：<design 固定清單中的名稱>（只有失敗時）
# 沒有可發佈的變更時，報告之後再印一行「沒有可發佈的變更。」。以 0 結束時，報告之後依序接
# 「補建的 Release Notes（<tag>）：」與補建的文字（有補建時），以及「Release Notes：」與這次的 Release Notes。
#
# 失敗時 release.sh 保證：工作目錄沒有改變、沒有新的 commit、remote 沒有新的 commit 與 tag、
# 假的 gh 沒有收到 release create；失敗類的測試用 assert_failed_with_step（含 assert_repo_untouched 與
# assert_no_release_created）檢查。兩種例外：補建成功之後才失敗時，補建的 Release 保留；建立 Release 失敗時，
# remote 已經有版號 commit 與 tag（下一次執行補建 Release）。這幾個測試不用 assert_no_release_created，
# 改成逐項斷言。
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
  assert_mode_rejected "false" "$NOT_SET" "正式發版只能在 GitHub Actions 中執行"
  assert_file_not_contains "$TEST_STDERR" "的值不認得" "false 是認得的值，被拒絕的原因是不在 GitHub Actions 中"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_uppercase_true_is_rejected() {
  assert_mode_rejected "TRUE" "true" "的值不認得：TRUE；"
}

# spectra-scenario: release-automation / Choose the mode
# spectra-scenario: release-automation / Choose the mode / modes
test_release_mode_one_is_rejected() {
  assert_mode_rejected "1" "$NOT_SET" "的值不認得：1；"
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

  assert_exit_code 0 "release.sh 的退出碼"
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

  assert_exit_code 0 "release.sh 的退出碼"
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

  assert_exit_code 0 "release.sh 的退出碼"
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

  assert_exit_code 0 "release.sh 的退出碼"
  assert_plan "release-as-is" "0.9.0" "0.10.0"
}

# 最新的 tag 是 0.4.2（有 Release），PR 把版號手動改成 1.0.0，正式發版：照原樣發佈 1.0.0，上一版 0.4.2，
# 沒有建立版號 commit（本機 HEAD 與 remote 的 main 都不變），tag 1.0.0 指向原本的 HEAD，建立了 Release 1.0.0，
# 也沒有問 AI 升級等級
# spectra-scenario: release-automation / Choose a version by hand
test_release_plan_for_a_hand_set_version_creates_no_version_commit() {
  new_release_repo 0.1.0
  make_version_tag 0.4.2
  commit_version 1.0.0
  finish_fixture
  release_mode
  local old_head
  old_head="$(repo_git rev-parse HEAD)"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_plan "release-as-is" "0.4.2" "1.0.0"
  assert_equals "$old_head" "$(repo_git rev-parse HEAD)" "不建立 commit"
  assert_equals "$old_head" "$(remote_git rev-parse refs/heads/main)" "remote 的 main 不變"
  assert_equals "$old_head" "$(remote_tag_commit 1.0.0)" "tag 1.0.0 指向原本的 HEAD"
  assert_equals "1" "$(call_count "gh release-create 1.0.0")" "建立 Release 1.0.0 一次"
  assert_release_record 1.0.0
  assert_equals "0" "$(call_count "lkai bump-level")" "人工指定的版號不問升級等級"
}

# HEAD 的版號是 0.1.0，工作目錄有還沒 commit 的修改把它改成 0.9.0：目前版號是 0.1.0，而且工作目錄的修改原封不動
# spectra-scenario: release-automation / Read the version at HEAD
test_release_plan_reads_the_version_at_head_not_the_working_tree() {
  fixture_first_release
  "$BASH" "$RELEASE_DIR/package-version.sh" set "$TEST_REPO/$VERSION_FILE_PATH" 0.9.0 ||
    fail "無法修改工作目錄的版號"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
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

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "升級等級：$2"
  assert_has_line "$TEST_STDOUT" "新版號：0.1.1"
  assert_equals "1" "$(call_count "lkai release-notes")" "回答被接受之後要送出 Release Notes 的請求"
}

# assert_answer_rejected <lkai 的 stdout> [<stderr 要含有的回答文字>]：正式發版時回答被拒絕：以 1 結束，
# stderr 有錯誤訊息（有回答文字時，含它的前 200 bytes），沒有送出 Release Notes 的請求，
# 報告的失敗步驟是「判斷升級等級」，沒有任何改變
assert_answer_rejected() {
  fixture_version_bump
  release_mode
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
  release_mode
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

# 正式發版，還沒有 tag，lkai 以 0 結束、Release Notes 只有空格與 LF：失敗，沒有任何改變，沒有 tag 或 Release
# spectra-scenario: release-automation / The release notes are blank
test_release_blank_release_notes_fail_the_run() {
  fixture_first_release
  release_mode
  export FAKE_LKAI_NOTES=$'   \n'

  run_release

  assert_failed_with_step "撰寫 Release Notes"
}

# 正式發版，升版，升級等級的請求以 1 結束並在 stderr 寫「Error: test failure」：失敗，stderr 保留 lkai 的訊息，
# 沒有送出 Release Notes 的請求，沒有任何改變
# spectra-scenario: release-automation / The AI service rejects the request
test_release_failed_bump_level_request_fails_the_run_and_keeps_the_error() {
  fixture_version_bump
  release_mode
  export FAKE_LKAI_BUMP_EXIT=1
  export FAKE_LKAI_BUMP_STDERR="Error: test failure"

  run_release

  assert_failed_with_step "判斷升級等級"
  assert_file_contains "$TEST_STDERR" "Error: test failure" "要保留 lkai 的 stderr"
  assert_equals "0" "$(call_count "lkai release-notes")" "升級等級失敗時不該送出 Release Notes 的請求"
}

# 正式發版，升版，Release Notes 的請求以 2 結束（回答被截斷）：release.sh 以 1 結束（不沿用 2），沒有 tag 或 Release
# spectra-scenario: release-automation / The release notes are cut off
test_release_cut_off_release_notes_fail_the_run() {
  fixture_version_bump
  release_mode
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

  assert_exit_code 0 "release.sh 的退出碼"
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
# 報告與 AI 文字：報告只印一次、dry run、job summary、AI 文字的保護、API 金鑰
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

# 在 GitHub Actions 中正式發版 0.1.1：job summary 要有模式 release、計畫、上一版、新版號、供應商、模型與
# Release Notes。summary 是 Markdown，各行寫成清單（前面加「- 」）；Release Notes 原樣接在後面；
# job summary 不是 job log，不加 stop-commands 的標記。
# spectra-scenario: release-automation / Report a release in the job summary
test_release_job_summary_reports_a_release() {
  fixture_version_bump
  use_step_summary
  release_mode
  export FAKE_LKAI_NOTES=$'## 新功能\n- 測試用的項目\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$SUMMARY_FILE" "已有的內容" "附加到 summary，不能蓋掉原有的內容"
  assert_has_line "$SUMMARY_FILE" "- 模式：release"
  assert_has_line "$SUMMARY_FILE" "- 計畫：version-bump"
  assert_has_line "$SUMMARY_FILE" "- 上一版：0.1.0"
  assert_has_line "$SUMMARY_FILE" "- 新版號：0.1.1"
  assert_has_line "$SUMMARY_FILE" "- 供應商：anthropic"
  assert_has_line "$SUMMARY_FILE" "- 模型：claude-opus-5-5"
  assert_file_contains "$SUMMARY_FILE" "Release Notes" "summary 要有 Release Notes 的標示"
  assert_has_line "$SUMMARY_FILE" "## 新功能" "Release Notes 原樣接在後面"
  assert_has_line "$SUMMARY_FILE" "- 測試用的項目" "Release Notes 原樣接在後面"
  assert_line_count "$SUMMARY_FILE" "- 模式：release" 1
  assert_file_not_contains "$SUMMARY_FILE" "::stop-commands::" "job summary 不加 stop-commands 的標記"
  assert_equals "1" "$(call_count "gh release-create 0.1.1")" "有建立 Release 0.1.1"
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

# ---------------------------------------------------------------------------
# 正式發版：版號 commit 與 tag 的推送、Release 的建立與補建
# ---------------------------------------------------------------------------
#
# 正式發版一律是 GITHUB_ACTIONS=true、LKAI_RELEASE_DRY_RUN=false（release_mode）。
# 暫存 repo 的 origin 是 bare repo（TEST_REMOTE），push 真的推進去；假的 gh 的 release create 會檢查 remote 有沒有
# 那個 tag（--verify-tag），建立成功才在 FAKE_LOG_DIR/releases/<tag>/ 寫下 Release 紀錄。
#
# 結果的檢查：
#   - 升版：remote 的 main 多一個 commit（只改版號那一行，github-actions[bot] 當 author 與 committer），
#     remote 有 lightweight tag <新版號> 指向它，再建立 Release。
#   - 照原樣發佈：沒有新的 commit，tag 在 HEAD，只推 tag，再建立 Release。
#   - 目前版號的 tag 沒有 Release 時先補建（Release repair），再照常判斷之後的計畫。

BOT_IDENTITY="github-actions[bot]|41898282+github-actions[bot]@users.noreply.github.com"

# release_mode：正式發版
release_mode() {
  export GITHUB_ACTIONS=true
  export LKAI_RELEASE_DRY_RUN=false
}

# remote_git <git 的引數>...：對 origin（bare repo）執行 git
remote_git() {
  git -C "$TEST_REMOTE" "$@"
}

# remote_tag_commit <tag>：remote 的 tag 指向的 commit；沒有這個 tag 時什麼都不印
remote_tag_commit() {
  remote_git rev-parse --verify --quiet "refs/tags/$1^{commit}"
}

# build_repair_repo：版號 0.1.1 的 tag 還沒有 Release（建立 Release 失敗之後的狀態）。
# tag 0.1.0（有 Release）之後一個改 Sources/ 的 commit，再一個把版號改成 0.1.1 的 commit，tag 0.1.1 在 HEAD、沒有 Release。
# 還沒有推上 origin 與記下狀態，呼叫端可以再加 commit，最後呼叫 finish_fixture。
build_repair_repo() {
  new_release_repo 0.1.0
  make_version_tag 0.1.0
  commit_change "feat: 0.1.1 的功能" "Sources/LKAICore/Feature.swift"
  commit_version 0.1.1
  make_version_tag 0.1.1 no-release
}

# arg_after <引數檔> <旗標>：假指令記錄的引數檔（一行一個引數）裡，跟在這個旗標後面的那一個引數
arg_after() {
  awk -v flag="$2" 'previous == flag { print; exit } { previous = $0 }' "$1"
}

# assert_calls_in_order <記錄行>...：calls.log 依序出現這些行（中間可以有別的呼叫）
assert_calls_in_order() {
  local previous_line=0 expected offset
  for expected in "$@"; do
    offset="$(tail -n +$((previous_line + 1)) "$FAKE_LOG_DIR/calls.log" | grep -n -x -F -m 1 -- "$expected" | cut -d: -f1)"
    if [ -z "$offset" ]; then
      fail "calls.log 沒有依序出現「${expected}」（要在第 ${previous_line} 行之後）" "calls.log（cat -v）：$(show_file "$FAKE_LOG_DIR/calls.log")"
    fi
    previous_line=$((previous_line + offset))
  done
}

# assert_release_record <tag>：假的 gh 有為這個 tag 建立 Release，標題是 tag 本身；
# Release 的內容是 Release Notes，沒有 stop-commands 的標記（標記只給 job log）
assert_release_record() {
  assert_file_equals "$FAKE_LOG_DIR/releases/$1/title" "$1\n"
  assert_file_not_empty "$FAKE_LOG_DIR/releases/$1/notes" "Release $1 的內容"
  assert_file_not_contains "$FAKE_LOG_DIR/releases/$1/notes" "::stop-commands::" "Release 的內容不該有 stop-commands 的標記"
}

# assert_bot_version_commit <remote 上的 commit> <版號>：只改 Sources/LKAICore/LKAIKitInfo.swift 的版號那一行，
# 訊息是「chore: 版本號更新為 <版號>」，author 與 committer 都是 github-actions[bot]
assert_bot_version_commit() {
  local commit="$1" version="$2"
  assert_equals "chore: 版本號更新為 ${version}" "$(remote_git log -1 --format=%s "$commit")" "版號 commit 的訊息"
  assert_equals "${BOT_IDENTITY}|${BOT_IDENTITY}" "$(remote_git log -1 --format='%an|%ae|%cn|%ce' "$commit")" "author 與 committer"
  assert_equals "Sources/LKAICore/LKAIKitInfo.swift" "$(remote_git diff --name-only "${commit}^" "$commit")" "只改這一個檔案"
  assert_equals "1	1	Sources/LKAICore/LKAIKitInfo.swift" "$(remote_git diff --numstat "${commit}^" "$commit")" "只改一行"
  assert_contains "$(remote_git diff -U0 "${commit}^" "$commit" | grep -E '^\+[^+]')" "\"${version}\"" "新增的那一行是新的版號"
}

# ---------------------------------------------------------------------------
# Version commit and tag push
# ---------------------------------------------------------------------------

# tag 0.1.0（有 Release）之後有改 Sources/ 的 commit，AI 回答 minor（0.x 的 minor 只升 PATCH）：
# remote 的 main 多一個只改版號的 commit，tag 0.1.1 指向它，再以 --verify-tag 建立 Release 0.1.1，退出碼 0
# spectra-scenario: release-automation / Bump the version
test_release_bump_pushes_the_version_commit_and_the_tag_then_creates_the_release() {
  fixture_version_bump
  release_mode
  export FAKE_LKAI_BUMP_REPLY=$'minor\n'
  export FAKE_LKAI_NOTES=$'## 新功能\n- 測試用的項目\n'
  local old_main
  old_main="$(remote_git rev-parse refs/heads/main)"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  local new_main
  new_main="$(remote_git rev-parse refs/heads/main)"
  assert_equals "$old_main" "$(remote_git rev-parse "${new_main}^")" "remote 的 main 只多一個 commit"
  assert_bot_version_commit "$new_main" "0.1.1"
  assert_equals "$new_main" "$(remote_tag_commit 0.1.1)" "tag 0.1.1 要指向版號 commit"
  assert_equals "commit" "$(remote_git cat-file -t refs/tags/0.1.1)" "tag 是 lightweight tag"
  assert_equals "$new_main" "$(repo_git rev-parse HEAD)" "暫存 repo 的 HEAD 就是推上去的 commit"
  assert_equals "" "$(repo_git status --porcelain)" "工作目錄是乾淨的"
  assert_equals "1" "$(call_count "gh release-create 0.1.1")" "建立 Release 0.1.1 一次"
  assert_has_line "$FAKE_LOG_DIR/gh-release-create-1.args" "0.1.1"
  assert_has_line "$FAKE_LOG_DIR/gh-release-create-1.args" "--verify-tag"
  assert_equals "0.1.1" "$(arg_after "$FAKE_LOG_DIR/gh-release-create-1.args" "--title")" "--title 的值"
  assert_release_record 0.1.1
  assert_has_line "$FAKE_LOG_DIR/releases/0.1.1/notes" "- 測試用的項目" "Release 的內容是 Release Notes"
  assert_has_line "$TEST_STDOUT" "模式：release"
  assert_plan "version-bump" "0.1.0" "0.1.1"
  assert_has_line "$TEST_STDOUT" "- 測試用的項目" "報告有 Release Notes"
  assert_calls_in_order "lkai bump-level" "lkai release-notes" "swift build" "swift show-bin-path" "lkai -v" "gh release-create 0.1.1"
  # 重新建置的兩個 swift 呼叫：第一個建置，第二個取 bin 資料夾；兩個都是 release 組態的 lkai product
  local build_args="$FAKE_LOG_DIR/swift-build-1.args" bin_path_args="$FAKE_LOG_DIR/swift-build-2.args"
  assert_equals "release" "$(arg_after "$build_args" "-c")" "建置的 -c 要是 release"
  assert_equals "lkai" "$(arg_after "$build_args" "--product")" "建置的 --product 要是 lkai"
  assert_lacks_line "$build_args" "--show-bin-path" "第一個呼叫是建置，不是取 bin 資料夾"
  assert_equals "release" "$(arg_after "$bin_path_args" "-c")" "取 bin 資料夾的 -c 要是 release"
  assert_equals "lkai" "$(arg_after "$bin_path_args" "--product")" "取 bin 資料夾的 --product 要是 lkai"
  assert_has_line "$bin_path_args" "--show-bin-path"
}

# 版號 commit 只含 LKAIKitInfo.swift：工作目錄裡剛好有一個沒有追蹤的檔案、一個已經 stage 的檔案，
# 兩個都不能進版號 commit，也不能被弄掉（仍然是沒有追蹤、仍然在 stage 裡）
test_release_bump_commits_only_the_version_file() {
  fixture_version_bump
  release_mode
  printf '沒有追蹤的檔案\n' >"$TEST_REPO/stray.txt"
  printf '已經 stage 的檔案\n' >"$TEST_REPO/staged.txt"
  repo_git add -- staged.txt || fail "git add 失敗"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_bot_version_commit "$(remote_git rev-parse refs/heads/main)" "0.1.1"
  assert_equals "A  staged.txt
?? stray.txt" "$(repo_git status --porcelain)" "原本的修改要留在原處，不能進版號 commit"
}

# move_remote_main：從另一個 clone 推一個新的 commit 到 origin 的 main（暫存 repo 本身沒有 fetch，
# 等於 release.sh 執行期間 main 前進了）。新的 commit 記在 MOVED_MAIN
move_remote_main() {
  git clone -q "$TEST_REMOTE" "$TEST_TMP/other" || fail "無法 clone remote"
  printf '另一個人的變更\n' >"$TEST_TMP/other/other-change.txt"
  git -C "$TEST_TMP/other" add other-change.txt || fail "git add 失敗"
  git -C "$TEST_TMP/other" -c user.name="Other User" -c user.email="other@example.invalid" commit -q -m "feat: 另一個人的變更" ||
    fail "git commit 失敗"
  git -C "$TEST_TMP/other" push -q origin main || fail "無法推上 remote"
  MOVED_MAIN="$(git -C "$TEST_TMP/other" rev-parse HEAD)"
}

# push 之前讓 remote 的 main 多一個 commit：
# push 被拒絕，remote 沒有版號 commit 也沒有 tag 0.1.1，退出碼 1，沒有建立 Release
# spectra-scenario: release-automation / Main moved during the run
test_release_main_moved_during_the_run_rejects_the_push_and_creates_nothing() {
  fixture_version_bump
  release_mode
  move_remote_main
  local moved_main="$MOVED_MAIN"

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：推送"
  assert_file_not_empty "$TEST_STDERR" "失敗時 stderr 要有訊息"
  assert_equals "$moved_main" "$(remote_git rev-parse refs/heads/main)" "remote 的 main 還是另一個人推的那個 commit"
  assert_equals "" "$(remote_tag_commit 0.1.1)" "remote 不該有 tag 0.1.1"
  assert_not_contains "$(remote_git log --format=%s refs/heads/main)" "chore: 版本號更新為 0.1.1" "remote 不該有版號 commit"
  assert_no_release_created
}

# 沒有 tag、版號 0.1.0：不建立 commit，tag 0.1.0 指向原本的 HEAD（remote 的 main 不變），
# Release 的標題是 0.1.0、內容是 Release Notes
# spectra-scenario: release-automation / Release as-is for the first time
test_release_as_is_for_the_first_time_pushes_only_the_tag() {
  fixture_first_release
  release_mode
  export FAKE_LKAI_NOTES=$'## 新功能\n- 第一次發版\n'
  local old_head
  old_head="$(repo_git rev-parse HEAD)"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_equals "$old_head" "$(repo_git rev-parse HEAD)" "不建立 commit"
  assert_equals "$old_head" "$(remote_git rev-parse refs/heads/main)" "remote 的 main 不變"
  assert_equals "$old_head" "$(remote_tag_commit 0.1.0)" "tag 0.1.0 指向原本的 HEAD"
  assert_equals "1" "$(call_count "gh release-create 0.1.0")" "建立 Release 0.1.0 一次"
  assert_has_line "$FAKE_LOG_DIR/gh-release-create-1.args" "--verify-tag"
  assert_release_record 0.1.0
  assert_has_line "$FAKE_LOG_DIR/releases/0.1.0/notes" "- 第一次發版" "Release 的內容是 Release Notes"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "這是 LKAIKit 的第一次發版，沒有上一版。" "沒有上一版時，prompt 要說明是第一次發版"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "chore: 建立測試用的 repo" "範圍從空的 tree 開始，要有第一個 commit 的標題"
  assert_plan "release-as-is" "（無）" "0.1.0"
  assert_equals "0" "$(call_count "swift build")" "照原樣發佈不重新建置"
}

# ---------------------------------------------------------------------------
# Release repair
# ---------------------------------------------------------------------------

# 版號 0.1.1 的 tag 在 HEAD、沒有 Release（上一次建立 Release 失敗）：補建 Release 0.1.1，範圍是 0.1.0 到 0.1.1；
# 之後沒有可發佈的變更，退出碼 0；報告有「補建的 Release：0.1.1」與「沒有可發佈的變更。」
# spectra-scenario: release-automation / Recover after a failed release creation
test_release_recovers_after_a_failed_release_creation() {
  build_repair_repo
  finish_fixture
  release_mode
  export FAKE_LKAI_NOTES=$'## 修正\n- 補建的項目\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_equals "1" "$(call_count "lkai release-notes")" "只送一次 Release Notes 的請求（補建用的）"
  assert_equals "0" "$(call_count "lkai bump-level")" "沒有可發佈的變更，不判斷升級等級"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "要發佈的版號：0.1.1" "補建的 prompt 要有版號"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "上一版：0.1.0" "補建的範圍從 0.1.0 開始"
  assert_equals "1" "$(call_count "gh release-create 0.1.1")" "補建 Release 0.1.1 一次"
  assert_release_record 0.1.1
  assert_has_line "$FAKE_LOG_DIR/releases/0.1.1/notes" "- 補建的項目"
  assert_has_line "$TEST_STDOUT" "計畫：nothing-to-release"
  assert_has_line "$TEST_STDOUT" "補建的 Release：0.1.1"
  assert_has_line "$TEST_STDOUT" "補建的 Release Notes（0.1.1）："
  assert_has_line "$TEST_STDOUT" "- 補建的項目" "報告有補建的 Release Notes"
  assert_has_line "$TEST_STDOUT" "沒有可發佈的變更。"
  assert_lacks_line "$TEST_STDOUT" "Release Notes：" "沒有這次的 Release Notes"
}

# 同上，但 tag 0.1.1 之後又合併了改 Sources/ 的 commit：先補建 0.1.1（範圍 0.1.0 到 0.1.1，不含 tag 之後的 commit），
# 再照常升版 0.1.2，上一版 0.1.1；兩個 Release 都建立
# spectra-scenario: release-automation / Recover when a new change was merged
test_release_recovers_and_then_bumps_when_a_new_change_was_merged() {
  build_repair_repo
  commit_change "feat: 0.1.1 之後的變更" "Sources/LKAICore/After.swift"
  finish_fixture
  release_mode
  export FAKE_LKAI_BUMP_REPLY=$'patch\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_calls_in_order \
    "gh release-list" "lkai release-notes" "gh release-create 0.1.1" \
    "lkai bump-level" "lkai release-notes" "gh release-create 0.1.2"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "要發佈的版號：0.1.1" "補建的 prompt"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "上一版：0.1.0" "補建的範圍從 0.1.0 開始"
  assert_file_not_contains "$FAKE_LOG_DIR/lkai-release-notes-1.prompt" "feat: 0.1.1 之後的變更" "補建的範圍只到 tag 0.1.1"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-2.prompt" "要發佈的版號：0.1.2" "升版的 prompt"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-2.prompt" "上一版：0.1.1" "升版的上一版是 0.1.1"
  assert_file_contains "$FAKE_LOG_DIR/lkai-release-notes-2.prompt" "feat: 0.1.1 之後的變更"
  assert_release_record 0.1.1
  assert_release_record 0.1.2
  assert_bot_version_commit "$(remote_git rev-parse refs/heads/main)" "0.1.2"
  assert_equals "$(remote_git rev-parse refs/heads/main)" "$(remote_tag_commit 0.1.2)" "tag 0.1.2 指向版號 commit"
  assert_has_line "$TEST_STDOUT" "補建的 Release：0.1.1"
  assert_plan "version-bump" "0.1.1" "0.1.2"
}

# gh release list 失敗：失敗，不送任何 AI 請求，不建立 Release
# spectra-scenario: release-automation / The release list cannot be read
test_release_fails_when_the_release_list_cannot_be_read() {
  fixture_nothing_to_release
  release_mode
  export FAKE_GH_LIST_EXIT=1

  run_release

  assert_failed_with_step "檢查 Release"
  assert_no_lkai_request
  assert_equals "1" "$(call_count "gh release-list")" "只列了一次 Release"
}

# 補建成功之後，升級等級的請求失敗：補建的 Release 保留；沒有升版 commit、沒有 tag 0.1.2、沒有其他 Release
# spectra-scenario: release-automation / A request fails after a repair
test_release_keeps_the_repaired_release_when_a_later_request_fails() {
  build_repair_repo
  commit_change "feat: 0.1.1 之後的變更" "Sources/LKAICore/After.swift"
  finish_fixture
  release_mode
  export FAKE_LKAI_BUMP_EXIT=1

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：判斷升級等級"
  assert_release_record 0.1.1
  assert_equals "1" "$(grep -c '^gh release-create' "$FAKE_LOG_DIR/calls.log")" "只建立補建的那一個 Release"
  assert_equals "1" "$(call_count "gh release-create 0.1.1")" "建立的是 Release 0.1.1"
  assert_repo_untouched
}

# dry run 時補建：只送補建用的 Release Notes 請求，報告有補建的文字，不建立 Release
test_release_dry_run_prints_the_repair_notes_without_creating_the_release() {
  build_repair_repo
  finish_fixture
  export FAKE_LKAI_NOTES=$'## 修正\n- 補建的項目\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_equals "1" "$(call_count "lkai release-notes")" "只送補建用的 Release Notes 請求"
  assert_equals "0" "$(call_count "lkai bump-level")" "沒有升級等級的請求"
  assert_no_release_created
  assert_has_line "$TEST_STDOUT" "模式：dry-run"
  assert_has_line "$TEST_STDOUT" "補建的 Release：0.1.1"
  assert_has_line "$TEST_STDOUT" "補建的 Release Notes（0.1.1）："
  assert_has_line "$TEST_STDOUT" "- 補建的項目"
  assert_has_line "$TEST_STDOUT" "沒有可發佈的變更。"
  assert_repo_untouched
}

# ---------------------------------------------------------------------------
# Release creation 與失敗時的狀態
# ---------------------------------------------------------------------------

# 重新建置後的 lkai -v 不是新版號：在 commit 之前失敗，版號檔還原，沒有 commit、沒有 tag（本機與 remote）
test_release_fails_before_committing_when_the_rebuilt_lkai_prints_another_version() {
  fixture_version_bump
  release_mode
  export FAKE_LKAI_VERSION=9.9.9

  run_release

  assert_failed_with_step "重新建置"
}

# swift build 失敗：同上
test_release_fails_before_committing_when_the_build_fails() {
  fixture_version_bump
  release_mode
  export FAKE_SWIFT_EXIT=1

  run_release

  assert_failed_with_step "重新建置"
}

# 建立 Release 失敗：失敗；remote 已經有版號 commit 與 tag 0.1.1（下一次執行會補建），沒有 Release 紀錄
test_release_fails_when_the_release_cannot_be_created_but_keeps_the_pushed_commit_and_tag() {
  fixture_version_bump
  release_mode
  export FAKE_GH_CREATE_EXIT=1
  local old_main
  old_main="$(remote_git rev-parse refs/heads/main)"

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：建立 Release"
  assert_file_not_empty "$TEST_STDERR" "失敗時 stderr 要有訊息"
  local new_main
  new_main="$(remote_git rev-parse refs/heads/main)"
  assert_equals "$old_main" "$(remote_git rev-parse "${new_main}^")" "remote 的 main 多了版號 commit"
  assert_bot_version_commit "$new_main" "0.1.1"
  assert_equals "$new_main" "$(remote_tag_commit 0.1.1)" "remote 有 tag 0.1.1"
  if [ -e "$FAKE_LOG_DIR/releases/0.1.1" ]; then
    fail "建立 Release 失敗時，不該有 Release 0.1.1 的紀錄"
  fi
}

# ---------------------------------------------------------------------------
# package-distribution：release tag 的名稱就是那個 commit 裡 LKAIKitInfo.version 的值
# ---------------------------------------------------------------------------

# assert_tag_matches_version <tag>：從 remote 讀出那個 tag 的 LKAIKitInfo.swift，版號等於 tag 的名稱
assert_tag_matches_version() {
  local source_file="$TEST_TMP/tag-$1-LKAIKitInfo.swift"
  remote_git show "$1:Sources/LKAICore/LKAIKitInfo.swift" >"$source_file" || fail "讀不到 tag $1 的 LKAIKitInfo.swift"
  assert_equals "$1" "$("$BASH" "$RELEASE_DIR/package-version.sh" get "$source_file")" "tag $1 的 LKAIKitInfo.version"
}

# spectra-scenario: package-distribution / Inspect a release tag
test_release_tag_of_a_version_bump_matches_the_declared_version() {
  fixture_version_bump
  release_mode

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_tag_matches_version 0.1.1
}

# spectra-scenario: package-distribution / Inspect a release tag
test_release_tag_of_a_release_as_is_matches_the_declared_version() {
  fixture_first_release
  release_mode

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_tag_matches_version 0.1.0
}

# ---------------------------------------------------------------------------
# 失敗的報告、補建的 Release Notes 的保護、補建失敗的步驟、本機已有同名 tag
# ---------------------------------------------------------------------------

# assert_release_not_recorded <tag>：假的 gh 沒有為這個 tag 建立 Release（沒有 Release 紀錄）
assert_release_not_recorded() {
  if [ -e "$FAKE_LOG_DIR/releases/$1" ]; then
    fail "不該有 Release $1 的紀錄"
  fi
}

# 失敗的報告（這裡是 push 被拒絕）只有各行與失敗的步驟：Release Notes 已經撰寫完成，但退出碼不是 0 的報告
# 不附上它（stdout 與 job summary 都是），也沒有 stop-commands 的標記（標記只包 AI 的文字）
# spectra-scenario: release-automation / Report a failed run
test_release_failed_run_report_has_no_release_notes() {
  fixture_version_bump
  release_mode
  use_step_summary
  export FAKE_LKAI_NOTES=$'## 新功能\n- 不該出現的項目\n'
  move_remote_main

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_equals "1" "$(call_count "lkai release-notes")" "Release Notes 已經撰寫完成（沒有這一步，下面的斷言沒有意義）"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：推送"
  assert_has_line "$SUMMARY_FILE" "- 失敗的步驟：推送"
  assert_file_not_contains "$TEST_STDOUT" "Release Notes" "失敗的報告不該有 Release Notes 的段落"
  assert_file_not_contains "$TEST_STDOUT" "不該出現的項目" "失敗的報告不該有 Release Notes 的文字"
  assert_file_not_contains "$TEST_STDOUT" "::stop-commands::" "沒有 AI 的文字，就不該有標記"
  assert_file_not_contains "$SUMMARY_FILE" "Release Notes" "job summary 也不該有 Release Notes 的段落"
  assert_file_not_contains "$SUMMARY_FILE" "不該出現的項目" "job summary 也不該有 Release Notes 的文字"
}

# GITHUB_ACTIONS 是 true、dry run，tag 0.1.1 沒有 Release 而且就在 HEAD（nothing-to-release）：補建的 Release Notes
# 含一行 ::error::injected。stdout 中那一行在 ::stop-commands::<token> 與 ::<token>:: 之間（標題行在外面）；
# job summary 原樣有那一行，沒有標記
# spectra-scenario: release-automation / Release notes contain a workflow command
test_release_repaired_release_notes_with_a_workflow_command_are_wrapped_in_stop_commands() {
  build_repair_repo
  finish_fixture
  export GITHUB_ACTIONS=true
  export LKAI_RELEASE_DRY_RUN=true
  use_step_summary
  export FAKE_LKAI_NOTES=$'補建的前言\n::error::injected\n補建的結尾\n'

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "計畫：nothing-to-release"
  assert_has_line "$TEST_STDOUT" "補建的 Release Notes（0.1.1）："
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "::error::injected"
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "補建的前言"
  assert_wrapped_in_stop_commands "$TEST_STDOUT" "補建的結尾"
  assert_equals "1" "$(grep -c '^::stop-commands::' "$TEST_STDOUT")" "補建的文字只包一次"
  assert_line_before "$TEST_STDOUT" "補建的 Release Notes（0.1.1）：" "$(grep -m 1 '^::stop-commands::' "$TEST_STDOUT")"
  assert_file_not_contains "$TEST_STDERR" "injected" "補建的文字只寫在 stdout"
  assert_has_line "$SUMMARY_FILE" "補建的 Release Notes（0.1.1）："
  assert_has_line "$SUMMARY_FILE" "::error::injected" "job summary 原樣接著補建的文字"
  assert_file_not_contains "$SUMMARY_FILE" "::stop-commands::" "job summary 不加 stop-commands 的標記"
}

# 補建時 lkai 的請求失敗：失敗的步驟是「補建 Release」；tag 0.1.1 之後還有一個 Sources/ 的 commit，
# 所以補建若沒有失敗，下一步會要求升級等級，「沒有升級等級的請求」才有意義。remote 不變、沒有 0.1.1 的
# Release 紀錄；報告沒有「補建的 Release」那一行（job summary 也是）
test_release_repair_notes_request_failure_fails_the_repair_step() {
  build_repair_repo
  commit_change "feat: 0.1.1 之後的變更" "Sources/LKAICore/After.swift"
  finish_fixture
  release_mode
  use_step_summary
  export FAKE_LKAI_NOTES_EXIT=1

  run_release

  assert_failed_with_step "補建 Release"
  assert_equals "1" "$(call_count "lkai release-notes")" "只有補建用的那一個請求"
  assert_equals "0" "$(call_count "lkai bump-level")" "沒有升級等級的請求"
  assert_release_not_recorded 0.1.1
  assert_file_not_contains "$TEST_STDOUT" "補建的 Release" "沒有補建成功，報告就不該有這一行"
  assert_has_line "$SUMMARY_FILE" "- 失敗的步驟：補建 Release"
  assert_file_not_contains "$SUMMARY_FILE" "補建的 Release" "job summary 也不該有這一行"
}

# 補建時 gh release create 失敗：同上；假的 gh 有收到那一個呼叫（所以不用 assert_failed_with_step 的
# 「沒有 release create」），但沒有留下 Release 紀錄
test_release_repair_release_creation_failure_fails_the_repair_step() {
  build_repair_repo
  commit_change "feat: 0.1.1 之後的變更" "Sources/LKAICore/After.swift"
  finish_fixture
  release_mode
  use_step_summary
  export FAKE_GH_CREATE_EXIT=1

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：補建 Release"
  assert_file_not_empty "$TEST_STDERR" "失敗時 stderr 要有訊息"
  assert_repo_untouched
  assert_equals "1" "$(call_count "lkai release-notes")" "只有補建用的那一個請求"
  assert_equals "0" "$(call_count "lkai bump-level")" "沒有升級等級的請求"
  assert_equals "1" "$(call_count "gh release-create 0.1.1")" "只試了補建的那一個"
  assert_equals "1" "$(grep -c '^gh release-create' "$FAKE_LOG_DIR/calls.log")" "沒有試別的 Release"
  assert_release_not_recorded 0.1.1
  assert_file_not_contains "$TEST_STDOUT" "補建的 Release" "沒有補建成功，報告就不該有這一行"
  assert_has_line "$SUMMARY_FILE" "- 失敗的步驟：補建 Release"
  assert_file_not_contains "$SUMMARY_FILE" "補建的 Release" "job summary 也不該有這一行"
}

# 目前版號的 tag（0.1.0）存在，但指向 tree，不是 commit：第 3 步看不到它（以 commit 解析不了），
# 不能把它當成「沒有 tag」而照原樣發佈，要在「讀取版號」失敗，訊息說這個 tag 沒有指向 commit；
# 沒有任何 AI 請求、沒有重新建置，沒有任何改變
test_release_fails_when_the_tag_of_the_version_points_to_a_tree() {
  new_release_repo 0.1.0
  repo_git tag 0.1.0 "$(repo_git rev-parse 'HEAD^{tree}')" || fail "無法建立指向 tree 的 tag"
  finish_fixture
  release_mode

  run_release

  assert_failed_with_step "讀取版號"
  assert_file_contains "$TEST_STDERR" "目前版號的 tag 0.1.0 沒有指向 commit" "要是「目前版號的 tag」那道檢查擋下的（不是找上一版時的檢查）"
  assert_no_lkai_request
  assert_equals "0" "$(call_count "swift build")" "沒有重新建置"
}

# ---------------------------------------------------------------------------
# lkai 的 stderr、被訊號結束時的報告、供應商與模型的顯示、git commit 失敗
# ---------------------------------------------------------------------------

# 假的 lkai 失敗時寫到 stderr 的文字：多行，其中一行是 workflow command。OpenAI 回報拒答時，lkai 以
# 「Details: <模型寫的拒答文字>」印到 stderr，原樣、可以跨多行，所以這是 AI 寫的文字
LKAI_STDERR_TEXT=$'Error: refused\nDetails: 拒答\n::add-mask::x'

# assert_lkai_stderr_is_protected：LKAI_STDERR_TEXT 的每一行都只出現一次，而且都在 stderr 的
# ::stop-commands::<token> 與 ::<token>:: 之間；token 一次執行只選一次，所以只有一組標記
assert_lkai_stderr_is_protected() {
  assert_wrapped_in_stop_commands "$TEST_STDERR" "Error: refused"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "Details: 拒答"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "::add-mask::x"
  assert_line_count "$TEST_STDERR" "::add-mask::x" 1
  assert_equals "1" "$(grep -c '^::stop-commands::' "$TEST_STDERR")" "lkai 的 stderr 只包一次"
  assert_file_not_contains "$TEST_STDOUT" "add-mask" "lkai 的 stderr 不該跑到 stdout"
}

# assert_lkai_stderr_is_plain：不在 GitHub Actions 中，lkai 的 stderr 原樣出現，沒有任何標記
assert_lkai_stderr_is_plain() {
  assert_has_line "$TEST_STDERR" "Error: refused" "要保留 lkai 的 stderr"
  assert_has_line "$TEST_STDERR" "Details: 拒答" "要保留 lkai 的 stderr"
  assert_has_line "$TEST_STDERR" "::add-mask::x" "要保留 lkai 的 stderr"
  assert_equals "0" "$(grep -c '^::stop-commands::' "$TEST_STDERR")" "不該有 ::stop-commands:: 那一行"
  assert_equals "0" "$(grep -c -E '^::[0-9a-fA-F]{32,}::$' "$TEST_STDERR")" "不該有 ::<token>:: 那一行"
}

# args_after_flag <引數檔> <旗標> <行數>：引數檔（一行一個引數）裡，旗標後面的幾行，以 | 接起來。
# 引數裡有 LF 時，一個引數會佔多行，所以要看幾行
args_after_flag() {
  local number
  number="$(line_number "$1" "$2")"
  if [ -z "$number" ]; then
    fail "引數檔裡沒有 $2：$1" "檔案（cat -v）：$(show_file "$1")"
  fi
  sed -n "$((number + 1)),$((number + $3))p" "$1" | paste -s -d '|' -
}

# GITHUB_ACTIONS 是 true，升級等級的請求以 1 結束，stderr 是多行、含 ::add-mask::x：lkai 的 stderr 是 AI 寫的文字
# （模型的拒答、被截斷的回答等），要保留在 release.sh 自己的 stderr，而且在同一個流以
# ::stop-commands::<token> 與 ::<token>:: 包起來，GitHub 才不會執行裡面的 workflow command。
# 依據 spec「AI text in the job log」的「wherever release.sh writes text that comes from an AI answer to stdout or stderr」
test_release_stderr_of_the_bump_level_request_is_wrapped_in_stop_commands() {
  fixture_version_bump
  export GITHUB_ACTIONS=true
  export FAKE_LKAI_BUMP_EXIT=1
  export FAKE_LKAI_BUMP_STDERR="$LKAI_STDERR_TEXT"

  run_release

  assert_failed_with_step "判斷升級等級"
  assert_lkai_stderr_is_protected
}

# 同上，Release Notes 的請求（照原樣發佈只有這一個請求）：兩個呼叫處都經過同一條路
test_release_stderr_of_the_release_notes_request_is_wrapped_in_stop_commands() {
  fixture_first_release
  export GITHUB_ACTIONS=true
  export FAKE_LKAI_NOTES_EXIT=1
  export FAKE_LKAI_NOTES_STDERR="$LKAI_STDERR_TEXT"

  run_release

  assert_failed_with_step "撰寫 Release Notes"
  assert_lkai_stderr_is_protected
}

# GITHUB_ACTIONS 沒有設定（例如本機執行）時，lkai 的 stderr 原樣出現，不加標記，輸出才不會多出看不懂的行
test_release_stderr_of_the_bump_level_request_is_not_wrapped_outside_github_actions() {
  fixture_version_bump
  export FAKE_LKAI_BUMP_EXIT=1
  export FAKE_LKAI_BUMP_STDERR="$LKAI_STDERR_TEXT"

  run_release

  assert_failed_with_step "判斷升級等級"
  assert_lkai_stderr_is_plain
}

test_release_stderr_of_the_release_notes_request_is_not_wrapped_outside_github_actions() {
  fixture_first_release
  export FAKE_LKAI_NOTES_EXIT=1
  export FAKE_LKAI_NOTES_STDERR="$LKAI_STDERR_TEXT"

  run_release

  assert_failed_with_step "撰寫 Release Notes"
  assert_lkai_stderr_is_plain
}

# 升級等級的請求進行中，release.sh 收到 TERM（假的 lkai 對它的父行程送訊號，再照常結束）：以 1 結束，
# 報告仍然寫出失敗的步驟（判斷升級等級），而且只印一次；沒有改變 repo 與 remote，沒有建立 Release
# spectra-scenario: release-automation / Report a failed run
test_release_signal_during_a_request_reports_the_failed_step() {
  fixture_version_bump
  export FAKE_LKAI_SIGNAL_PARENT=TERM

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_equals "1" "$(call_count "lkai bump-level")" "升級等級的請求有送出（訊號是在請求進行中收到的）"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：判斷升級等級" "被訊號結束時，報告也要寫出失敗的步驟"
  assert_line_count "$TEST_STDOUT" "模式：dry-run" 1
  assert_line_count "$TEST_STDOUT" "供應商：anthropic" 1
  assert_line_count "$TEST_STDOUT" "模型：claude-opus-5-5" 1
  assert_line_count "$TEST_STDOUT" "計畫：version-bump" 1
  assert_repo_untouched
  assert_no_release_created
}

# 供應商與模型是原樣交給 lkai 的值，spec 不允許 release.sh 檢查它們，所以不拒絕；但寫進訊息與報告時，
# LF 要換成可見的 <LF>，免得值裡的一行變成另一條 workflow command。沒有可發佈的變更（不送請求）：
# 模型含 LF 與 ::warning::y 時，報告的那一行是「模型：x<LF>::warning::y」，stdout 與 stderr 都沒有以 ::warning:: 開頭的行
test_release_model_with_a_workflow_command_is_shown_on_one_line() {
  fixture_nothing_to_release
  export GITHUB_ACTIONS=true
  set_provider_variables "anthropic" $'x\n::warning::y' "$NOT_SET" "$NOT_SET"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "模型：x<LF>::warning::y"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDOUT")" "stdout 不該有以 ::warning:: 開頭的行"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDERR")" "stderr 不該有以 ::warning:: 開頭的行"
}

# 供應商的值也一樣
test_release_provider_with_a_workflow_command_is_shown_on_one_line() {
  fixture_nothing_to_release
  export GITHUB_ACTIONS=true
  set_provider_variables $'anthropic\n::warning::p' "x" "$NOT_SET" "$NOT_SET"

  run_release

  assert_exit_code 0 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "供應商：anthropic<LF>::warning::p"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDOUT")" "stdout 不該有以 ::warning:: 開頭的行"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDERR")" "stderr 不該有以 ::warning:: 開頭的行"
}

# 會送請求的版本（沒有 tag，Release Notes 的請求以 1 結束）：lkai 收到的 --model 是原樣的值
# （含 LF，所以在引數檔裡佔兩行），但錯誤訊息那一行（::error::）裡是 <LF>，stderr 沒有以 ::warning:: 開頭的行
test_release_model_with_a_workflow_command_is_passed_to_lkai_unchanged_and_shown_on_one_line() {
  fixture_first_release
  export GITHUB_ACTIONS=true
  export FAKE_LKAI_NOTES_EXIT=1
  set_provider_variables "anthropic" $'x\n::warning::y' "$NOT_SET" "$NOT_SET"

  run_release

  assert_failed_with_step "撰寫 Release Notes"
  assert_equals "x|::warning::y" "$(args_after_flag "$FAKE_LOG_DIR/lkai-release-notes-1.args" "--model" 2)" "lkai 收到的 --model 要是原樣的值"
  assert_equals "anthropic" "$(args_after_flag "$FAKE_LOG_DIR/lkai-release-notes-1.args" "--provider" 1)" "lkai 收到的 --provider"
  assert_has_line "$TEST_STDOUT" "模型：x<LF>::warning::y"
  assert_equals "1" "$(grep -c -E '^::error::.*x<LF>::warning::y' "$TEST_STDERR")" "::error:: 那一行要含 <LF>"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDOUT")" "stdout 不該有以 ::warning:: 開頭的行"
  assert_equals "0" "$(grep -c '^::warning::' "$TEST_STDERR")" "stderr 不該有以 ::warning:: 開頭的行"
}

# git commit 失敗（暫存 repo 的 pre-commit hook 以 1 結束）：失敗的步驟是「建立 commit 與 tag」，而且工作目錄
# 已經還原（LKAIKitInfo.swift 回到 HEAD 的內容）；本機與 remote 都沒有新的 commit 或 tag，沒有建立 Release
test_release_commit_failure_restores_the_version_file() {
  fixture_version_bump
  release_mode
  mkdir -p "$TEST_REPO/.git/hooks"
  printf '#!/bin/sh\necho "pre-commit 故意失敗" >&2\nexit 1\n' >"$TEST_REPO/.git/hooks/pre-commit"
  chmod +x "$TEST_REPO/.git/hooks/pre-commit"

  run_release

  assert_failed_with_step "建立 commit 與 tag"
  assert_file_contains "$TEST_STDERR" "pre-commit 故意失敗" "失敗要來自 pre-commit hook（沒有這一行，測試沒有走到 git commit）"
  assert_equals "" "$(repo_git status --porcelain)" "工作目錄要是乾淨的（版號檔已還原）"
  assert_equals "0.1.0" "$("$BASH" "$RELEASE_DIR/package-version.sh" get "$TEST_REPO/$VERSION_FILE_PATH")" "版號檔回到 HEAD 的內容"
}

# ---------------------------------------------------------------------------
# git 指令失敗時的處理、被訊號中止時的 lkai stderr
# ---------------------------------------------------------------------------

# run_release_with_failing_git <git 的引數的開頭> [<退出碼>]：執行 release.sh，但 PATH 最前面有一個 git 包裝：
# 引數以 <git 的引數的開頭>（例如 "tag --list"）開頭時，印一行訊息並以 <退出碼>（預設 1）結束，其他情況
# exec 真正的 git。真正的 git 的路徑在改 PATH 之前記下；包裝只在 release.sh 執行期間生效，
# fixture 與之後的檢查都用真正的 git
run_release_with_failing_git() {
  local real_git wrapper_dir="$TEST_TMP/git-wrapper"
  real_git="$(command -v git)" || fail "找不到 git"
  mkdir -p "$wrapper_dir"
  cat >"$wrapper_dir/git" <<WRAPPER_EOF
#!/bin/sh
case "\$*" in
  "$1"*)
    echo "測試用的 git 包裝：git \$* 故意失敗" >&2
    exit ${2:-1}
    ;;
esac
exec "$real_git" "\$@"
WRAPPER_EOF
  chmod +x "$wrapper_dir/git"
  PATH="$wrapper_dir:$PATH" run_release
}

# git tag --list 失敗：版本 tag 列不出來時不能當成「沒有 tag」繼續。repo 有比目前版號（0.1.0）大的 tag 0.2.0，
# 列得出來時會被「有更大的 tag」擋下；列不出來時也要在「讀取版號」失敗（失敗的原因是列不出 tag，不是偵測到更大的 tag）
test_release_fails_when_listing_the_tags_fails() {
  new_release_repo 0.1.0
  make_version_tag 0.2.0
  finish_fixture

  run_release_with_failing_git "tag --list"

  assert_failed_with_step "讀取版號"
  assert_file_contains "$TEST_STDERR" "測試用的 git 包裝：git tag --list 故意失敗" "包裝要真的被呼叫到"
  assert_file_not_contains "$TEST_STDERR" "更大的版本 tag" "失敗的原因是列不出 tag"
  assert_no_lkai_request
}

# 照原樣發佈（目前版號 0.1.0 沒有 tag）時，版本 tag 0.0.9 指向 tree：找上一版時解析不了它，不能當成「不是祖先」
# 而略過；在「讀取版號」失敗，訊息寫出那個 tag，沒有 AI 請求，沒有任何改變
test_release_as_is_fails_when_a_version_tag_points_to_a_tree() {
  new_release_repo 0.1.0
  repo_git tag 0.0.9 "$(repo_git rev-parse 'HEAD^{tree}')" || fail "無法建立指向 tree 的 tag"
  finish_fixture

  run_release

  assert_failed_with_step "讀取版號"
  assert_file_contains "$TEST_STDERR" "0.0.9" "訊息要寫出那個 tag"
  assert_no_lkai_request
  assert_has_line "$TEST_STDOUT" "計畫：release-as-is"
  assert_equals "0" "$(grep -c '^上一版：' "$TEST_STDOUT")" "找上一版失敗時上一版是未知的，報告不印「上一版：」那一行（不是「（無）」）"
}

# 找上一版時，git merge-base --is-ancestor 出錯（退出碼 2，不是 0 或 1；退出碼 1 才是「不是祖先」）：
# 不能當成「不是祖先」而略過，要在「讀取版號」失敗。tag 0.0.9 在 HEAD，是 HEAD 的祖先，沒有出錯時上一版就是它
test_release_as_is_fails_when_the_ancestor_check_errors() {
  new_release_repo 0.1.0
  make_version_tag 0.0.9
  finish_fixture

  run_release_with_failing_git "merge-base --is-ancestor " 2

  assert_failed_with_step "讀取版號"
  assert_file_contains "$TEST_STDERR" "測試用的 git 包裝：git merge-base --is-ancestor" "包裝要真的被呼叫到"
  assert_no_lkai_request
  assert_has_line "$TEST_STDOUT" "計畫：release-as-is"
  assert_equals "0" "$(grep -c '^上一版：' "$TEST_STDOUT")" "找上一版失敗時上一版是未知的，報告不印「上一版：」那一行（不是「（無）」）"
}

# 補建 Release 時（tag 0.1.1 沒有 Release，就在 HEAD），另一個版本 tag 0.1.0 指向 tree：找補建的上一版時解析不了它，
# 失敗的步驟是「補建 Release」；沒有 AI 請求，沒有建立 Release，沒有任何改變
test_release_repair_fails_when_a_version_tag_points_to_a_tree() {
  new_release_repo 0.1.1
  make_version_tag 0.1.1 no-release
  repo_git tag 0.1.0 "$(repo_git rev-parse 'HEAD^{tree}')" || fail "無法建立指向 tree 的 tag"
  finish_fixture
  release_mode

  run_release

  assert_failed_with_step "補建 Release"
  assert_file_contains "$TEST_STDERR" "0.1.0" "訊息要寫出那個 tag"
  assert_no_lkai_request
}

# 升級等級的請求進行中收到 TERM，lkai 已經把 stderr 寫進收 stderr 的檔案（假的 lkai 先送訊號、再寫 stderr，
# release.sh 的 trap 要等 lkai 結束才執行，所以檔案已經寫完）：那段 AI 的文字不能遺失，要在 GitHub Actions 中
# 以 ::stop-commands::<token> 與 ::<token>:: 包起來印出；報告仍有失敗的步驟
test_release_signal_during_a_request_keeps_the_stderr_of_lkai() {
  fixture_version_bump
  export GITHUB_ACTIONS=true
  export FAKE_LKAI_SIGNAL_PARENT=TERM
  export FAKE_LKAI_BUMP_STDERR=$'Error: cancelled\n::add-mask::x'

  run_release

  assert_exit_code 1 "release.sh 的退出碼"
  assert_has_line "$TEST_STDOUT" "失敗的步驟：判斷升級等級"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "Error: cancelled"
  assert_wrapped_in_stop_commands "$TEST_STDERR" "::add-mask::x"
  assert_line_count "$TEST_STDERR" "::add-mask::x" 1
  assert_equals "1" "$(grep -c '^::stop-commands::' "$TEST_STDERR")" "lkai 的 stderr 只包一次"
  assert_repo_untouched
  assert_no_release_created
}
