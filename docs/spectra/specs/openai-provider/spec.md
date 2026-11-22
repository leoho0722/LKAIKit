# openai-provider Specification

## Purpose

The openai-provider capability defines how `LKOpenAIClient` fulfils the chat-client contract against the OpenAI Responses API: the HTTP request it sends, the response storage setting, how it maps streamed events, finish reasons, refusals, token usage and errors, and how it keeps the API key out of diagnostic output.

## Requirements

### Requirement: Responses API request

`LKOpenAIClient` SHALL send every chat call, streaming or non-streaming, as a POST request to `https://api.openai.com/v1/responses` with the header `Authorization` set to `Bearer ` followed by the configured API key and the header `content-type` set to `application/json`. The JSON body SHALL contain `model`, `input` holding one `{"role": <role>, "content": <text>}` object per message in order with the role `user` or `assistant`, `max_output_tokens` set to the request's maximum number of output tokens, `stream` set to `true`, `store` as the response storage requirement defines, and `instructions` only when the request has a system prompt. The body SHALL NOT contain `temperature`, `top_p`, or `reasoning`. The client SHALL send the maximum number of output tokens unchanged, also when it is below the API's documented minimum of 16, and SHALL report the API's rejection through the error mapping requirement.

#### Scenario: Send a request with a system prompt

- **GIVEN** an `LKOpenAIClient` configured with the API key `test-key` and the default response storage setting
- **WHEN** it sends a request with the model `gpt-6-luna`, the system prompt "Be brief.", the maximum output tokens 1024, and one user message "Hi"
- **THEN** the recorded request is a POST to `https://api.openai.com/v1/responses`
- **AND** its headers include `Authorization: Bearer test-key` and `content-type: application/json`
- **AND** its body, compared as a JSON value, equals `{"model":"gpt-6-luna","instructions":"Be brief.","input":[{"role":"user","content":"Hi"}],"max_output_tokens":1024,"stream":true,"store":false}`

#### Scenario: Omit the instructions field without a system prompt

- **GIVEN** an `LKOpenAIClient` configured with the API key `test-key`
- **WHEN** it sends a request without a system prompt
- **THEN** the recorded JSON body has no `instructions` key

#### Scenario: Send the conversation in order

- **GIVEN** an `LKOpenAIClient` configured with the API key `test-key`
- **WHEN** it sends a request whose messages are the user message "Hi", the assistant message "Hello!", and the user message "How are you?"
- **THEN** the `input` of the recorded JSON body equals `[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello!"},{"role":"user","content":"How are you?"}]`

#### Scenario: Send a maximum below the documented minimum unchanged

- **GIVEN** an `LKOpenAIClient` configured with the API key `test-key`
- **WHEN** it sends a request whose maximum output tokens is 8
- **THEN** the recorded JSON body has `max_output_tokens` equal to 8


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Response storage setting

`LKOpenAIClient` SHALL keep response storage disabled unless the app enables it while creating the client, including when the app creates the client from an API key and a `URLSession` without a storage setting. With response storage disabled, every request body SHALL carry `"store": false`; with response storage enabled, every request body SHALL carry `"store": true`. The client's `Mirror` SHALL report the setting as the child `shouldStoreResponses`.

#### Scenario: Send the storage setting

- **GIVEN** an `LKOpenAIClient` created with a response storage setting
- **WHEN** it sends a request
- **THEN** the recorded `store` body field matches the expected value for that setting

##### Example: storage settings

| Setting | `store` body field |
| ------- | ------------------ |
| not set | `false` |
| disabled | `false` |
| enabled | `true` |

#### Scenario: Create a client from a URL session without a storage setting

- **GIVEN** an `LKOpenAIClient` created from an API key and a `URLSession` without a storage setting
- **WHEN** an app reads the children of the client's `Mirror`
- **THEN** the child `shouldStoreResponses` is `false`


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Stream text mapping

