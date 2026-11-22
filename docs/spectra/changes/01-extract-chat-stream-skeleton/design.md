## Context

`add-chat-abstraction-anthropic` 完成了共用對話抽象與 Anthropic 實作。它封存後的 design 在 Open Questions 建議：第二家供應商的 change 開始前，先把 `stream(_:)` 的共同流程抽進 `LKAICore`，並一併處理實作審查留下的四項。下一家是 OpenAI（`02-add-openai-provider`），使用者在 2026-11-22 的討論中決定把抽出共同流程拆成本 change，先做。規劃完成後經 fable 與 opus 兩位審查者審查，本文件已納入查證成立的修正。

目前的狀態（2026-11-22 讀取原始碼）：

- **背景 task**：`LKAnthropicClient.stream(_:)` 在 `AsyncThrowingStream` 的建構 closure 內建立一個 `Task` 執行請求，只由 `onTermination` 取消。`LKAIHTTPClient` 的 `makeLines(from:)` 以同樣方式建立讀取位元組的 task。
- **共同流程整段寫在 `LKAnthropicClient`**：
  - `run(_:continuation:)` 依序檢查請求、檢查備援設定、組出請求、送出。非 2xx 時交給 `httpError(for:)`，由它讀錯誤內容，依 `error.type` 分類，不認得時改用 `LKAIError(httpStatusCode:retryAfter:)` 的預設分類。
  - `relayEvents(from:to:)` 逐行解析 SSE、解碼事件，並在這裡處理 `error` 事件（丟出對應的錯誤）與 `message_stop`（交出結束事件並停止讀取）。其餘事件交給 `LKAnthropicStreamState.apply(_:)`。
- **`LKAIError.streamFailure(for:)`**：由 `LKAIChatStream` 與 `LKAIHTTPLines` 的迭代器呼叫，兩處都先自己判斷 `Task.isCancelled`。
- **JSON 解碼**：`LKAnthropicStreamEvent.init(data:)` 與 `LKAnthropicErrorBody.init?(text:)` 各自建立 `JSONDecoder` 並設定 `.convertFromSnakeCase`。
- **測試 helper**：
  - `LKAnthropicClientTestSupport` 混著 Anthropic 專屬的成員（`validRequest`、SSE 事件建構、`makeClient(events:)`、`lines(of:)`、`finishedEvent`）與與供應商無關的成員（`CallMode`、`StreamOutcome`、`collectOutcome(from:onEvent:)`、`callError(on:with:mode:)`）。
  - `LKAnthropicClientCancellationTests` 另有 private 的 `waitUntil(_:)`、`receiveFirstEvent(of:)`、`invokeError(on:)`。
- **替身第二次 `fetch`**：`LKAIMockHTTPClient` 只丟出 `.invalidResponse`。只比對錯誤種類的測試，會把「供應商誤送兩次請求」當成通過。
- **測試與內部實作的關係**（grep 確認）：
  - `LKAIAnthropicTests` 判斷 `.invalidResponse` 時只比對種類，不比對 `reason` 文字。
  - 沒有測試直接使用 `LKAnthropicStreamState`、`LKAnthropicStreamEvent`、`LKAnthropicErrorBody` 或 `LKAnthropicClient` 的 private 方法。
  - 每個測試或參數組合各自建立替身，沒有測試合法地 `fetch` 兩次。
- **測試數**：2026-11-22 封存上一個 change 時量測，Swift Testing 共 114 個：LKAICore 62、LKAIAnthropic 43、LKAIKitCLI 7、LKAIKit 2。

各供應商串流格式的查證：

- **OpenAI Responses API**：討論時依官方文件（Context7 收錄的 OpenAI API 參考，2026-11-22）確認：
  - 文字在 `response.output_text.delta`，拒答文字在 `response.refusal.delta`。
  - 串流以 `response.completed`、`response.incomplete` 或 `response.failed` 結束。
  - 錯誤以 `error` 事件送出。
- **Gemini `streamGenerateContent`**：fable 依官方文件查證，結束原因 `finishReason` 是 `Candidate` 的欄位，與 `content.parts[].text` 在同一則回應裡，沒有獨立的結束事件。所以同一則 SSE 事件可能同時帶文字與結束；這點尚未以實際回應驗證。

2026-11-22 在 scratchpad 以 Swift 6.4.2、`swift-tools-version: 6.2`、Swift 6 語言模式實測：

- **typed throws 的 closure**：`package init(producing: @escaping @Sendable (_ yield: (Event) -> Void) async throws(自訂錯誤) -> Void)`，以 `{ yield throws(自訂錯誤) in ... }` 呼叫，建置零警告。生產端只拿到交出事件的 closure，拿不到 `Continuation`。
- **`package` protocol 的遵循**：
  - 另一個模組的 `public struct` 遵循 `package` protocol 時，滿足要求的成員必須宣告成 `package`，否則編譯錯誤（must be declared package）。
  - 要求的回傳型別寫成 `any <protocol>` 時，實際的狀態型別可以維持 internal；改用 associated type 時，狀態型別也必須是 `package`。
  - 對 existential 的 `var` 呼叫 `mutating` 方法可以編譯。
