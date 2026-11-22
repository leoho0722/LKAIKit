# anthropic-provider Specification

## Purpose

The anthropic-provider capability defines how `LKAnthropicClient` fulfils the chat-client contract against the Anthropic Messages API: the HTTP request it sends, how it maps streamed events, stop reasons, token usage and errors, and how it keeps the API key out of diagnostic output.

## Requirements

### Requirement: Messages API request

`LKAnthropicClient` SHALL send every chat call, streaming or non-streaming, as a POST request to `https://api.anthropic.com/v1/messages` with the header `x-api-key` set to the configured API key, the header `anthropic-version` set to `2026-10-21`, and the header `content-type` set to `application/json`. The JSON body SHALL contain `model`, `max_tokens` set to the request's maximum number of output tokens, `messages` holding each message's role and text content in order, `stream` set to `true`, and `system` only when the request has a system prompt. The body SHALL NOT contain `temperature`, `top_p`, or `top_k`, and the request SHALL NOT contain an `anthropic-beta` header or a `fallbacks` field unless refusal fallback is enabled.

#### Scenario: Send a request with a system prompt

- **GIVEN** an `LKAnthropicClient` configured with the API key `test-key`
- **WHEN** it sends a request with the model `claude-opus-5-5`, the system prompt "Be brief.", the maximum output tokens 1024, and one user message "Hi"
- **THEN** the recorded request is a POST to `https://api.anthropic.com/v1/messages`
- **AND** its headers include `x-api-key: test-key`, `anthropic-version: 2026-10-21`, and `content-type: application/json`
- **AND** its body, compared as a JSON value, equals `{"model":"claude-opus-5-5","max_tokens":1024,"system":"Be brief.","messages":[{"role":"user","content":"Hi"}],"stream":true}`

#### Scenario: Omit the system field without a system prompt

- **GIVEN** an `LKAnthropicClient` configured with the API key `test-key`
- **WHEN** it sends a request without a system prompt
- **THEN** the recorded JSON body has no `system` key


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Refusal fallback

`LKAnthropicClient` SHALL use the server-side refusal fallback only when the app enables it while creating the client, and the fallback SHALL be disabled by default. With automatic fallback, every request SHALL carry the header `anthropic-beta: server-side-fallback-2026-07-01` and the body field `"fallbacks": "default"`. With specified fallback models, every request SHALL carry the same header and a `fallbacks` array that holds one `{"model": <identifier>}` object per specified model, in the specified order. A specified model list that is empty, holds more than 3 models, holds the same model twice, or holds an empty identifier SHALL make every call fail with an invalid-request error before any network request is sent.

#### Scenario: Send the fallback setting

- **GIVEN** an `LKAnthropicClient` created with a refusal fallback setting
- **WHEN** it sends a request
- **THEN** the recorded `anthropic-beta` header and `fallbacks` body field match the expected values for that setting

##### Example: fallback settings

| Setting | `anthropic-beta` header | `fallbacks` body field |
| ------- | ----------------------- | ---------------------- |
| not set | absent | absent |
| disabled | absent | absent |
| automatic | `server-side-fallback-2026-07-01` | `"default"` |
| models `claude-opus-4-8` | `server-side-fallback-2026-07-01` | `[{"model":"claude-opus-4-8"}]` |
| models `claude-opus-4-8`, `claude-opus-5` | `server-side-fallback-2026-07-01` | `[{"model":"claude-opus-4-8"},{"model":"claude-opus-5"}]` |

#### Scenario: Reject an invalid fallback model list

- **GIVEN** an `LKAnthropicClient` created with a specified fallback model list that breaks one of the rules above
- **WHEN** an app calls the streaming call or the non-streaming call
- **THEN** the call fails with an invalid-request error
- **AND** no network request is recorded

##### Example: invalid fallback model lists

| Specified models | Expected |
| ---------------- | -------- |
| none | invalid-request error |
| `a`, `b`, `c`, `d` | invalid-request error |
| `claude-opus-4-8`, `claude-opus-4-8` | invalid-request error |
| `""` | invalid-request error |


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Responding model and fallback blocks