`LKOpenAIClient` SHALL read the kind of each streamed event from the `type` field of its data, and SHALL turn the `delta` of each `response.output_text.delta` event into one text-delta event, in arrival order. `response.refusal.delta` and `response.refusal.done` events SHALL NOT produce text-delta events. Every other event type that this capability does not name, such as `response.created`, `response.in_progress`, `response.output_item.added`, `response.reasoning_summary_text.delta`, `response.output_text.done`, and types the client does not know, SHALL produce no event. Event data that is not valid JSON, or a named event whose fields do not match, SHALL fail the call with an invalid-response error at that event, without delivering the events that follow it.

#### Scenario: Skip lifecycle and reasoning events

- **GIVEN** a Responses API stream that contains lifecycle events, a reasoning summary delta, and text deltas
- **WHEN** an app iterates the streaming call
- **THEN** it receives only the text deltas, followed by the finished event

##### Example: stream with lifecycle and reasoning events

- **GIVEN** the stream events, in order: `response.created`; `response.in_progress`; `response.output_item.added`; `response.reasoning_summary_text.delta` with delta "Thinking"; `response.output_text.delta` with delta "Hel"; `response.output_text.delta` with delta "lo"; `response.output_text.done`; `response.completed`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel", text-delta "lo", and a finished event whose finish reason is completed

#### Scenario: Fail on malformed event data

- **GIVEN** a Responses API stream whose first event data is not valid JSON, followed by a `response.output_text.delta` event with delta "Hel" and a `response.completed` event
- **WHEN** an app iterates the streaming call
- **THEN** the stream fails with an invalid-response error
- **AND** the app receives no text-delta event


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Finish and refusal mapping

`LKOpenAIClient` SHALL end the stream at the first `response.completed`, `response.incomplete`, `response.failed`, or `error` event, and SHALL NOT act on any event after it. The refusal text of a stream SHALL be the `delta` values of its `response.refusal.delta` events joined in arrival order, or, when that joined text is empty, the `refusal` values of its `response.refusal.done` events joined in arrival order. When the refusal text is not empty, a `response.completed` or `response.incomplete` event SHALL fail the call with a refused error whose detail is the refusal text. Otherwise, `response.completed` SHALL deliver a finished event whose finish reason is completed, and `response.incomplete` SHALL be mapped by `response.incomplete_details.reason`: `max_output_tokens` to a finished event whose finish reason is max output tokens, `content_filter` to a refused error whose detail is `content_filter`, and any other or missing reason to an invalid-response error. Because the Responses API reports generation that fills the model's context window with the same reason `max_output_tokens`, the client SHALL NOT report the finish reason context window exceeded. Text deltas delivered before the end of the stream SHALL stay delivered.

#### Scenario: Map terminal events

- **GIVEN** a Responses API stream that delivers the text delta "Hel", then a terminal event, and then a `response.completed` event
- **WHEN** an app iterates the streaming call to its end
- **THEN** it receives text-delta "Hel"
- **AND** the outcome after it matches the expected result for the first terminal event

##### Example: terminal events

| First terminal event | Refusal events before it | Expected result |
| -------------------- | ------------------------ | --------------- |
| `response.completed` | none | finished event, finish reason completed |
| `response.completed` | `response.refusal.delta` "I'm sorry," and " I can't help with that." | refused error, detail "I'm sorry, I can't help with that." |
| `response.completed` | `response.refusal.done` with refusal "I can't help with that." and no delta | refused error, detail "I can't help with that." |
| `response.completed` | `response.refusal.delta` "" and `response.refusal.done` with refusal "I can't help with that." | refused error, detail "I can't help with that." |
| `response.incomplete` with reason `max_output_tokens` | none | finished event, finish reason max output tokens |
| `response.incomplete` with reason `content_filter` | none | refused error, detail "content_filter" |
| `response.incomplete` with reason `max_messages` | none | invalid-response error |
| `response.incomplete` without `incomplete_details` | none | invalid-response error |

#### Scenario: Non-streaming call refused after partial text