- **共同流程的寫法**：共同流程寫在 `package` protocol 的 `package` extension，由 `public` 的 `stream(_:)` 一行轉呼叫，可以編譯並通過測試。`public` protocol 的要求不能只由 `package` extension 滿足（記在 `add-chat-abstraction-anthropic` 的 Context），所以每家供應商仍要寫這一行。
- **一般 target `import Testing`**：
  - 一般的 `.target` 可以 `import Testing`，`Package.swift` 不需要任何設定，`swift package clean` 後 `swift build` 零警告。
  - 它的 helper 內 `#expect` 失敗時，問題記在呼叫端傳入的 `sourceLocation`。
  - 在 `init(producing:)` 建立的非結構化 `Task` 內呼叫 `Issue.record`，問題仍記在當下的測試上。
- **`withKnownIssue` 的語意**：
  - body 丟出的錯誤本身就會被當成已知問題。
  - 加上 `matching:` 並只接受 `issue.kind` 為 `.unconditional`，就只接受 `Issue.record` 記錄的問題。
  - body 沒有記錄任何問題時，測試以「Known issue was not recorded」失敗。
- **跨模組的 `Sendable`**：沒有明寫 `Sendable` 的 `package struct` 從另一個模組作為 `Task` 的回傳值，可以編譯。

以 XcodeBuildMCP 對 iOS 26.5 模擬器實測目前的 `main`：

- `LKAIKit-Package` scheme 一般建置成功，但只建置 product 的 target，不含 `LKAITestSupport`。
- 建置測試（build for testing）會失敗，兩個錯誤都是 `LKAIKitCLITests/LKAICommandTests.swift` 的 `Process` 在 iOS 不存在；這是既有狀態。`LKAITestSupport` 在這次建置中被編譯，沒有錯誤。

## Goals / Non-Goals

**Goals:**

- 每條串流的背景 task 只在 `LKAICore` 的一處建立，取消接線只寫一次，供應商碰不到它。
- 以 SSE 串流回答的供應商只需要提供四樣東西：組出請求、分類錯誤內容、把每則 SSE 事件對應成對話事件，以及送出請求的 HTTP client。其餘都由 `LKAICore` 處理：建立 task、送出、讀取錯誤內容與預設分類、SSE 迴圈、交出結束事件就停止讀取、沒有結束事件時的錯誤。
- 處理封存 design 的 Open Questions 留下的四項。
- 行為不變：capability 層級可觀察的行為完全不變，所有既有測試的期望值不變，spec 與 spectra-scenario 標記不變。

**Non-Goals:**

- OpenAI 的實作，由 `02-add-openai-provider` 負責。
- `LKAIHTTPClient.makeLines(from:)` 讀取位元組的 task 不改用 `init(producing:)`：它的元素是 `String`，錯誤轉換屬於 `LKAIHTTPLines`；而且只有這一處，寫在 `LKAICore` 內，供應商不會重寫。
- 公開 API 不變：`LKAIChatStream.init(_:)`、`LKAIChatClientProtocol`、`LKAIError` 的 case 都不改；不新增錯誤種類，也不在 `serviceUnavailable` 加等待時間。
- 不為共同流程另寫 `LKAICoreTests`：分支由 `LKAIAnthropicTests` 的測試把關，見 Implementation Contract 的對照，其中兩個分支由任務 2.3 補上回歸測試。測試的長期位置留在 Open Questions。
- SSE 分框的測試 helper 不搬：`SSEEvent` 的 `name`／`data` 與 `lines(of:)` 和 Anthropic 的事件建構寫在同一個型別裡。等 OpenAI 的測試需要時再拆，見 Open Questions。
- 不重跑實際 API 測試：送出的請求內容不變，由 `LKAnthropicClientTests` 比對標頭與內容的測試把關。
- 只 `import LKAIKit` 的使用端檢查 package，延後到 BuyLedger 整合。

## Decisions

### 串流的背景 task 只在 LKAIChatStream.init(producing:) 建立

`LKAIChatStream` 新增：

```swift
package init(
    producing produce: @escaping @Sendable (
        _ yield: (LKAIChatStreamEvent) -> Void
    ) async throws(LKAIError) -> Void
)
```

- **task 的生命週期**：
  - 在 `AsyncThrowingStream` 的建構 closure 內建立一個 `Task`，以 `{ continuation.yield($0) }` 呼叫 `produce`。
  - `produce` 正常返回時 `finish()`，丟出錯誤時 `finish(throwing:)`。
  - `continuation.onTermination` 取消這個 task；task 不存進任何屬性。
- **生產端碰不到取消接線**：生產端只拿到交出事件的 closure，無法自行 `finish`，也無法改寫 `onTermination`。改寫 `onTermination` 會蓋掉唯一的取消接線，正是本 change 要消除的計費風險。這個寫法已實測可行，見 Context。
- **說明移到 init**：原本寫在 `LKAnthropicClient.stream(_:)` 的 `- Note:`，也就是偏離 ios-dev-kit「`Task { }` 只在兩個地方建立」的理由與生命週期限制，移到這個 init。`stream(_:)` 只保留「釋放串流才會取消請求」那一則。

**與上一個 change 決策的關係**：這個決策只改變 `add-chat-abstraction-anthropic` 的決策「以自訂 AsyncSequence 提供 typed throws 的串流」中「生產端 task 的擁有權」第一點。

