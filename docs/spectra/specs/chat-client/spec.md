# chat-client Specification

## Purpose

The chat-client capability defines the provider-independent contract that every LKAIKit chat provider fulfils: the request an app sends, the streaming and non-streaming calls, finish reasons, normalized token usage, and how refusals, cancellation and failures are reported. It exists so that apps can switch between OpenAI GPT, Anthropic Claude and Google Gemini without changing how they call LKAIKit.

## Requirements

### Requirement: Chat request content

A chat request SHALL contain a model identifier, an ordered list of messages whose role is either user or assistant and whose content is text, an optional system prompt, and a maximum number of output tokens. A chat client SHALL reject a request whose model identifier is empty, whose message list is empty, or whose maximum number of output tokens is less than 1, by failing with an invalid-request error before it sends any network request. This rule applies to both the streaming call and the non-streaming call.

#### Scenario: Reject an invalid request before sending

- **GIVEN** a chat client whose network requests are recorded
- **WHEN** the client is called through the streaming call or the non-streaming call with a request that breaks one of the rules above
- **THEN** the call fails with an invalid-request error
- **AND** no network request is recorded

##### Example: invalid requests

| Model | Messages | Maximum output tokens | Expected |
| ----- | -------- | --------------------- | -------- |
| `""` | user "Hi" | 1024 | invalid-request error |
| `claude-opus-5-5` | none | 1024 | invalid-request error |
| `claude-opus-5-5` | user "Hi" | 0 | invalid-request error |


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
### Requirement: Streaming call

A chat client SHALL provide a streaming call that delivers the generated text as text-delta events in the order the provider generates them, followed by exactly one finished event that carries the finish reason, the token usage, and the responding model, after which the stream SHALL end.

#### Scenario: Stream a response that completes normally

- **GIVEN** a provider that generates the text "Hel", then "lo", and then finishes normally
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel", text-delta "lo", and a finished event whose finish reason is completed, in this order
- **AND** the stream ends after the finished event


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
### Requirement: Non-streaming call

A chat client SHALL provide a non-streaming call that, after generation finishes, returns one result containing the concatenation of all generated text, the finish reason, the token usage, and the responding model.

#### Scenario: Receive a complete response

- **GIVEN** a provider that generates the text "Hel", then "lo", and then finishes normally
- **WHEN** an app awaits the non-streaming call
- **THEN** the result text is "Hello"
- **AND** the result finish reason is completed


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
### Requirement: Output token limit

When generation stops because the maximum number of output tokens is reached, the streaming call SHALL end with a finished event whose finish reason is max output tokens, and the non-streaming call SHALL return the text generated so far with the finish reason max output tokens. Neither call SHALL report this case as an error.

#### Scenario: Stream stops at the output token limit

- **GIVEN** a provider that generates "Partial" and then stops at the output token limit
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Partial" and then a finished event whose finish reason is max output tokens

#### Scenario: Non-streaming call stops at the output token limit

- **GIVEN** a provider that generates "Partial" and then stops at the output token limit
- **WHEN** an app awaits the non-streaming call
- **THEN** the result text is "Partial"
- **AND** the result finish reason is max output tokens


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
### Requirement: Context window limit

When generation stops because the model's context window is full, and the provider reports that cause separately from reaching the output token limit, the streaming call SHALL end with a finished event whose finish reason is context window exceeded, and the non-streaming call SHALL return the text generated so far with the finish reason context window exceeded. When the provider reports a full context window the same way as reaching the output token limit, both calls SHALL report the finish reason max output tokens instead, as that provider's capability states. Neither call SHALL report either case as an error, and the finish reason context window exceeded SHALL be distinct from max output tokens.

#### Scenario: Stream stops when the context window is full

- **GIVEN** a provider that reports a full context window separately from the output token limit, and that generates "Partial" and then stops because the model's context window is full
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Partial" and then a finished event whose finish reason is context window exceeded

#### Scenario: Non-streaming call stops when the context window is full