`LKAnthropicClient` SHALL produce no event for a content block whose type is `fallback`, SHALL keep delivering the text deltas that arrive before and after such a block, and SHALL report as the responding model the `to.model` of the last `fallback` block in the stream, or the `model` of the `message_start` message when the stream has no `fallback` block.

#### Scenario: Report the responding model of a stream

- **GIVEN** a Messages API stream with or without a `fallback` content block
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the delivered events and the responding model match the expected result

##### Example: stream without a fallback block

- **GIVEN** the stream events, in order: `message_start` whose message model is `claude-opus-5-5`; `content_block_start` of type `text`; `content_block_delta` of type `text_delta` with text "Hi"; `content_block_stop`; `message_delta` with `stop_reason` `end_turn`; `message_stop`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hi" and a finished event whose finish reason is completed and whose responding model is `claude-opus-5-5`

##### Example: fallback in the middle of a stream

- **GIVEN** the stream events, in order: `message_start` whose message model is `claude-opus-5-5`; `content_block_start` of type `text`; `content_block_delta` of type `text_delta` with text "Sure"; `content_block_stop`; `content_block_start` of type `fallback` from model `claude-opus-5-5` to model `claude-opus-4-8`; `content_block_stop`; `content_block_start` of type `text`; `content_block_delta` of type `text_delta` with text ", here"; `content_block_stop`; `message_delta` with `stop_reason` `end_turn`; `message_stop`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Sure", text-delta ", here", and a finished event whose finish reason is completed and whose responding model is `claude-opus-4-8`


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Stream text mapping

`LKAnthropicClient` SHALL turn the `text` of each `content_block_delta` event whose delta type is `text_delta` into one text-delta event, in arrival order. Deltas of every other type, such as `thinking_delta` and `signature_delta`, and `ping` events SHALL produce no events.

#### Scenario: Skip thinking deltas and ping events

- **GIVEN** a Messages API stream that contains a thinking block, a `ping` event, and a text block
- **WHEN** an app iterates the streaming call
- **THEN** it receives only the text deltas of the text block, followed by the finished event

##### Example: stream with thinking and ping

- **GIVEN** the stream events, in order: `message_start`; `content_block_start` of type `thinking`; `content_block_delta` of type `thinking_delta` with empty thinking text; `content_block_stop`; `ping`; `content_block_start` of type `text`; `content_block_delta` of type `text_delta` with text "Hel"; `content_block_delta` of type `text_delta` with text "lo"; `content_block_stop`; `message_delta` with `stop_reason` `end_turn`; `message_stop`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel", text-delta "lo", and a finished event whose finish reason is completed


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Stop reason mapping

`LKAnthropicClient` SHALL use the last non-null `stop_reason` that a `message_delta` event reports, since a stream can carry more than one `message_delta` event, and SHALL map it as follows: `end_turn` and `stop_sequence` to the finish reason completed, `max_tokens` to the finish reason max output tokens, `model_context_window_exceeded` to the finish reason context window exceeded, `refusal` to a refused error whose detail is the refusal category from `stop_details` when it is present and not null, and any other value to an invalid-response error. It SHALL deliver the finished event when the `message_stop` event arrives.

#### Scenario: Map stop reasons

- **GIVEN** a Messages API stream whose `message_delta` event reports a `stop_reason`
- **WHEN** an app iterates the streaming call to its end
- **THEN** the outcome matches the expected result for that `stop_reason`

##### Example: stop reasons

| `stop_reason` | `stop_details` | Expected result |
| ------------- | -------------- | --------------- |
| `end_turn` | none | finished event, finish reason completed |
| `stop_sequence` | none | finished event, finish reason completed |
| `max_tokens` | none | finished event, finish reason max output tokens |
| `refusal` | `{"type":"refusal","category":"cyber"}` | refused error, detail "cyber" |
| `refusal` | none | refused error, no detail |
| `refusal` | `{"type":"refusal","category":null}` | refused error, no detail |
| `model_context_window_exceeded` | none | finished event, finish reason context window exceeded |
| `tool_use` | none | invalid-response error |


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Usage mapping