- task 原本由「供應商的 `stream(_:)`」建立，改由這個 init 建立。
- 「每條串流一個 task、只由 `onTermination` 取消、不存進屬性」的規則不變。
- 該決策其餘內容仍然有效：自訂 AsyncSequence、錯誤轉換規則、`break` 但仍持有串流時不取消。
- `Supersedes` 是整個決策一個旗標，標了會讓整個決策顯示為不再有效，所以不標。之後的 change 由 `docs/spectra/config.yaml` 的指標讀到本 change，見最後一個決策。

考慮過的替代方案：

- **每家供應商繼續自己建立 task**：取消接線要每家各寫一次，漏寫時 App 釋放串流後請求仍繼續計費。這正是 Open Questions 要解決的問題，否決。
- **把整個 `Continuation` 交給生產端**：生產端可以改寫 `onTermination` 或提早 `finish`，只能靠說明約束，否決。
- **只在下一個決策的共同流程內建立 task，不提供 `init(producing:)`**：task 的規則屬於串流型別本身，不走 SSE 的供應商也能用這個 init，所以分成兩層。例如 Ollama 的原生串流是 NDJSON，fable 的認知，尚未查證。

### SSE 對話的共同流程以 LKAIServerSentEventChatStreaming 的 extension 提供

`Sources/LKAICore/Chat/` 新增 `package protocol LKAIServerSentEventChatStreaming: Sendable`，要求如下：

| 要求 | 用途 |
| --- | --- |
| `var httpClient: any LKAIHTTPClientProtocol { get }` | 送出請求的 HTTP client |
| `func makeURLRequest(for request: LKAIChatRequest) throws(LKAIError) -> URLRequest` | 檢查供應商自己的設定，例如 Anthropic 的拒答備援，再組出帶金鑰的請求 |
| `func httpError(statusCode: Int, headers: [String: String], body: String) -> LKAIError?` | 依供應商的錯誤格式分類非 2xx 回應；認不得時回傳 nil |
| `func makeEventMapper() -> any LKAIServerSentEventMapping` | 每條串流建立一份新的事件對應狀態 |

`package` extension 提供 `makeStream(for request: LKAIChatRequest) -> LKAIChatStream`，以 `init(producing:)` 依序執行：

1. `try request.validate()`。這是 `chat-client` spec「Chat request content」的共用規則，所有供應商相同。
2. `try makeURLRequest(for:)`。
3. `try await httpClient.fetch(_:)`。
4. 狀態碼不在 200...299 時：
   - 以 `try await response.readErrorBody()` 讀出錯誤內容。
   - 丟出 `httpError(statusCode:headers:body:)` 的結果；結果為 nil 時，改丟 `LKAIError(httpStatusCode:retryAfter:)` 以 `headers["retry-after"]` 算出的預設分類。這也是 `chat-client` spec「Default HTTP status classification」的共用規則。
5. 以 `LKAIServerSentEventParser` 逐行解析 `response.lines`，每則 SSE 事件交給 mapper 的 `handle(_:)`，依序交出它回傳的對話事件：
   - 交出 `.finished` 後立即返回，同一個陣列裡在它之後的事件不交出，也不再讀取。呼叫端離開後回應被釋放，底層傳輸跟著取消。
   - mapper 或逐行讀取丟出錯誤時，已交出的文字保留，串流以該錯誤結束。
6. 讀完都沒有 `.finished` 時，先呼叫 `parser.finish()`，再丟出 `.invalidResponse(reason: "Stream ended before a finish event")`。

**供應商這一側的寫法**：

- **`stream(_:)`**：供應商的 `public func stream(_:)` 只寫 `makeStream(for: request)` 一行。
- **存取層級**：
  - `LKAnthropicClient` 滿足要求的成員宣告為 `package`，實測必須如此，見 Context。
  - `httpClient` 由 `private` 改為 `package`，`customMirror` 仍然不放它。
  - `makeURLRequest(for:)` 的 `///` 寫明：它回傳帶金鑰的請求，只給共同流程使用。
- **錯誤分類改成純函式**：`httpError(statusCode:headers:body:)` 是純函式，不必透過替身就能測試。讀取錯誤內容的方式與 64 KiB 上限由共同流程統一處理，供應商不能自訂；目前三家都不需要。

**命名**：依 ios-dev-kit `coding-style.md` 的規則決定。

- 描述能力的 protocol 用 `-ing`，描述角色的用名詞加 `Protocol` 後綴。
- `Provider` 只用在「按需提供一個值、沒有業務邏輯」的型別，這裡不符合。
- `Mapper` 不是已定義的角色後綴。
- 兩個 protocol 描述的都是能力：「以 SSE 串流對話」與「把 SSE 事件對應成對話事件」，所以分別命名為 `LKAIServerSentEventChatStreaming` 與 `LKAIServerSentEventMapping`。
- 兩者都依賴 `LKAIChatRequest`、`LKAIChatStream` 與 `LKAIChatStreamEvent`，所以放 `Chat/`，不放只處理傳輸的 `Networking/`。

兩家對照如下，OpenAI 一欄依 Context 的查證：

