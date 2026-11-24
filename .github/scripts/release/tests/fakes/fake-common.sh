#!/usr/bin/env bash
# fake-common.sh：假的 lkai、gh、swift 共用的函式，由三個假指令載入，不單獨執行。
#
# - 假指令把「收到的引數」「收到的 prompt」與「Release 紀錄」寫在 FAKE_LOG_DIR，測試再去檢查。
# - 只記錄引數與 prompt 檔案，不讀、也不記錄任何環境變數（特別是 API 金鑰），
#   所以 script 若把金鑰放進命令列引數，測試才看得出來。
#
# FAKE_LOG_DIR 內的檔案：
#   calls.log                     每次呼叫一行，依先後排列：lkai bump-level、lkai release-notes、lkai -v、
#                                 gh release-list、gh release-create <tag>、swift build、swift show-bin-path
#   lkai-<種類>-<n>.args          第 n 次 lkai 請求的引數，一行一個；<種類> 是 bump-level 或 release-notes
#   lkai-<種類>-<n>.prompt        第 n 次請求收到的 prompt 檔案的複本
#   gh-release-list-<n>.args、gh-release-create-<n>.args、swift-build-<n>.args  各指令的引數
#   releases/<tag>/               這個 tag 的 Release 紀錄（gh release list 列出這些 tag）
#     title、notes                Release 的標題與內容
#
# 寫法的限制：相容 bash 3.2，只用 BSD 與 GNU 都有的寫法。

# fake_require_log_dir <指令名稱>：FAKE_LOG_DIR 沒有設定或不存在時，印出訊息並以 70 結束
fake_require_log_dir() {
  if [ -z "${FAKE_LOG_DIR:-}" ] || [ ! -d "$FAKE_LOG_DIR" ]; then
    echo "測試用的 $1：FAKE_LOG_DIR 沒有設定或資料夾不存在（測試要先呼叫 use_fakes）" >&2
    exit 70
  fi
}

# fake_write_args_file <檔案> [<引數>...]：把引數一行一個寫進檔案
fake_write_args_file() {
  local file="$1" arg
  shift
  : >"$file"
  for arg in "$@"; do
    printf '%s\n' "$arg" >>"$file"
  done
}

# fake_next_index <前綴>：印出下一個還沒用過的序號（從 1 開始），依 FAKE_LOG_DIR 內的 <前綴>-<n>.args 計算
fake_next_index() {
  local n=1
  while [ -e "$FAKE_LOG_DIR/$1-$n.args" ]; do
    n=$((n + 1))
  done
  printf '%s\n' "$n"
}

# fake_log_call <文字>：在 calls.log 加一行
fake_log_call() {
  printf '%s\n' "$1" >>"$FAKE_LOG_DIR/calls.log"
}