`LKAnthropicClient` SHALL report token usage with the total input tokens equal to `input_tokens` plus `cache_creation_input_tokens` plus `cache_read_input_tokens`, the cached input tokens equal to `cache_read_input_tokens`, the total output tokens equal to `output_tokens`, and the reasoning output tokens equal to `output_tokens_details.thinking_tokens`. It SHALL read these counts from the `usage` of the `message_start` event when it is present and replace each count with the value that a later `message_delta` event reports for it. A count that is null or omitted SHALL count as not reported and SHALL keep the value reported earlier. A cache count that the API does not report SHALL count as zero in the input total, the cached input tokens SHALL be absent when `cache_read_input_tokens` is not reported, and the reasoning output tokens SHALL be absent when `output_tokens_details` is not reported. When no event reports `input_tokens`, or no event reports `output_tokens`, the finished event SHALL carry no usage.

#### Scenario: Combine usage from the start and delta events

- **GIVEN** a Messages API stream whose `message_start` and `message_delta` events report token counts
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event carries the combined usage

##### Example: cached prompt

- **GIVEN** `message_start` reports `input_tokens` 10, `cache_creation_input_tokens` 5, `cache_read_input_tokens` 20, and `output_tokens` 1, and `message_delta` reports `output_tokens` 7
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the usage has total input tokens 35, cached input tokens 20, total output tokens 7, and no reasoning token count

##### Example: thinking tokens

- **GIVEN** `message_start` reports `input_tokens` 12, and `message_delta` reports `output_tokens` 120 and `output_tokens_details` with `thinking_tokens` 100
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the usage has total input tokens 12, no cached input token count, total output tokens 120, and reasoning output tokens 100

##### Example: usage only in the delta event

- **GIVEN** `message_start` has no `usage`, and `message_delta` reports `input_tokens` 12, `cache_read_input_tokens` null, and `output_tokens` 30
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the usage has total input tokens 12, no cached input token count, total output tokens 30, and no reasoning token count

##### Example: input tokens never reported

- **GIVEN** `message_start` has no `usage`, and `message_delta` reports only `output_tokens` 5
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event carries no usage


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Error mapping

`LKAnthropicClient` SHALL classify an HTTP response whose status code is outside 200-299 by the `error.type` in its JSON body: `authentication_error` as invalid API key; `permission_error` as permission denied; `billing_error` as quota exceeded; `rate_limit_error` as quota exceeded when `error.details.error_code` is `enforced_spend_limit_reached`, and otherwise as rate limited with the `retry-after` header value in seconds as the retry delay; `invalid_request_error` as quota exceeded when `error.message` starts with "You have reached your specified", which is how the API reports a spend limit that the organization or workspace set for itself, and otherwise, like `not_found_error` and `request_too_large`, as invalid request carrying `error.message`; and `api_error`, `overloaded_error` and `timeout_error` as service unavailable with the response's HTTP status code and the `retry-after` header value in seconds as the retry delay. A body it cannot decode, an `error` object without `error.type`, or an `error.type` it does not know, SHALL fall back to the default HTTP status classification of the chat-client capability. An `error` event inside a stream SHALL be classified by the same `error.type` rules, using 500 as the status code for `api_error`, 529 for `overloaded_error` and 504 for `timeout_error`, with no retry delay because a stream carries no headers. Following the unrecognized stream errors requirement of the chat-client capability, with `error.type` as the error code, an `error` event whose `error.type` it does not know SHALL be reported as an invalid-response error whose description contains the `error.type` and the `error.message`; an `error` event whose `error` object has no `error.type` SHALL be reported as service unavailable with status 500 and no retry delay; and an `error` event whose data it cannot decode, which includes data that is not JSON and data without an `error` object, SHALL be reported as an invalid-response error.

#### Scenario: Classify HTTP error responses

- **GIVEN** an HTTP error response from the Messages API
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with the expected error for that response

##### Example: error responses