| 要求 | Anthropic（本 change 改寫） | OpenAI（`02-add-openai-provider`） |
| --- | --- | --- |
| `makeURLRequest` | 檢查拒答備援設定；帶 `x-api-key`、`anthropic-version`、`anthropic-beta` | 帶 `Authorization: Bearer`；送出 Responses API 的內容 |
| `httpError` | 依 `error.type` 分類，不認得時回傳 nil | 依 `error.code` 區分額度用完與頻率限制 |
| mapper 交出文字 | `content_block_delta` 的 `text_delta` | `response.output_text.delta` |
| mapper 交出 `.finished` 或丟錯 | `message_stop`，依 `stop_reason` 決定 | `response.completed`、`response.incomplete`、`response.failed` |
| mapper 丟出串流中的錯誤 | `error` 事件 | `error` 事件 |

驗證順序與原本相同：先 `request.validate()`，再於 `makeURLRequest(for:)` 的第一行檢查備援設定，最後組出請求。

考慮過的替代方案：

- **以 closure 參數組成的建構函式**：例如 `LKAIChatStream.serverSentEvents(makeRequest:httpClient:httpError:mapper:)`。四個 closure 參數不易閱讀，也沒有地方寫每個要求的說明，否決。
- **mapper 用 associated type**：實測滿足要求的型別必須是 `package`，供應商的狀態型別就得從 internal 提高到 `package`，見 Context。改回傳 `any LKAIServerSentEventMapping`，每條串流多一次 existential，相對網路延遲可以忽略（估計，未量測），所以否決 associated type。
- **讓 protocol 直接提供 `stream(_:)` 的預設實作**：`public` protocol 的要求不能由 `package` extension 滿足，見 `add-chat-abstraction-anthropic` 的 Context 實測，否決。
- **`httpError(for: LKAIHTTPResponse) async throws(LKAIError) -> LKAIError`**：讀取內容與預設分類要每家各寫一次，否決。

### 每條串流的事件狀態與結束判斷由供應商的 mapper 持有

`Sources/LKAICore/Chat/` 新增 `package protocol LKAIServerSentEventMapping`：

```swift
mutating func handle(_ event: LKAIServerSentEvent) throws(LKAIError) -> [LKAIChatStreamEvent]
```

- **回傳值**：
  - 沒有要交出的事件時，回傳空陣列。
  - 交出結束事件時，`.finished` 放在陣列最後。
- **為什麼回傳陣列**：Gemini 的同一則事件可能同時帶最後一段文字與結束原因，見 Context。回傳陣列時可以依序交出 `.textDelta` 與 `.finished`，不必另外定義一個對應結果的型別。
- **不要求 `Sendable`**：mapper 在 task 內建立，只在那個 task 內使用。

`LKAnthropicStreamState` 改為遵循 `LKAIServerSentEventMapping`，這處理 Open Questions 的第二項：

- `handle(_:)` 先把 SSE 的 `data` 解碼成 `LKAnthropicStreamEvent`。解碼失敗時丟出 `.invalidResponse(reason: "Malformed stream event: ...")`，與原本的 `decodeEvent(from:)` 相同。
- **`error` 事件**：依 `error.type` 丟出對應的錯誤；不認得的類型丟出 `.serviceUnavailable(statusCode: 500)`。
- **`message_stop`**：以 `makeCompletion()` 組出結束資訊，回傳 `[.finished(結束資訊)]`。結束原因是拒答或不認得時，照原本丟出錯誤。
- **其他事件**：照原本的 `apply(_:)` 更新狀態，有文字時回傳 `[.textDelta(文字)]`，否則回傳空陣列。
- **整理後的結構**：
  - `apply(_:)` 與 `makeCompletion()` 改為 private。
  - `LKAnthropicClient` 不再有 `run`、`relayEvents`、`decodeEvent`。
  - `httpError` 改為上一個決策的純函式。

事件對應規則完全不變：`add-chat-abstraction-anthropic` 的決策「Anthropic 串流事件的對應規則」仍然有效，只是改由狀態型別執行。

考慮過的替代方案：新增 `.skip`／`.text`／`.finish` 三種對應結果的 enum。它與既有的 `LKAIChatStreamEvent` 重複，而且一則事件只能表達一種結果，放不進 Gemini「同一則事件帶文字與結束」的格式，否決。

### streamFailure(for:isCancelled:) 一併判斷取消

`LKAIError.streamFailure(for:)` 改為 `streamFailure(for error: any Error, isCancelled: Bool) -> LKAIError?`，這處理 Open Questions 的第一項：

- **新的取消判斷**：`isCancelled` 為 true 時一律回傳 nil。
- **其餘規則不變**：`CancellationError` 與 `.cancelled` 回傳 nil；其他 `LKAIError` 原樣回傳；其他錯誤轉成 `.invalidResponse`。
- **呼叫端**：`LKAIChatStream` 與 `LKAIHTTPLines` 的迭代器改為傳入 `Task.isCancelled`，不再自己先判斷。完整的轉換規則集中在一處，之後的呼叫端不會漏寫取消判斷。
- **存取層級**：維持 internal。

### snake_case JSON 的解碼設定收成 LKAISnakeCaseJSON

`Sources/LKAICore/Networking/` 新增沒有 case 的 `package enum LKAISnakeCaseJSON`，提供 `package static func decode<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value`，以 `.convertFromSnakeCase` 解碼 UTF-8 文字。這處理 Open Questions 的第三項：