- **GIVEN** a Responses API stream that delivers the text delta "Sure", the refusal delta "I can't help with that.", and then `response.completed`
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with a refused error whose detail is "I can't help with that."
- **AND** no result is returned


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Responding model

`LKOpenAIClient` SHALL report as the responding model of a finished event the `model` of the response object in the `response.completed` or `response.incomplete` event that ends the stream, and SHALL report no responding model when that response object has no `model`.

#### Scenario: Report the model of the finished response

- **GIVEN** a Responses API stream for a request with the model `gpt-6-luna` whose `response.completed` event carries a response with the model `gpt-6-luna-2026-09-01`
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event's responding model is `gpt-6-luna-2026-09-01`


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Usage mapping

`LKOpenAIClient` SHALL report token usage from the `response.usage` of the event that ends the stream with a finished event: the total input tokens equal to `input_tokens`, the cached input tokens equal to `input_tokens_details.cached_tokens`, the total output tokens equal to `output_tokens`, and the reasoning output tokens equal to `output_tokens_details.reasoning_tokens`. A detail that the API does not report SHALL leave its count absent. When `usage` is null or absent, or reports no `input_tokens` or no `output_tokens`, the finished event SHALL carry no usage.

#### Scenario: Map the usage of the finished response

- **GIVEN** a Responses API stream whose `response.completed` event carries a response with a `usage` value
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event carries the expected usage

##### Example: usage values

| `usage` | Expected usage |
| ------- | -------------- |
| `{"input_tokens":120,"input_tokens_details":{"cached_tokens":100},"output_tokens":45,"output_tokens_details":{"reasoning_tokens":30},"total_tokens":165}` | total input 120, cached input 100, total output 45, reasoning output 30 |
| `{"input_tokens":12,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":17}` | total input 12, cached input 0, total output 5, reasoning output 0 |
| `{"input_tokens":12,"output_tokens":5,"total_tokens":17}` | total input 12, no cached input count, total output 5, no reasoning count |
| `null` | no usage |
| `{"output_tokens":5}` | no usage |


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Error mapping

In this requirement, the policy codes are `cyber_policy`, `bio_policy`, and `misalignment_policy_violation`, and the quota codes are `insufficient_quota`, `billing_hard_limit_reached`, `credit_balance_exhausted`, `organization_spend_limit_exceeded`, `project_spend_limit_exceeded`, and `organization_usage_limit_exceeded`.

`LKOpenAIClient` SHALL classify an HTTP response whose status code is outside 200-299 by the `error` object in its JSON body, applying the first rule that matches: a policy code in `error.code` SHALL be reported as refused with the code as detail; a quota code in `error.code`, or `error.type` equal to `insufficient_quota`, SHALL be reported as quota exceeded; any other decodable body whose status code is a 4xx status other than 401, 402, 403, and 429 SHALL be reported as invalid request carrying `error.message`. Every other response, including a body it cannot decode, SHALL fall back to the default HTTP status classification of the chat-client capability. The body SHALL count as decodable when it holds an `error` object whose `message`, `type`, and `code`, when present, are strings or null, even when none of them is present.

An `error` event, and the `response.error` of a `response.failed` event, SHALL be classified by its `code`: a policy code as refused with the code as detail; `rate_limit_exceeded` and `slow_down` as rate limited with no retry delay; a quota code as quota exceeded; `server_is_overloaded` as service unavailable with status 503, and `server_error` and `vector_store_timeout` as service unavailable with status 500, all three with no retry delay because a stream carries no headers; `invalid_prompt` and `data_residency_mismatch` as invalid request carrying the `message`; and, following the unrecognized stream errors requirement of the chat-client capability with `code` as the error code, any other code that is not null as an invalid-response error whose description contains the code and the `message`, and a null or absent code, or a `response.failed` event without `response.error`, as service unavailable with status 500 and no retry delay. The data of an `error` event SHALL count as decodable when it is a JSON object whose `code` and `message`, when present, are strings or null, even when it has neither `code` nor `message`; any other data SHALL be reported as an invalid-response error.

