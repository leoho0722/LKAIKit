派工方式依 design「平行實作沿用兩個 git worktree」：

- 第 1 組由 sonnet 在 `.worktrees/sonnet` 實作。
- 第 2 組由 haiku 在 `.worktrees/haiku` 實作。
- 建置、測試、反向檢查與合併都由主對話執行。

測試的做法分兩種：

- 1.1、1.2、2.2 是行為不變的搬移，依 TDD 的 Regression 以既有測試把關，不改期望值。
- 2.1 是新行為：先寫測試，主對話觀察到測試失敗後再實作。2.3 是既有行為的回歸測試，修改前就要通過。

## 1. LKAICore 的共同流程

- [x] 1.1 依 design「串流的背景 task 只在 LKAIChatStream.init(producing:) 建立」與「streamFailure(for:isCancelled:) 一併判斷取消」，完成以下改動：
  - `LKAIChatStream` 新增 `package init(producing:)`。生產端只拿到交出事件的 closure；建立唯一的 task，正常返回時 `finish()`、丟錯時 `finish(throwing:)`，只由 `onTermination` 取消，不存進屬性。
  - `LKAnthropicClient.stream(_:)` 改用它執行原本的 `run`：`run` 的參數由 continuation 改為交出事件的 closure，`relayEvents` 也一樣。
  - 偏離 ios-dev-kit `Task` 規則的 `- Note:` 移到這個 init，`stream(_:)` 只保留「釋放串流才會取消請求」那一則。
  - `LKAIError.streamFailure(for:)` 改為 `streamFailure(for:isCancelled:)`，`LKAIChatStream` 與 `LKAIHTTPLines` 的迭代器改為傳入 `Task.isCancelled`。

  驗證：`swift test` 全部通過且零警告，測試的期望值沒有修改。主對話依 design Implementation Contract 的反向檢查表，做 `onTermination` 與 `isCancelled` 兩項。
- [x] 1.2 [after: 1.1] 依 design「SSE 對話的共同流程以 LKAIServerSentEventChatStreaming 的 extension 提供」「每條串流的事件狀態與結束判斷由供應商的 mapper 持有」「snake_case JSON 的解碼設定收成 LKAISnakeCaseJSON」，完成以下改動：
  - 在 `Sources/LKAICore/Chat/` 新增 `LKAIServerSentEventChatStreaming`（含 `makeStream(for:)` 的六個步驟）與 `LKAIServerSentEventMapping`。
  - 在 `Sources/LKAICore/Networking/` 新增 `LKAISnakeCaseJSON`。
  - `LKAnthropicStreamState` 遵循 mapping：在 `handle(_:)` 內完成解碼、`error` 事件與 `message_stop`，回傳 `[LKAIChatStreamEvent]`；`apply(_:)` 與 `makeCompletion()` 改為 private。
  - `LKAnthropicClient` 遵循 streaming，滿足要求的成員宣告為 `package`：
    - `stream(_:)` 只有 `makeStream(for: request)` 一行。
    - `makeURLRequest(for:)` 的第一行是 `try refusalFallback.validate()`，`///` 寫明它回傳帶金鑰的請求。
    - `httpError(statusCode:headers:body:)` 是不讀取內容的純函式。
    - 移除 `run`、`relayEvents`、`decodeEvent`。
  - `LKAnthropicStreamEvent.init(data:)` 與 `LKAnthropicErrorBody.init?(text:)` 改用 `LKAISnakeCaseJSON`。

  驗證：
  - `swift test` 全部通過且零警告，測試的期望值沒有修改。
  - `grep` 確認 Implementation Contract 的「完成後的狀態」：`Task {`、`JSONDecoder()` 的位置，以及 `LKAnthropicClient` 沒有被移除的方法。
  - 主對話做反向檢查表的 `request.validate()` 一項。

## 2. LKAITestSupport

- [x] 2.1 依 design「替身第二次 fetch 記錄測試失敗，並新增 LKAITestSupportTests」，讓 `LKAIMockHTTPClient.fetch(_:)` 在累計第二次以上的請求時，於鎖外以 `Issue.record` 記錄問題。設定了 `failFetch` 時同樣記錄，原本回傳或丟出的結果不變。
  - 先在 `Package.swift` 新增測試 target `LKAITestSupportTests`，依賴 `LKAITestSupport` 與 `LKAICore`。
  - 再在 `Tests/LKAITestSupportTests/LKAIMockHTTPClientTests.swift` 寫兩個測試，然後才實作：
    - 第二次 `fetch` 記錄問題，以參數涵蓋「推送了逐行內容」與「設定了 `failFetch`」兩種設定：`withKnownIssue` 的 body 內以 `do`／`catch` 存下第二次 `fetch` 的錯誤，`matching:` 只接受 `.unconditional`，錯誤的 `#expect` 寫在 `withKnownIssue` 之外。
    - 只 `fetch` 一次時不記錄問題，並回傳設定的狀態碼。

  驗證：主對話先觀察到第二次 `fetch` 的測試在實作前以「Known issue was not recorded」失敗，實作後通過；完整 `swift test` 通過且零警告。
- [x] 2.2 依 design「與供應商無關的測試 helper 提前放進 LKAITestSupport」，搬移與供應商無關的測試 helper：
  - 新增 `LKAIChatClientProtocolTestSupport`：`CallMode`、`StreamOutcome`（明寫 `Sendable`）、`collectOutcome(from:request:onEvent:)`、`callError(on:request:mode:)`、`receiveFirstEvent(of:request:)`。
  - 新增 `LKAITestWaiting`：`waitUntil(_:)`。
  - `LKAnthropicClientTestSupport` 只留 Anthropic 專屬的成員。
  - `LKAnthropicClientCancellationTests` 的 `invokeError(on:)` 改用 `callError(on:request:mode:)`，`waitUntil(_:)` 與 `receiveFirstEvent(of:)` 改用搬過去的版本。
  - `LKAIAnthropicTests` 各檔的呼叫處跟著修改。

  驗證：
  - `swift test` 全部通過且零警告，LKAIAnthropic 仍是 43 個測試，測試名稱與期望值不變。
  - `Tests/` 內的 `spectra-scenario:` 行排序後與修改前逐行相同。