- **改用它的地方**：`LKAnthropicStreamEvent.init(data:)` 與 `LKAnthropicErrorBody.init?(text:)` 改用它，`LKAIAnthropic` 不再自己建立 `JSONDecoder`。
- **使用規則**：型別的 `///` 寫明，snake_case 的供應商一律用它解碼，不自己建立 `JSONDecoder`。

考慮過的替代方案：

- **每個巢狀型別明寫 `CodingKeys` 的 raw value**：Anthropic 的解碼型別有 10 個 snake_case 鍵（2026-11-22 依原始碼計數），OpenAI 也是 snake_case，又要再寫一次。收成一處的程式碼較少，所以否決。
- **收成一處的限制**：它擋不住之後有人另外建立 `JSONDecoder`，由型別說明與 review 把關。
- **Gemini 不受影響**：依 `add-chat-abstraction-anthropic` 的對照表，Gemini 回應的欄位是 camelCase（例如 `promptTokenCount`），不會用到它。

### 與供應商無關的測試 helper 提前放進 LKAITestSupport

這處理 Open Questions 的第四項，依 ios-dev-kit `file-templates.md` 的 TestSupport 規則命名：

- **`Sources/LKAITestSupport/LKAIChatClientProtocolTestSupport.swift`**：沒有 case 的 `package enum`，對應的受測型別是 `LKAIChatClientProtocol`。成員：
  - `CallMode`：`stream`、`invoke`，`CaseIterable`、`Sendable`。
  - `StreamOutcome`：`events`、`error`。依本 repo 慣例明寫 `Sendable`；實測不寫也能跨模組作為 `Task` 的回傳值，見 Context。
  - `collectOutcome(from:request:onEvent:)`、`callError(on:request:mode:)`、`receiveFirstEvent(of:request:)`：接受 `any LKAIChatClientProtocol`。請求改由呼叫端傳入，因為合法請求的模型名稱屬於各供應商。
- **`Sources/LKAITestSupport/LKAITestWaiting.swift`**：沒有對應受測型別的主題命名空間 `package enum`，放 `waitUntil(_:)`。等待方式不變：最多等 2 秒，每 10 毫秒檢查一次，條件成立就返回；一直沒成立時等滿返回，由呼叫端的斷言失敗。
- **`LKAnthropicClientTestSupport`**：只留 Anthropic 專屬的 `validRequest`、SSE 事件建構、`makeClient(events:)`、`lines(of:)`、`finishedEvent`。
- **`LKAnthropicClientCancellationTests`**：
  - `invokeError(on:)` 與 `callError(on:request:mode:)` 的 `.invoke` 完全相同，改用後者。
  - `waitUntil(_:)` 與 `receiveFirstEvent(of:)` 改用搬過去的版本。
- 測試名稱、期望值與 spectra-scenario 標記都不變。

**提前搬移是刻意的例外**：上述 helper 目前都只有 `LKAIAnthropicTests` 使用，而取消相關的三個只有 `LKAnthropicClientCancellationTests` 一個測試型別使用。ios-dev-kit 規定只有一個測試型別使用的 helper 寫成它的 private 成員，`add-chat-abstraction-anthropic` 的任務 6.9 也曾依此把支援檔折回。

本 change 提前搬移的理由：

- 封存的 Open Questions 明列這幾類 helper 要在抽出共同流程時一起搬。
- 緊接著的 `02-add-openai-provider` 一開始就要用。

不搬的話，02 只能先在自己的測試照抄一份，之後再合併。

### 替身第二次 fetch 記錄測試失敗，並新增 LKAITestSupportTests

**替身的新行為**：

- **記錄問題**：`LKAIMockHTTPClient.fetch(_:)` 在鎖內記錄請求、取得累計的請求數與這次的結果；離開鎖後，累計已超過一次就以 Swift Testing 的 `Issue.record` 記錄問題，再回傳或丟出結果。
- **不論是否設定 `failFetch`**：設定了 `failFetch(with:)` 時同樣記錄，否則「連線失敗後誤重送」抓不到。
- **原本的行為不變**：設定了 `failFetch` 時丟出該錯誤；來源已交出過時丟出 `.invalidResponse`。
- **在鎖外記錄**：避免 `Issue.record` 同步執行測試的 `matching:` 判斷時，判斷內讀取 `requests` 而再次取得同一把不可重入的 `Mutex`。
- **`import Testing`**：`LKAITestSupport` 因此 `import Testing`；實測不需修改 `Package.swift`，見 Context。

這取代封存 Open Questions 原本的寫法「搬移 helper 時讓 helper 斷言 `requests.count == 1`」：記錄在替身上，沒有使用 helper 的測試也擋得住。

**新增測試 target `LKAITestSupportTests`**（使用者決定）：

- 依賴 `LKAITestSupport` 與 `LKAICore`。依 `add-chat-abstraction-anthropic` 的決策，測試檔直接 import 的模組都要列為依賴。
- **`LKAIMockHTTPClientTests` 的兩個測試**：
  - 第二次 `fetch` 記錄問題：以參數涵蓋兩種設定，一種推送了逐行內容，一種設定了 `failFetch`。
    - `withKnownIssue` 的 body 內以 `do`／`catch` 把第二次 `fetch` 的錯誤存進區域變數，`matching:` 只接受 `issue.kind` 為 `.unconditional` 的問題。
    - 錯誤的 `#expect` 寫在 `withKnownIssue` 之外。
    - 這樣寫，丟出的錯誤不會被當成已知問題；沒有 `Issue.record` 時，測試以「Known issue was not recorded」失敗，見 Context 的實測。
  - 只 `fetch` 一次時不記錄問題，並回傳設定的狀態碼。