- **GIVEN** a provider that reports a full context window separately from the output token limit, and that generates "Partial" and then stops because the model's context window is full
- **WHEN** an app awaits the non-streaming call
- **THEN** the result text is "Partial"
- **AND** the result finish reason is context window exceeded

#### Scenario: Provider reports a full context window as the output token limit

- **GIVEN** a provider that reports a full context window the same way as reaching the output token limit, and that generates "Hel" and then stops for that reason
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel" and then a finished event whose finish reason is max output tokens


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
### Requirement: Responding model

The finished event of the streaming call and the result of the non-streaming call SHALL carry the identifier of the model that produced the final output as the provider reports it, and SHALL carry no identifier when the provider does not report one.

#### Scenario: Report the responding model

- **GIVEN** a provider that reports the model `claude-opus-4-8` as the producer of the output and finishes normally
- **WHEN** an app iterates the streaming call and, separately, awaits the non-streaming call
- **THEN** the finished event names the responding model `claude-opus-4-8`
- **AND** the non-streaming result names the responding model `claude-opus-4-8`

#### Scenario: Provider reports no model

- **GIVEN** a provider stream that finishes normally without reporting which model produced the output
- **WHEN** an app awaits the non-streaming call
- **THEN** the result carries no responding model


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
### Requirement: Refusal

When the provider declines to answer or blocks the content, both calls SHALL fail with a refused error that carries the detail the provider gives, or no detail when the provider gives none. The streaming call SHALL fail after delivering the text deltas generated before the refusal, and the non-streaming call SHALL NOT return that partial text.

#### Scenario: Streaming call refused after partial text

- **GIVEN** a provider that generates "Sure" and then declines with the detail "cyber"
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Sure"
- **AND** the stream then fails with a refused error whose detail is "cyber"

#### Scenario: Non-streaming call refused after partial text

- **GIVEN** a provider that generates "Sure" and then declines with the detail "cyber"
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with a refused error whose detail is "cyber"
- **AND** no result is returned


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
### Requirement: Cancellation

When the task that iterates a streaming call is cancelled, the stream SHALL end without failing, even when the provider reports an error after the cancellation, and the client SHALL cancel the underlying network request. When the app releases a stream, whether or not it iterated the stream, the client SHALL cancel the underlying network request; leaving the iteration loop while the app still holds the stream does not by itself cancel the request. When the task that awaits a non-streaming call is cancelled, the call SHALL fail with a cancelled error, even when the provider reports another error after the cancellation, and SHALL NOT return partial text.

#### Scenario: Cancel a streaming call

- **GIVEN** a streaming call that has delivered one text delta and is waiting for more data from the network
- **WHEN** the iterating task is cancelled
- **THEN** the iteration ends without an error
- **AND** the underlying network request is cancelled

#### Scenario: Release a stream after leaving the loop

- **GIVEN** a streaming call that has delivered one text delta and is waiting for more data from the network
- **WHEN** the app leaves the iteration loop and releases the stream
- **THEN** the underlying network request is cancelled

#### Scenario: Cancel a non-streaming call

- **GIVEN** a non-streaming call that is waiting for more data from the network
- **WHEN** the awaiting task is cancelled
- **THEN** the call fails with a cancelled error


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
### Requirement: Error classification and retryability

Every failure of a chat call SHALL be reported as one of these errors: invalid API key, permission denied, rate limited with an optional retry delay, quota exceeded, service unavailable with the HTTP status code and an optional retry delay, invalid request with an optional provider message, refused with an optional detail, cancelled, transport failure with the underlying URL error, and invalid response with a description. Each error SHALL state whether sending the same request again can succeed: rate limited, service unavailable and transport failure SHALL be retryable, and every other error SHALL NOT be retryable.

#### Scenario: Report whether an error is retryable

- **GIVEN** an error of each kind
- **WHEN** an app reads whether the error is retryable
- **THEN** the answer matches the expected value for that kind

##### Example: retryability by error kind