- [x] 2.3 [after: 2.2] 依 design Implementation Contract 的表列分支，在 `LKAnthropicClientErrorTests` 補兩個既有行為的回歸測試，以 `LKAIMockHTTPClient` 的 `finish(throwing:)` 送出連線中斷：
  - `stream_送出文字後連線中斷_先交出文字再丟出transport且保留底層錯誤代碼`：替身推送 `message_start`、文字區塊與 `Hel` 之後，以 `.transport` 結束。預期先收到 `.textDelta("Hel")`，再丟出同一個 `URLError` 代碼的 `.transport`。
  - `stream與invoke_讀取錯誤內容時連線中斷_丟出transport且保留底層錯誤代碼`：替身回應狀態碼 500，錯誤內容讀到一半以 `.transport` 結束。預期兩種呼叫方式都丟出同一個代碼的 `.transport`。

  驗證：兩個測試在修改前的實作上就通過（主對話執行），完整 `swift test` 通過且零警告，LKAIAnthropic 為 45 個測試。

## 3. 文件與驗收

- [x] 3.1 依 design「config.yaml 的指標改為同時指向本 change」，把 `docs/spectra/config.yaml` API 演進規則的指標換成 design 引用的文字（主對話）。

  驗證：`spectra instructions proposal --change "01-extract-chat-stream-skeleton" --json` 回傳的 context 含有新的指標。
- [x] 3.2 [after: 1.2, 2.1, 2.3, 3.1] 合併兩組任務後的整體驗收（主對話）：依 design Implementation Contract 的「驗收」逐項執行，並完成反向檢查表剩下的四項（吞掉逐行讀取的錯誤、讀不到錯誤內容、送出兩次 `fetch`、拿掉 `Issue.record`）。每一項的執行結果記錄在本任務下方。

  驗證：每一項結果都符合 Implementation Contract 的描述，包括共 118 個測試，以及 `LKAIKit-Package` 的 iOS 測試建置只有既有的 `Process` 錯誤。

  執行結果（2026-11-22，功能分支 `16acfbd`，主對話執行）：

  - **建置與測試**：`swift package clean` 後 `swift build`、`swift build --build-tests` 與 `swift test` 都零警告。
    - Swift Testing 共 118 個通過：LKAICore 62、LKAIAnthropic 45、LKAIKitCLI 7、LKAIKit 2、LKAITestSupportTests 2。
    - LKAITestSupportTests 的第二次 `fetch` 測試，兩組參數都記到預期的問題。
    - 2 個實際 API 測試因沒有金鑰而略過。
  - **spectra-scenario 標記**：`Tests/` 內共 93 行，排序後與修改前逐行相同。
  - **`swift package dump-package`**：
    - `LKAITestSupport` 只依賴 `LKAICore`，不屬於任何 product。
    - 從 `LKAIKit` 只走得到 `LKAIKit`、`LKAIAnthropic`、`LKAICore`。
    - products 只有 `LKAIKit` 與 `lkai`。
    - `LKAITestSupportTests` 依賴 `LKAITestSupport` 與 `LKAICore`。
  - **XcodeBuildMCP（iPhone 17 模擬器）**：
    - `LKAIKit` scheme 建置成功、零警告。
    - `LKAIKit-Package` 建置測試的錯誤只有 `LKAICommandTests.swift` 既有的 `Process` 兩則，零警告。
    - `LKAITestSupport` 的三個檔案與 `LKAIMockHTTPClientTests.swift` 都有編譯，沒有錯誤。
    - 驗收後 session 的 scheme 已改回 `LKAIKit`。
  - **config.yaml 的指標**：`spectra instructions proposal` 回傳的 context 含有新的指標。
  - **反向檢查**：七項都在暫時改壞後觀察到預期的測試失敗，並已還原。前三項在 `wt/sonnet` 上執行，其餘在功能分支上執行。
    - 拿掉 `init(producing:)` 的 `onTermination` 取消：「取消迭代的 task」與「釋放串流」兩個測試因底層請求沒被取消而失敗。
    - `streamFailure(for:isCancelled:)` 忽略 `isCancelled`：`LKAIChatStreamTests` 與 `LKAIHTTPLinesTests` 的取消測試，每組參數都失敗。
    - 拿掉 `makeStream(for:)` 的 `request.validate()`：不合法請求的測試每組參數都失敗，錯誤種類不對，請求也被送出。
    - 吞掉逐行讀取的錯誤：`stream_送出文字後連線中斷_先交出文字再丟出transport且保留底層錯誤代碼` 失敗。
    - 讀不到錯誤內容時改用空字串：`stream與invoke_讀取錯誤內容時連線中斷_丟出transport且保留底層錯誤代碼` 兩種呼叫方式都失敗。
    - 送出兩次 `fetch`：`stream_回應沒有任何事件_丟出無效回應錯誤` 因替身記錄的問題而失敗。
    - 拿掉替身的 `Issue.record`：第二次 `fetch` 的測試兩組參數都以「Known issue was not recorded」失敗。
    - 另外加做一項：替身第一次 `fetch` 就記錄問題時，`fetch_只呼叫一次_不記錄問題並回傳設定的狀態碼` 失敗。
  - **還原後**：完整 `swift test` 再跑一次，118 個通過、零警告。