- **收錄範圍**：只測替身自己會判定測試失敗、或會影響測試結論的行為，不為每個 helper 加測試。

**與上一個 change 決策的關係**：這只改寫決策「測試 target 依受測 target 增加 LKAIAnthropicTests」中「`LKAITestSupport` 不設測試 target」那一點。

- 當時的理由是它由 `LKAIAnthropicTests` 實際使用來驗證，但 Anthropic 的測試永遠只 `fetch` 一次，驗證不到這個新行為。
- 該決策其餘內容仍然有效，所以不標 `Supersedes`，理由同第一個決策。

**spec 不受影響**：

- `package-distribution` spec 的「Module dependency direction」明寫不含 `.testTarget`。
- 「Test support stays out of the library build」只限制 `LKAITestSupport` 的依賴，而 `Testing` 不是 target 依賴。

### config.yaml 的指標改為同時指向本 change

`docs/spectra/config.yaml` 的 API 演進規則目前要求新增供應商前先讀 `add-chat-abstraction-anthropic` 的 design。本 change 封存後，那份 design 有三處過時：

- 「生產端 task 的擁有權」寫 task 由供應商的 `stream(_:)` 建立。
- 「`LKAITestSupport` 不設測試 target」。
- Open Questions 的抽出共同流程那一項。

而 `spectra decisions` 只依 `Supersedes` 判斷決策是否有效，本 change 沒有標，見前面兩個決策。

所以把那一條改為：

> 新增供應商的 change 開始前，先讀 add-chat-abstraction-anthropic 與 01-extract-chat-stream-skeleton 封存後的 design：逐列核對前者 Context 的三家對照表，並處理兩者 Open Questions 留給下一家供應商的項目。以 SSE 串流回答的供應商一律遵循 `LKAIServerSentEventChatStreaming`，不自行建立 `Task`。前者「生產端 task 的擁有權」、「`LKAITestSupport` 不設測試 target」與 Open Questions 的抽出共同流程一項，以後者為準。

考慮過的替代方案：

- **修改封存的 design**：封存的內容記錄當時的決定，不回頭改，否決。
- **標 `Supersedes`**：理由見第一個決策，否決。

### 平行實作沿用兩個 git worktree

沿用 `add-chat-abstraction-anthropic` 的決策「平行實作時兩位實作者各用一個 git worktree」，worktree 放 `.worktrees/sonnet` 與 `.worktrees/haiku`，由主對話在各 worktree 建置、測試與合併。

- **sonnet 做第 1 組（1.1 → 1.2）**：它是風險最高的改寫：typed throws closure、`package` protocol 的存取規則，以及把 `error` 與 `message_stop` 併進狀態型別而行為不變。
- **haiku 做第 2 組（2.1、2.2 → 2.3）**：
  - 2.1 依本 design 寫明的測試寫法實作。
  - 2.2 是機械式搬移。
  - 2.3 只新增兩個測試。
- **兩組檔案不重疊**：第 1 組只改 `Sources/LKAICore` 與 `Sources/LKAIAnthropic`；第 2 組改 `Package.swift`、`Sources/LKAITestSupport` 與 `Tests/`。
- **主對話**：做 3.1 與 3.2。

## Implementation Contract

**capability 層級可觀察的行為完全不變**：App 看得到的 API、串流與非串流的事件、錯誤種類、送出的請求內容都與修改前相同。

唯一的文字差異：串流沒有結束事件就結束時，`.invalidResponse` 的開發者說明由「Stream ended before message_stop」改為「Stream ended before a finish event」。這段文字不在 spec 內，也沒有測試比對它，見 Context。

完成後的狀態：

- **`Task {` 只在兩處**：`Sources/` 內只出現在 `LKAICore/Chat/LKAIChatStream.swift` 的 `init(producing:)` 與 `LKAICore/Networking/LKAIHTTPClient.swift` 的 `makeLines(from:)`。這兩個檔案的 `///` 說明裡也會出現這個字樣。
- **`JSONDecoder()` 只在一處**：`Sources/` 內只出現在 `LKAICore/Networking/LKAISnakeCaseJSON.swift`。
- **`LKAnthropicClient`**：
  - 遵循 `LKAIServerSentEventChatStreaming`，`stream(_:)` 只有 `makeStream(for: request)` 一行。
  - 沒有 `run`、`relayEvents`、`decodeEvent`。
  - `makeURLRequest(for:)` 的第一行是 `try refusalFallback.validate()`，`- Throws:` 一併說明。
- **`LKAnthropicStreamState`**：遵循 `LKAIServerSentEventMapping`，`apply(_:)` 與 `makeCompletion()` 為 private。
- **`LKAIError`**：只有 `streamFailure(for:isCancelled:)`，舊的 `streamFailure(for:)` 已移除。
- **測試 helper**：
  - `LKAnthropicClientTestSupport` 不再有 `CallMode`、`StreamOutcome`、`collectOutcome`、`callError`。
  - `LKAnthropicClientCancellationTests` 不再有 `waitUntil`、`receiveFirstEvent`、`invokeError`。