#### Scenario: Classify HTTP error responses

- **GIVEN** an HTTP error response from the Responses API
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with the expected error for that response

##### Example: error responses

| Status | `error` object | Other response data | Expected error |
| ------ | -------------- | ------------------- | -------------- |
| 401 | `{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}` | none | invalid API key |
| 402 | `{"message":"Payment required.","type":"invalid_request_error","code":null}` | none | quota exceeded |
| 403 | `{"message":"Country, region, or territory not supported","type":"request_forbidden","code":"unsupported_country_region_territory"}` | none | permission denied |
| 403 | `{"message":"This request was stopped by misalignment monitoring.","type":"invalid_request_error","code":"misalignment_policy_violation"}` | none | refused, detail "misalignment_policy_violation" |
| 400 | `{"message":"This request was flagged as potentially suspicious.","type":"invalid_request_error","code":"cyber_policy"}` | none | refused, detail "cyber_policy" |
| 429 | `{"message":"Rate limit reached for requests","type":"requests","code":"rate_limit_exceeded"}` | header `retry-after: 20` | rate limited, retry delay 20 seconds |
| 429 | `{"message":"Please slow down.","type":"rate_limit_error","code":"slow_down"}` | none | rate limited, no retry delay |
| 429 | `{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}` | none | quota exceeded |
| 429 | `{"message":"Your credit balance is exhausted.","type":"insufficient_quota","code":"credit_balance_exhausted"}` | header `retry-after: 20` | quota exceeded |
| 429 | `{"message":"Organization spend limit exceeded.","type":"requests","code":"organization_spend_limit_exceeded"}` | none | quota exceeded |
| 429 | `{"message":"Project spend limit exceeded.","type":"requests","code":"project_spend_limit_exceeded"}` | none | quota exceeded |
| 429 | `{"message":"Organization usage limit exceeded.","type":"requests","code":"organization_usage_limit_exceeded"}` | none | quota exceeded |
| 429 | `{"message":"Billing hard limit reached.","type":"requests","code":"billing_hard_limit_reached"}` | none | quota exceeded |
| 429 | `{"message":"Quota exhausted.","type":"insufficient_quota","code":null}` | none | quota exceeded |
| 429 | `{"type":"insufficient_quota","code":"insufficient_quota"}` | none | quota exceeded |
| 400 | `{"message":"Your input exceeds the context window of this model.","type":"invalid_request_error","code":null}` | none | invalid request, message "Your input exceeds the context window of this model." |
| 404 | `{"message":"The model 'gpt-0' does not exist.","type":"invalid_request_error","code":"model_not_found"}` | none | invalid request, message "The model 'gpt-0' does not exist." |
| 503 | `{"message":"Model temporarily overloaded","type":"service_unavailable_error","code":"server_is_overloaded"}` | header `retry-after: 5` | service unavailable, status 503, retry delay 5 seconds |
| 500 | `{"message":"The server had an error while processing your request.","type":"server_error","code":null}` | none | service unavailable, status 500, no retry delay |
| 502 | body is not JSON | none | service unavailable, status 502, no retry delay |

#### Scenario: Error event in the middle of a stream

- **GIVEN** a Responses API stream that delivers the text delta "Hel" and then an `error` event
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel"
- **AND** the stream then fails with the expected error for that event's `code`

##### Example: error event codes