| Status | `error.type` | Other response data | Expected error |
| ------ | ------------ | ------------------- | -------------- |
| 401 | `authentication_error` | none | invalid API key |
| 403 | `permission_error` | none | permission denied |
| 402 | `billing_error` | none | quota exceeded |
| 429 | `rate_limit_error` | header `retry-after: 20` | rate limited, retry delay 20 seconds |
| 429 | `rate_limit_error` | `error.details.error_code` is `enforced_spend_limit_reached` | quota exceeded |
| 400 | `invalid_request_error` | `error.message` is "max_tokens: too large" | invalid request, message "max_tokens: too large" |
| 400 | `invalid_request_error` | `error.message` is "You have reached your specified API usage limits. You will regain access on 2026-12-01 at 00:00 UTC." | quota exceeded |
| 400 | `invalid_request_error` | `error.message` is "You have reached your specified workspace API usage limits. You will regain access on 2026-12-01 at 00:00 UTC." | quota exceeded |
| 529 | `overloaded_error` | none | service unavailable, status 529, no retry delay |
| 529 | `overloaded_error` | header `retry-after: 10` | service unavailable, status 529, retry delay 10 seconds |
| 500 | `api_error` | none | service unavailable, status 500, no retry delay |
| 500 | `api_error` | header `retry-after: 3` | service unavailable, status 500, retry delay 3 seconds |
| 504 | `timeout_error` | none | service unavailable, status 504, no retry delay |
| 504 | `timeout_error` | header `retry-after: 7` | service unavailable, status 504, retry delay 7 seconds |
| 409 | `conflict_error` | none | invalid request |
| 502 | body is not JSON | none | service unavailable, status 502, no retry delay |
| 400 | `error` object without `type` | `error.message` is "Bad request" | invalid request without a message |

#### Scenario: Error event in the middle of a stream

- **GIVEN** a Messages API stream that delivers the text delta "Hel" and then an `error` event
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel"
- **AND** the stream then fails with the expected error for that event

##### Example: error events

| `error` event data | Expected error |
| ------------------ | -------------- |
| `error.type` is `overloaded_error` | service unavailable, status 529, no retry delay |
| `error.type` is `api_error` | service unavailable, status 500, no retry delay |
| `error.type` is `timeout_error` | service unavailable, status 504, no retry delay |
| `error.type` is `new_unknown_error`, `error.message` is "Something went wrong." | invalid response whose description contains "new_unknown_error" and "Something went wrong." |
| `error` object without `type`, `error.message` is "Something went wrong." | service unavailable, status 500, no retry delay |
| `{"type":"error"}`, without an `error` object | invalid response |
| data is not JSON | invalid response |


<!-- @trace
source: 03-revise-chat-client-contract
updated: 2026-11-22
code:
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAICoreTests/Chat/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/Chat/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/Chat/LKAIErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - docs/adding-a-provider.md
-->

---
### Requirement: API key secrecy

`LKAnthropicClient` SHALL NOT include its API key in the text produced by `String(describing:)`, `String(reflecting:)`, or `dump(_:)` for the client, nor in the description of any error it reports.

#### Scenario: Describe a configured client

- **GIVEN** an `LKAnthropicClient` configured with the API key `sk-ant-secret-123`
- **WHEN** its `String(describing:)` text, its `String(reflecting:)` text, and its `dump(_:)` output are produced
- **THEN** none of them contains `sk-ant-secret-123`
- **AND** the `String(describing:)` text of the error reported for an HTTP 401 response does not contain `sk-ant-secret-123`


<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Availability through LKAIKit

Code that imports only `LKAIKit` SHALL be able to create an `LKAnthropicClient` from an API key and a `URLSession` and use it as a value of type `any LKAIChatClientProtocol`.

#### Scenario: Create the client through the umbrella module

- **GIVEN** a source file whose only LKAIKit-related import statement is `import LKAIKit`
- **WHEN** the file creates an `LKAnthropicClient` with an API key and a `URLSession` and assigns it to a value of type `any LKAIChatClientProtocol`
- **THEN** the file compiles without an `import LKAIAnthropic` or `import LKAICore` statement

<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->