- **新檔案的建立方式**：

| 檔案 | 建立方式 |
| --- | --- |
| `LKAIServerSentEventChatStreaming.swift` | `data/Service.swift` 的 Protocol 區，比照 `LKAIChatClientProtocol.swift`；共同流程寫在同檔的 `package` extension，刪掉 Implementation 區 |
| `LKAIServerSentEventMapping.swift` | 沒有對應樣板，手寫。它描述的是能力，不是 Service 或 Client 這類角色，ios-dev-kit 沒有能力式 protocol 的樣板 |
| `LKAISnakeCaseJSON.swift`、`LKAIChatClientProtocolTestSupport.swift`、`LKAITestWaiting.swift` | 沒有對應樣板，依 `file-templates.md` 檔頭規則、`formatting.md` 與 `coding-style.md` 手寫；兩個 TestSupport 依 `tests/Tests.swift` 一節的 TestSupport 規則 |
| `LKAIMockHTTPClientTests.swift` | `tests/Tests.swift` |

**共同流程的表列分支與把關的測試**：依 TDD 的 Regression，表內的分支都由測試覆蓋，既有測試的期望值不改。

| 共同流程的分支 | 把關的測試 |
| --- | --- |
| 請求不合法時不送出請求 | `LKAnthropicClientTests` 的 `stream與invoke_不合法的請求_丟出無效請求錯誤且不送出請求` |
| 備援設定不合法時不送出請求 | `LKAnthropicClientTests` 的 `stream與invoke_不合法的備援模型清單_丟出無效請求錯誤且不送出請求` |
| 非 2xx 依錯誤內容分類，認不得時用預設分類 | `LKAnthropicClientErrorTests` 的 `invoke_HTTP錯誤回應_依error類型分類為範例表的錯誤` |
| 送出請求時連線失敗 | `LKAnthropicClientErrorTests` 的 `stream與invoke_連線失敗_丟出transport且保留底層錯誤代碼` |
| 讀取錯誤內容時連線中斷 | 任務 2.3 新增：`LKAnthropicClientErrorTests` 的 `stream與invoke_讀取錯誤內容時連線中斷_丟出transport且保留底層錯誤代碼` |
| mapper 交出文字與結束事件 | `LKAnthropicClientStreamTests` 的 `stream_文字Hel與lo後正常結束_依序交出兩段文字與完成事件` |
| mapper 回傳空陣列 | `LKAnthropicClientStreamTests` 的 `stream_有思考區塊與ping_只交出文字區塊的文字後完成`、`stream_有signatureDelta與不認得的事件_略過後照常交出文字` |
| mapper 丟錯時保留已交出的文字 | `LKAnthropicClientErrorTests` 的 `stream_串流中途的error事件_先交出文字再以範例表的錯誤結束` |
| 逐行讀取途中連線中斷 | 任務 2.3 新增：`LKAnthropicClientErrorTests` 的 `stream_送出文字後連線中斷_先交出文字再丟出transport且保留底層錯誤代碼` |
| 沒有結束事件 | `LKAnthropicClientStreamTests` 的 `stream_沒有messageStop就結束_交出文字後丟出無效回應錯誤`、`stream_回應沒有任何事件_丟出無效回應錯誤` |
| `.finished` 後停止讀取並放開回應 | `LKAnthropicClientCancellationTests` 的 `stream_收到messageStop並交出結束事件_放開回應且底層請求被取消` |
| 取消迭代的 task、釋放串流 | `LKAnthropicClientCancellationTests` 的 `stream_送出一段文字後取消迭代的task_迭代正常結束且底層請求被取消`、`stream_離開迴圈並釋放串流_底層請求被取消` |
| `streamFailure` 的 `isCancelled` | `LKAIChatStreamTests` 與 `LKAIHTTPLinesTests` 的 `init_先取消迭代的task再由來源丟出錯誤_正常結束且沒有錯誤` |

任務 2.3 的兩個測試是既有行為的回歸測試：在修改前的實作上就要通過，合併第 1 組之後也要通過。

**驗收（主對話執行）**：

- **建置與測試**：`swift package clean` 後 `swift build` 與完整 `swift test` 零警告。
  - Swift Testing 共 118 個：LKAICore 62、LKAIAnthropic 45（原本 43，加任務 2.3 的 2 個）、LKAIKitCLI 7、LKAIKit 2、LKAITestSupportTests 2。
  - 2 個實際 API 測試沒有金鑰時略過。
- **spectra-scenario 標記**：`Tests/` 內所有 `spectra-scenario:` 行排序後與修改前逐行相同。
- **`swift package dump-package`**：
  - 依賴方向不變；`LKAITestSupport` 只依賴 `LKAICore`，不屬於任何 product，從 `LKAIKit` 走不到它。
  - `LKAITestSupportTests` 依賴 `LKAITestSupport` 與 `LKAICore`。
- **XcodeBuildMCP（iOS 26 模擬器）**：
  - 建置 `LKAIKit` scheme 成功、零警告。
  - 以 `LKAIKit-Package` scheme 建置測試：錯誤只有既有的 `LKAICommandTests.swift` 的 `Process`，`LKAITestSupport` 沒有錯誤或警告。