| `code` | `message` | Expected error |
| ------ | --------- | -------------- |
| `rate_limit_exceeded` | "Rate limit reached." | rate limited, no retry delay |
| `slow_down` | "Please slow down." | rate limited, no retry delay |
| `insufficient_quota` | "You exceeded your current quota." | quota exceeded |
| `server_is_overloaded` | "Model temporarily overloaded" | service unavailable, status 503, no retry delay |
| `server_error` | "The model failed to generate a response." | service unavailable, status 500, no retry delay |
| `vector_store_timeout` | "Vector store timed out." | service unavailable, status 500, no retry delay |
| `cyber_policy` | "Request flagged." | refused, detail "cyber_policy" |
| `bio_policy` | "Request blocked." | refused, detail "bio_policy" |
| `misalignment_policy_violation` | "Request stopped." | refused, detail "misalignment_policy_violation" |
| `invalid_prompt` | "Invalid prompt." | invalid request, message "Invalid prompt." |
| `data_residency_mismatch` | "Data residency mismatch." | invalid request, message "Data residency mismatch." |
| `new_unknown_code` | "Something went wrong." | invalid response whose description contains "new_unknown_code" and "Something went wrong." |
| null | "Something went wrong." | service unavailable, status 500, no retry delay |
| absent | absent | service unavailable, status 500, no retry delay |
| `500`, a number | "Something went wrong." | invalid response |

#### Scenario: Failed response in the middle of a stream

- **GIVEN** a Responses API stream that delivers the text delta "Hel" and then a `response.failed` event
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel"
- **AND** the stream then fails with the expected error for that event's `response.error`

##### Example: failed response errors

| `response.error` | Expected error |
| ---------------- | -------------- |
| `{"code":"rate_limit_exceeded","message":"Rate limit reached."}` | rate limited, no retry delay |
| `{"code":"server_error","message":"The model failed to generate a response."}` | service unavailable, status 500, no retry delay |
| `{"code":"bio_policy","message":"Request blocked."}` | refused, detail "bio_policy" |
| `{"code":"invalid_prompt","message":"Invalid prompt."}` | invalid request, message "Invalid prompt." |
| `{"code":"new_unknown_code","message":"Something went wrong."}` | invalid response whose description contains "new_unknown_code" and "Something went wrong." |
| absent | service unavailable, status 500, no retry delay |


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

`LKOpenAIClient` SHALL NOT include its API key in the text produced by `String(describing:)`, `String(reflecting:)`, or `dump(_:)` for the client, nor in the description of any error it reports.

#### Scenario: Describe a configured client

- **GIVEN** an `LKOpenAIClient` configured with the API key `sk-proj-secret-123`
- **WHEN** its `String(describing:)` text, its `String(reflecting:)` text, and its `dump(_:)` output are produced
- **THEN** none of them contains `sk-proj-secret-123`
- **AND** the `String(describing:)` text of the error reported for an HTTP 401 response whose `error.message` is "Incorrect API key provided: sk-proj-secret-123." does not contain `sk-proj-secret-123`


<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->

---
### Requirement: Availability through LKAIKit

Code that imports only `LKAIKit` SHALL be able to create an `LKOpenAIClient` from an API key and a `URLSession` and use it as a value of type `any LKAIChatClientProtocol`.

#### Scenario: Create the client through the umbrella module

- **GIVEN** a source file whose only LKAIKit-related import statement is `import LKAIKit`
- **WHEN** the file creates an `LKOpenAIClient` with an API key and a `URLSession` and assigns it to a value of type `any LKAIChatClientProtocol`
- **THEN** the file compiles without an `import LKAIOpenAI` or `import LKAICore` statement

<!-- @trace
source: 02-add-openai-provider
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIOpenAI/LKOpenAIClient.swift
  - Sources/LKAIOpenAI/LKOpenAIErrorBody.swift
  - Sources/LKAIOpenAI/LKOpenAIResponsesRequestBody.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamEvent.swift
  - Sources/LKAIOpenAI/LKOpenAIStreamState.swift
  - Sources/LKAITestSupport/LKAIServerSentEventTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAIServerSentEvent+AnthropicEvents.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIKitTests/ExportsTests.swift
  - Tests/LKAIOpenAITests/LKAIServerSentEvent+OpenAIEvents.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientErrorTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientLiveTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientStreamTests.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTestSupport.swift
  - Tests/LKAIOpenAITests/LKOpenAIClientTests.swift
  - Tests/LKAITestSupportTests/LKAIServerSentEventTestSupportTests.swift
-->