| Error | Retryable |
| ----- | --------- |
| invalid API key | no |
| permission denied | no |
| rate limited, retry delay 30 seconds | yes |
| quota exceeded | no |
| service unavailable, status 529, no retry delay | yes |
| service unavailable, status 503, retry delay 5 seconds | yes |
| invalid request, message "bad" | no |
| refused, detail "cyber" | no |
| cancelled | no |
| transport failure, URL error not connected to internet | yes |
| invalid response, description "bad data" | no |


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
### Requirement: Default HTTP status classification

When a provider receives an HTTP response whose status code is outside 200-299 and whose body its own error format does not classify, the provider SHALL classify the response by HTTP status code: 401 as invalid API key, 403 as permission denied, 402 as quota exceeded, 429 as rate limited with the `retry-after` header value in seconds as the retry delay, any other 4xx status as invalid request, any 5xx status as service unavailable with that status code and the `retry-after` header value in seconds as the retry delay, and any other status as invalid response. A `retry-after` value SHALL count as a retry delay only when it consists of ASCII digits alone; any other value, such as a signed number or an HTTP date, SHALL count as no retry delay.

#### Scenario: Classify HTTP error statuses

- **GIVEN** an HTTP response with a status code outside 200-299 and a body that the provider cannot classify
- **WHEN** the provider classifies the response
- **THEN** the error matches the expected error for that status code

##### Example: status codes

| Status | `retry-after` header | Expected error |
| ------ | -------------------- | -------------- |
| 401 | none | invalid API key |
| 403 | none | permission denied |
| 402 | none | quota exceeded |
| 429 | `30` | rate limited, retry delay 30 seconds |
| 429 | none | rate limited, no retry delay |
| 429 | `-1` | rate limited, no retry delay |
| 429 | `Wed, 21 Oct 2026 07:28:00 GMT` | rate limited, no retry delay |
| 400 | none | invalid request |
| 404 | none | invalid request |
| 503 | none | service unavailable, status 503, no retry delay |
| 503 | `5` | service unavailable, status 503, retry delay 5 seconds |
| 503 | `-1` | service unavailable, status 503, no retry delay |
| 529 | none | service unavailable, status 529, no retry delay |
| 529 | `Wed, 21 Oct 2026 07:28:00 GMT` | service unavailable, status 529, no retry delay |
| 302 | none | invalid response |


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
### Requirement: Token usage

Token usage SHALL report the total input tokens including tokens read from a prompt cache, the total output tokens including tokens spent on reasoning or thinking, the input tokens read from a prompt cache when the provider reports them, and the output tokens spent on reasoning when the provider reports them. A count that the provider does not report SHALL be absent rather than zero. When the provider reports no usage at all, the finished event and the non-streaming result SHALL carry no usage instead of failing. A call that fails or is cancelled SHALL deliver no usage.

#### Scenario: Provider reports no usage

- **GIVEN** a provider stream that finishes normally without reporting any token usage
- **WHEN** an app iterates the streaming call
- **THEN** the finished event has the finish reason completed and carries no usage


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
### Requirement: Invalid responses

A chat call SHALL fail with an invalid-response error when the provider's data cannot be decoded, when the provider reports a finish reason that this contract does not define, or when the provider's stream ends before the provider reports a finish.

#### Scenario: Stream ends before a finish is reported

- **GIVEN** a provider stream that delivers the text "Hel" and then closes without reporting a finish
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel"
- **AND** the stream then fails with an invalid-response error

#### Scenario: Non-streaming call on a stream without a finish

- **GIVEN** a provider stream that delivers the text "Hel" and then closes without reporting a finish
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with an invalid-response error


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
### Requirement: Stream construction for test doubles

An app SHALL be able to construct a chat stream from its own asynchronous sequence of events, so that it can implement a test double of the chat client interface. Such a stream SHALL deliver the source's events in order, SHALL surface a chat error thrown by the source unchanged except a cancelled error, SHALL surface any other error thrown by the source as an invalid-response error, and SHALL end without failing when the source throws a cancellation error or a cancelled error, or when the source throws any error after the iterating task has been cancelled.