- **config.yaml 的指標**：`spectra instructions` 回傳的 context 含有新的指標。
- **反向檢查**：每項都暫時改壞、觀察到測試失敗後還原。

| 暫時改壞的地方 | 預期失敗的測試 |
| --- | --- |
| 拿掉 `init(producing:)` 的 `onTermination` 取消 | 取消與釋放串流的測試 |
| `streamFailure(for:isCancelled:)` 忽略 `isCancelled` | 兩個 `init_先取消迭代的task再由來源丟出錯誤_正常結束且沒有錯誤` |
| 拿掉 `makeStream(for:)` 的 `request.validate()` | 不合法請求的測試 |
| `makeStream(for:)` 吞掉逐行讀取的錯誤、當成串流結束 | `stream_送出文字後連線中斷_先交出文字再丟出transport且保留底層錯誤代碼` |
| `makeStream(for:)` 讀不到錯誤內容時改用空字串 | `stream與invoke_讀取錯誤內容時連線中斷_丟出transport且保留底層錯誤代碼` |
| 讓 `makeStream(for:)` 送出兩次 `fetch` | `stream_回應沒有任何事件_丟出無效回應錯誤`，因替身記錄的問題而失敗；這個測試原本只比對錯誤種類 |
| 拿掉替身的 `Issue.record` | `LKAIMockHTTPClientTests` 的第二次 `fetch` 測試，以「Known issue was not recorded」失敗 |

## Risks / Trade-offs

- [`LKAnthropicClient` 的 `httpClient` 與三個方法提高到 `package`] → 只在 package 內可見，公開 API 不變；`customMirror` 仍不含 `httpClient`，`makeURLRequest(for:)` 的 `///` 寫明只給共同流程使用。
- [共同流程只由一家供應商的測試把關] → 以上方的反向檢查確認表列分支有測試擋住；`02-add-openai-provider` 會帶來第二組使用它的測試，長期位置見 Open Questions。
- [`LKAITestSupport` 開始 `import Testing`] → macOS 上 `swift build` 零警告（實測）。在 iOS 上，`LKAIKit` 與 `LKAIKit-Package` 的一般建置都不含 `LKAITestSupport`（實測），只有建置測試時會編譯它；這種建置目前已因 `Process` 失敗，3.2 以「`LKAITestSupport` 沒有新錯誤」驗收。
- [`Issue.record` 在測試以外被呼叫] → `LKAITestSupport` 不屬於任何 product，只有測試使用。
- [`.invalidResponse` 的說明文字改變] → 只是開發者看的文字；測試只比對錯誤種類（grep 確認），spec 沒有規定這段文字。
- [每條串流多一次 existential 的配置，每則事件多一個陣列] → 相對網路延遲可以忽略（估計，未量測）；量測發現影響時，再改用 associated type 並把狀態型別提高到 `package`。
- [供應商不能自訂錯誤內容的讀取方式] → 三家的錯誤內容都是一般的 JSON，64 KiB 上限足夠（見 `add-chat-abstraction-anthropic` 的決策）；需要時再於 protocol 加要求。
- [提前搬移的 helper 違反 ios-dev-kit 的使用範圍規則] → 寫明為例外與理由；`02-add-openai-provider` 開始使用後即符合規則。

## Migration Plan

只動 package 內部、測試與 `config.yaml`，沒有資料要遷移，App 不需修改。

- **依任務順序擴充、改用、移除**：
  - 1.1 先新增 `init(producing:)`，並讓 `LKAnthropicClient.stream(_:)` 改用它。
  - 1.2 再新增共同流程，讓 Anthropic 改用它，並移除 `run`、`relayEvents`、`decodeEvent`。
  - 第 2 組不動原始碼的行為。
- 每個任務結束時都能建置，所有測試通過。
- **回復方式**：revert 這個 change 的 commit。

## Open Questions

- `LKAIHTTPClient.makeLines(from:)` 的 task 寫法是否也收進共用的建構方式：等出現第二個建立逐行內容的地方再決定。
- 共同流程分支的測試長期放哪裡：目前由 `LKAIAnthropicTests` 把關，其中 14 行標記為 `spectra-scenario: chat-client`（2026-11-22 計數）。
  - 如果 `02-add-openai-provider` 照抄一份，之後改一次共同流程就要改每一家的測試。
  - 另一條路是在 `LKAICoreTests` 用假的供應商測一次；這要讓 `LKAICoreTests` 依賴 `LKAITestSupport`。
  - 由 02 決定。
- SSE 分框的測試 helper：`SSEEvent` 的 `name`／`data` 與 `lines(of:)` 是 SSE 的分框，不是 Anthropic 專屬。02 使用時，把分框的部分搬進 `LKAITestSupport`，Anthropic 的事件建構留在原處。
- 金鑰遮蔽：`LKAnthropicClient` 的 `CustomStringConvertible`、`CustomDebugStringConvertible`、`CustomReflectable` 三個遵循要每家各寫一次，漏了 `CustomReflectable` 時 `dump(_:)` 會印出金鑰。02 要有對應的測試，並考慮能否共用。
- Ollama 原生串流若為 NDJSON（fable 的認知，未查證）：Ollama 的 change 應重用 `makeStream(for:)` 的步驟 1–4 與 6，只抽換步驟 5 的分框方式，不複製整段流程。