#### Scenario: Build a stream from scripted events

- **GIVEN** a chat stream constructed from a source sequence
- **WHEN** an app iterates the stream
- **THEN** the delivered events and the outcome match the expected result for the source's behavior

##### Example: source behaviors

| Source behavior | Expected result |
| --------------- | --------------- |
| yields text-delta "A", then a finished event with the finish reason completed, then ends | delivers both events in order, then ends |
| yields text-delta "A", then throws a rate-limited error | delivers text-delta "A", then fails with the same rate-limited error |
| throws an error that is not a chat error | fails with an invalid-response error |
| throws a cancellation error | ends without an error |
| throws a cancelled error | ends without an error |
| the iterating task is cancelled, then the source throws a rate-limited error | ends without an error |


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
### Requirement: Localized error descriptions

Every chat error SHALL provide a non-empty localized description through `LocalizedError.errorDescription` in English (`en`) and in Traditional Chinese (`zh-Hant`), and English SHALL be the development language used when the app's language is neither. The description SHALL be one generic message for the error kind, and it SHALL NOT include the provider message of an invalid-request error, the detail of a refused error, the text of the underlying URL error, or an API key.

#### Scenario: Look up the description of each error kind

- **GIVEN** an error of each kind
- **WHEN** its description is looked up in a supported language
- **THEN** the description is non-empty and differs from its lookup key

##### Example: supported languages

| Language | Expected |
| -------- | -------- |
| `en` | every error kind has a non-empty description that differs from its lookup key |
| `zh-Hant` | every error kind has a non-empty description that differs from its lookup key |

#### Scenario: Use English as the development language

- **GIVEN** the resource bundle of `LKAICore`
- **WHEN** its development language and its localizations are inspected
- **THEN** the development language is `en`
- **AND** the localizations include `en` and `zh-Hant`

#### Scenario: Keep provider text out of the description

- **GIVEN** an invalid-request error whose provider message is "max_tokens: too large" and a refused error whose detail is "cyber"
- **WHEN** their descriptions are produced
- **THEN** the description of the invalid-request error does not contain "max_tokens: too large"
- **AND** the description of the refused error does not contain "cyber"

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
### Requirement: Unrecognized stream errors

When a provider's stream reports an error after the HTTP response has started, and the error carries a provider error code that the provider does not recognize, the call SHALL fail with an invalid-response error whose description contains that code and, when the provider gives one, its error message; this error SHALL NOT be retryable. When the stream error carries no error code at all, the call SHALL fail with a service-unavailable error with status 500 and no retry delay. Every provider SHALL apply this rule to the stream errors it does not map to another error. Which field of a stream error counts as its error code, and how incomplete the error data can be before it counts as data that cannot be decoded, SHALL be stated by that provider's capability. A stream error whose data cannot be decoded SHALL be reported as an invalid-response error, as the invalid responses requirement states. This rule SHALL NOT apply to an HTTP error response: an HTTP error response that the provider's own error format does not classify SHALL fall back to the default HTTP status classification, because its status code still tells whether the failure can be retried.

#### Scenario: Report a stream error the provider does not recognize

- **GIVEN** a stream error that the provider does not map to another error
- **WHEN** the provider reports it to the app
- **THEN** the error and its retryability match the expected values for that error's code and message

##### Example: unrecognized stream errors

| Error code | Error message | Expected error | Retryable |
| ---------- | ------------- | -------------- | --------- |
| `new_unknown_code` | "Something went wrong." | invalid response whose description contains "new_unknown_code" and "Something went wrong." | no |
| `new_unknown_code` | none | invalid response whose description contains "new_unknown_code" | no |
| none | "Something went wrong." | service unavailable, status 500, no retry delay | yes |
| none | none | service unavailable, status 500, no retry delay | yes |

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