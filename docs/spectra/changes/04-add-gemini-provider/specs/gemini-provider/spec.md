## Purpose

The gemini-provider capability defines how `LKGeminiClient` fulfils the chat-client contract against the Gemini Interactions API `v1`: the HTTP request it sends, the response storage setting, how it maps streamed events, finish reasons, token usage and errors, and how it keeps the API key out of diagnostic output.

## ADDED Requirements

### Requirement: Interactions API request

`LKGeminiClient` SHALL send every chat call, streaming or non-streaming, as a POST request to `https://generativelanguage.googleapis.com/v1/interactions` with the header `x-goog-api-key` set to the configured API key and the header `content-type` set to `application/json`. The JSON body SHALL contain `model`, `input` holding one step per message in order, `generation_config` holding only `max_output_tokens` set to the request's maximum number of output tokens, `stream` set to `true`, `store` as the response storage requirement defines, and `system_instruction` set to the system prompt text only when the request has a system prompt. Each step SHALL be `{"type": <type>, "content": [{"type": "text", "text": <text>}]}`, whose type is `user_input` for a user message and `model_output` for an assistant message. The body SHALL NOT contain `temperature`, `top_p`, `top_k`, or a thinking setting.

#### Scenario: Send a request with a system prompt

- **GIVEN** an `LKGeminiClient` configured with the API key `test-key` and the default response storage setting
- **WHEN** it sends a request with the model `gemini-3.5-flash-lite`, the system prompt "Be brief.", the maximum output tokens 1024, and one user message "Hi"
- **THEN** the recorded request is a POST to `https://generativelanguage.googleapis.com/v1/interactions`
- **AND** its headers include `x-goog-api-key: test-key` and `content-type: application/json`
- **AND** its body, compared as a JSON value, equals `{"model":"gemini-3.5-flash-lite","system_instruction":"Be brief.","input":[{"type":"user_input","content":[{"type":"text","text":"Hi"}]}],"generation_config":{"max_output_tokens":1024},"stream":true,"store":false}`

#### Scenario: Omit the system instruction without a system prompt

- **GIVEN** an `LKGeminiClient` configured with the API key `test-key`
- **WHEN** it sends a request without a system prompt
- **THEN** the recorded JSON body has no `system_instruction` key

#### Scenario: Send the conversation in order

- **GIVEN** an `LKGeminiClient` configured with the API key `test-key`
- **WHEN** it sends a request whose messages are the user message "Hi", the assistant message "Hello!", and the user message "How are you?"
- **THEN** the `input` of the recorded JSON body equals `[{"type":"user_input","content":[{"type":"text","text":"Hi"}]},{"type":"model_output","content":[{"type":"text","text":"Hello!"}]},{"type":"user_input","content":[{"type":"text","text":"How are you?"}]}]`

### Requirement: Response storage setting

`LKGeminiClient` SHALL keep response storage disabled unless the app enables it while creating the client, including when the app creates the client from an API key and a `URLSession` without a storage setting. With response storage disabled, every request body SHALL carry `"store": false`; with response storage enabled, every request body SHALL carry `"store": true`. The client's `Mirror` SHALL report the setting as the child `shouldStoreResponses`.

#### Scenario: Send the storage setting

- **GIVEN** an `LKGeminiClient` created with a response storage setting
- **WHEN** it sends a request
- **THEN** the recorded `store` body field matches the expected value for that setting

##### Example: storage settings

| Setting | `store` body field |
| ------- | ------------------ |
| not set | `false` |
| disabled | `false` |
| enabled | `true` |

#### Scenario: Create a client from a URL session without a storage setting

- **GIVEN** an `LKGeminiClient` created from an API key and a `URLSession` without a storage setting
- **WHEN** an app reads the children of the client's `Mirror`
- **THEN** the child `shouldStoreResponses` is `false`

### Requirement: Stream text mapping

`LKGeminiClient` SHALL read the kind of each streamed event from the `event_type` field of its data. A `step.start` event SHALL record the `step.type` of the step at its `index`; when that type is `model_output` and the step carries a `content` array, each entry of `content` whose `type` is `text` SHALL produce one text-delta event carrying its `text`, in order. A `step.delta` event SHALL produce one text-delta event carrying its `delta.text` when the step at its `index` was started with the type `model_output` and its `delta.type` is `text`. Text-delta events SHALL follow arrival order. Every other event SHALL produce no event, including `interaction.created`, `interaction.status_update`, a `step.start` of a `thought` step with or without a `summary`, a `step.start` of a `model_output` step without `content`, a `step.start` of any other step type whatever its `content`, `step.stop`, a `step.delta` of a `thought` step, a `step.delta` whose `index` no `step.start` has recorded, a `step.delta` whose `delta.type` is not `text`, and event types the client does not know. Event data that is not valid JSON or has no string `event_type`, a `step.start` without a numeric `index` or a string `step.type`, a `step.start` of a `model_output` step whose `content` is present but is not an array of objects with a string `type` or holds an entry of type `text` without a string `text`, a `step.delta` without a numeric `index` or a string `delta.type`, and a `step.delta` whose `delta.type` is `text` without a string `delta.text`, whatever the type of its step and also when no `step.start` has recorded its `index`, SHALL fail the call with an invalid-response error at that event, without delivering the events that follow it. A field whose value is null SHALL count as absent, so a null `delta.text` of a `text` delta SHALL fail the call like a missing one. The client SHALL NOT read the `content` of a `step.start` whose `step.type` is not `model_output`, nor the `delta.text` of a `step.delta` whose `delta.type` is not `text`.

#### Scenario: Skip lifecycle and thought events

- **GIVEN** an Interactions API stream that contains lifecycle events, a thought step, and a model output step
- **WHEN** an app iterates the streaming call
- **THEN** it receives only the text of the model output step, followed by the finished event

##### Example: stream with lifecycle events and a thought step

- **GIVEN** the stream events, in order: `interaction.created`; `interaction.status_update` with status `in_progress`; `step.start` at index 0 with type `thought`; `step.delta` at index 0 with delta type `thought_signature`; `step.delta` at index 0 with delta type `text` and text "Thinking"; `step.stop` at index 0; `step.start` at index 1 with type `model_output`; `step.delta` at index 1 with delta type `text` and text "Hel"; `step.delta` at index 1 with delta type `text` and text "lo"; `step.stop` at index 1; `step.start` at index 2 with type `google_search_call` and content `{"queries":["sky colour"]}`; `step.delta` at index 2 with delta type `google_search_result` and text `{"items":[]}`; `step.stop` at index 2; `interaction.completed` with status `completed`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel", text-delta "lo", and a finished event whose finish reason is completed

#### Scenario: Deliver text carried by the start of a model output step

- **GIVEN** an Interactions API stream whose `step.start` events carry content
- **WHEN** an app iterates the streaming call
- **THEN** it receives the text of the model output step's content and deltas in order, followed by the finished event

##### Example: text in the start of a model output step

- **GIVEN** the stream events, in order: `step.start` at index 0 with type `thought` and summary `[{"type":"text","text":"Thinking"}]`; `step.stop` at index 0; `step.start` at index 1 with type `model_output` and content `[{"type":"text","text":"Hel"}]`; `step.delta` at index 1 with delta type `text` and text "lo"; `step.stop` at index 1; `interaction.completed` with status `completed`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel", text-delta "lo", and a finished event whose finish reason is completed

#### Scenario: Fail on malformed event data

- **GIVEN** an Interactions API stream whose first event data is not valid JSON, followed by a `step.start` of a `model_output` step, a `step.delta` with text "Hel", and an `interaction.completed` event with status `completed`
- **WHEN** an app iterates the streaming call
- **THEN** the stream fails with an invalid-response error
- **AND** the app receives no text-delta event

#### Scenario: Fail on events missing required fields

- **GIVEN** an Interactions API stream that delivers a `step.start` at index 1 with type `model_output`, then an event with missing or mistyped fields, then a `step.delta` at index 1 with delta type `text` and text "Hel", and then an `interaction.completed` event with status `completed`
- **WHEN** an app iterates the streaming call
- **THEN** the stream fails with an invalid-response error
- **AND** the app receives no text-delta event

##### Example: events missing required fields

| Event data | Missing or mistyped field |
| ---------- | ------------------------- |
| `{"index":2,"step":{"type":"model_output"}}` | `event_type` |
| `{"event_type":"step.start","step":{"type":"model_output"}}` | `index` of `step.start` |
| `{"event_type":"step.start","index":2,"step":{}}` | `step.type` |
| `{"event_type":"step.start","index":2,"step":{"type":"model_output","content":[{"type":"text"}]}}` | `text` of a content entry of type `text` |
| `{"event_type":"step.delta","delta":{"type":"text","text":"x"}}` | `index` of `step.delta` |
| `{"event_type":"step.delta","index":1,"delta":{"text":"x"}}` | `delta.type` |
| `{"event_type":"step.delta","index":1,"delta":{"type":"text"}}` | `delta.text` of a `text` delta |
| `{"event_type":"step.delta","index":3,"delta":{"type":"text","text":5}}` | `delta.text` that is not a string, at an index no `step.start` has recorded |
| `{"event_type":"step.delta","index":3,"delta":{"type":"text","text":null}}` | null `delta.text` of a `text` delta, at an index no `step.start` has recorded |

### Requirement: Finish mapping

`LKGeminiClient` SHALL end the stream at the first `interaction.completed` or `error` event, and SHALL NOT act on any event after it. An `interaction.completed` event SHALL be mapped by the `status` of its `interaction`: `completed` to a finished event whose finish reason is completed; `incomplete` to a finished event whose finish reason is max output tokens; `failed` by the first entry of `interaction.errors` with the code rules the error mapping requirement defines for the `error` object of an `error` event, where `errors` counts as decodable when it is an array whose entries are objects whose `code` and `message`, when present, are strings or null; when `errors` is absent, null, or empty, as service unavailable with status 500 and no retry delay, following the unrecognized stream errors requirement of the chat-client capability; with `errors` in any other shape, as an invalid-response error; and any other status, or a missing status, to an invalid-response error. The client SHALL NOT read the `errors` of an `interaction` whose status is not `failed`. An `interaction.completed` event without an `interaction` object SHALL fail the call with an invalid-response error. Because the Interactions API reports generation that fills the model's context window with the same status `incomplete`, the client SHALL NOT report the finish reason context window exceeded. Text deltas delivered before the end of the stream SHALL stay delivered.

#### Scenario: Map terminal events

- **GIVEN** an Interactions API stream that delivers the text delta "Hel", then an `interaction.completed` event, and then another `interaction.completed` event with status `completed`
- **WHEN** an app iterates the streaming call to its end
- **THEN** it receives text-delta "Hel"
- **AND** the outcome after it matches the expected result for the first `interaction.completed` event

##### Example: terminal events

| First `interaction.completed` event | Expected result |
| ----------------------------------- | --------------- |
| status `completed` | finished event, finish reason completed |
| status `completed`, `errors` is `"none"` | finished event, finish reason completed |
| status `incomplete` | finished event, finish reason max output tokens |
| status `failed`, `errors` is `[{"code":"safety","message":"Blocked."}]` | refused, detail "safety" |
| status `failed`, `errors` is `[{"code":"api_error","message":"Internal error."}]` | service unavailable, status 500, no retry delay |
| status `failed`, without `errors` | service unavailable, status 500, no retry delay |
| status `failed`, `errors` is `null` | service unavailable, status 500, no retry delay |
| status `failed`, `errors` is `[]` | service unavailable, status 500, no retry delay |
| status `failed`, `errors` is `[{"code":500,"message":"Internal error."}]` | invalid-response error |
| status `requires_action` | invalid-response error |
| status `cancelled` | invalid-response error |
| without `status` | invalid-response error |
| without an `interaction` object | invalid-response error |

#### Scenario: Finish at the output token limit while still thinking

- **GIVEN** an Interactions API stream with a thought step and no model output step, ending with an `interaction.completed` event with status `incomplete`
- **WHEN** an app awaits the non-streaming call
- **THEN** the result has empty text and the finish reason max output tokens

### Requirement: Responding model

`LKGeminiClient` SHALL report as the responding model of a finished event the `model` of the `interaction` in the `interaction.completed` event that ends the stream, and SHALL report no responding model when that `interaction` has no `model`.

#### Scenario: Report the model of the completed interaction

- **GIVEN** an Interactions API stream for a request with the model `gemini-3.5-flash` whose `interaction.completed` event carries an interaction with the model `gemini-3.6-flash`
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event's responding model is `gemini-3.6-flash`

### Requirement: Usage mapping

`LKGeminiClient` SHALL report token usage from the `interaction.usage` of the `interaction.completed` event that ends the stream with a finished event: the total input tokens equal to `total_input_tokens`, the cached input tokens equal to `total_cached_tokens`, the total output tokens equal to `total_output_tokens` plus `total_thought_tokens`, and the reasoning output tokens equal to `total_thought_tokens`. A missing `total_thought_tokens` SHALL count as zero in the total output tokens and SHALL leave the reasoning output count absent; a missing `total_cached_tokens` SHALL leave the cached input count absent. When `usage` is null or absent, or reports no `total_input_tokens` or no `total_output_tokens`, the finished event SHALL carry no usage.

#### Scenario: Map the usage of the completed interaction

- **GIVEN** an Interactions API stream whose `interaction.completed` event carries an interaction with a `usage` value
- **WHEN** an app iterates the streaming call to the finished event
- **THEN** the finished event carries the expected usage

##### Example: usage values

| `usage` | Expected usage |
| ------- | -------------- |
| `{"total_input_tokens":41,"total_cached_tokens":0,"total_output_tokens":3,"total_thought_tokens":528,"total_tokens":572}` | total input 41, cached input 0, total output 531, reasoning output 528 |
| `{"total_input_tokens":5000,"total_cached_tokens":2033,"total_output_tokens":10,"total_thought_tokens":0,"total_tokens":5010}` | total input 5000, cached input 2033, total output 10, reasoning output 0 |
| `{"total_input_tokens":12,"total_output_tokens":5,"total_tokens":17}` | total input 12, no cached input count, total output 5, no reasoning count |
| `null` | no usage |
| `{"total_output_tokens":5}` | no usage |

### Requirement: Error mapping

In this requirement, the blocked codes are `safety`, `jailbreak`, `prohibited_content`, `blocklist`, `recitation`, `language`, `spii`, `content_blocked`, `image_safety`, `image_prohibited_content`, `image_recitation`, and `image_other`, and the quota codes are `quota_exceeded` and `payment_required`.

`LKGeminiClient` SHALL classify an HTTP response whose status code is outside 200-299 by its JSON body, which comes in two formats. The Interactions format is a JSON object holding an `error` object whose `code` and `message`, when present, are strings or null. The Google generic format is a JSON object holding an `error` object whose `code` is a number, or a JSON array whose first element is such an object; within the `error` object, `message` and `status`, when present, are strings, and `details`, when present, is an array of objects whose `reason`, when present, is a string. For the Interactions format the client SHALL apply the first rule that matches: a blocked code in `error.code` SHALL be reported as refused with the code as detail; a quota code SHALL be reported as quota exceeded; and any other body whose status code is a 4xx status other than 401, 402, 403, and 429 SHALL be reported as invalid request carrying `error.message`. For the Google generic format, an entry of `error.details` whose `reason` is `API_KEY_INVALID` SHALL be reported as invalid API key. Every other response, including a body in neither format, SHALL fall back to the default HTTP status classification of the chat-client capability.

An `error` event SHALL be classified by the `code` of its `error` object: a blocked code as refused with the code as detail; `rate_limit_exceeded` and `too_many_requests` as rate limited with no retry delay; a quota code as quota exceeded; `api_error` as service unavailable with status 500, `bad_gateway` with status 502, `service_unavailable` with status 503, and `deadline_exceeded` and `gateway_timeout` with status 504, all with no retry delay because a stream carries no headers; `authentication` as invalid API key; `permission_denied` as permission denied; `invalid_request` as invalid request carrying the `message`; and, following the unrecognized stream errors requirement of the chat-client capability with `error.code` as the error code, any other code that is not null as an invalid-response error whose description contains the code and the `message`, and a null or absent code as service unavailable with status 500 and no retry delay. The data of an `error` event SHALL count as decodable when it is a JSON object holding an `error` object whose `code` and `message`, when present, are strings or null; any other data, including data without an `error` object, SHALL be reported as an invalid-response error.

#### Scenario: Classify HTTP error responses

- **GIVEN** an HTTP error response from the Interactions API
- **WHEN** an app awaits the non-streaming call
- **THEN** the call fails with the expected error for that response

##### Example: error responses

| Status | Body | Other response data | Expected error |
| ------ | ---- | ------------------- | -------------- |
| 400 | `{"error":{"message":"Input blocked: prohibited content.","code":"prohibited_content"}}` | none | refused, detail "prohibited_content" |
| 400 | `{"error":{"message":"The response was blocked.","code":"safety"}}` | none | refused, detail "safety" |
| 402 | `{"error":{"message":"Your Prepay credit balance is depleted.","code":"payment_required"}}` | none | quota exceeded |
| 429 | `{"error":{"message":"You have exceeded your daily quota.","code":"quota_exceeded"}}` | header `retry-after: 20` | quota exceeded |
| 429 | `{"error":{"message":"Rate limit exceeded. Please retry in 27s.","code":"too_many_requests"}}` | header `retry-after: 27` | rate limited, retry delay 27 seconds |
| 429 | `{"error":{"message":"Rate limit exceeded.","code":"rate_limit_exceeded"}}` | none | rate limited, no retry delay |
| 400 | `{"error":{"message":"max_output_tokens greater than 1048576 is not supported.","code":"invalid_request"}}` | none | invalid request, message "max_output_tokens greater than 1048576 is not supported." |
| 404 | `{"error":{"message":"Model 'gemini-0' not found.","code":"not_found"}}` | none | invalid request, message "Model 'gemini-0' not found." |
| 400 | `{"error":{"code":"invalid_request"}}` | none | invalid request without a message |
| 503 | `{"error":{"message":"This model is currently experiencing high demand.","code":"service_unavailable"}}` | header `retry-after: 5` | service unavailable, status 503, retry delay 5 seconds |
| 500 | `{"error":{"message":"An internal error has occurred.","code":"api_error"}}` | none | service unavailable, status 500, no retry delay |
| 400 | `[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}]` | none | invalid API key |
| 401 | `[{"error":{"code":401,"message":"API key not valid. Please pass a valid API key.","status":"UNAUTHENTICATED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_TOKEN_TYPE_UNSUPPORTED"}]}}]` | none | invalid API key |
| 403 | `[{"error":{"code":403,"message":"Permission denied on the service.","status":"PERMISSION_DENIED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_DENIED"}]}}]` | none | permission denied |
| 400 | `{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}` | none | invalid API key |
| 400 | `[{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}]` | none | invalid request without a message |
| 400 | `[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]` | none | invalid request without a message |
| 502 | body is not JSON | none | service unavailable, status 502, no retry delay |

#### Scenario: Error event in the middle of a stream

- **GIVEN** an Interactions API stream that delivers the text delta "Hel", then an `error` event, and then an `interaction.completed` event with status `completed`
- **WHEN** an app iterates the streaming call
- **THEN** it receives text-delta "Hel"
- **AND** the stream then fails with the expected error for that event's data

##### Example: error event data

| `error` event data | Expected error |
| ------------------ | -------------- |
| `{"event_type":"error","error":{"code":"safety","message":"Blocked."}}` | refused, detail "safety" |
| `{"event_type":"error","error":{"code":"recitation","message":"Blocked."}}` | refused, detail "recitation" |
| `{"event_type":"error","error":{"code":"rate_limit_exceeded","message":"Rate limit exceeded."}}` | rate limited, no retry delay |
| `{"event_type":"error","error":{"code":"too_many_requests","message":"Too many requests."}}` | rate limited, no retry delay |
| `{"event_type":"error","error":{"code":"quota_exceeded","message":"Daily quota exceeded."}}` | quota exceeded |
| `{"event_type":"error","error":{"code":"api_error","message":"Internal error."}}` | service unavailable, status 500, no retry delay |
| `{"event_type":"error","error":{"code":"bad_gateway","message":"Bad gateway."}}` | service unavailable, status 502, no retry delay |
| `{"event_type":"error","error":{"code":"service_unavailable","message":"High demand."}}` | service unavailable, status 503, no retry delay |
| `{"event_type":"error","error":{"code":"gateway_timeout","message":"Deadline expired before operation could complete."}}` | service unavailable, status 504, no retry delay |
| `{"event_type":"error","error":{"code":"deadline_exceeded","message":"Deadline exceeded."}}` | service unavailable, status 504, no retry delay |
| `{"event_type":"error","error":{"code":"authentication","message":"API key not valid."}}` | invalid API key |
| `{"event_type":"error","error":{"code":"permission_denied","message":"Permission denied."}}` | permission denied |
| `{"event_type":"error","error":{"code":"invalid_request","message":"Invalid request."}}` | invalid request, message "Invalid request." |
| `{"event_type":"error","error":{"code":"new_unknown_code","message":"Something went wrong."}}` | invalid response whose description contains "new_unknown_code" and "Something went wrong." |
| `{"event_type":"error","error":{"code":null,"message":"Something went wrong."}}` | service unavailable, status 500, no retry delay |
| `{"event_type":"error","error":{}}` | service unavailable, status 500, no retry delay |
| `{"event_type":"error"}` | invalid response |
| `{"event_type":"error","error":{"code":500,"message":"Something went wrong."}}` | invalid response |

### Requirement: API key secrecy

`LKGeminiClient` SHALL NOT include its API key in the text produced by `String(describing:)`, `String(reflecting:)`, or `dump(_:)` for the client, nor in the description of any error it reports.

#### Scenario: Describe a configured client

- **GIVEN** an `LKGeminiClient` configured with the API key `AQ.secret-123`
- **WHEN** its `String(describing:)` text, its `String(reflecting:)` text, and its `dump(_:)` output are produced
- **THEN** none of them contains `AQ.secret-123`
- **AND** the `String(describing:)` text of the error reported for an HTTP 401 response whose `error.message` is "API key not valid: AQ.secret-123." does not contain `AQ.secret-123`

### Requirement: Availability through LKAIKit

Code that imports only `LKAIKit` SHALL be able to create an `LKGeminiClient` from an API key and a `URLSession` and use it as a value of type `any LKAIChatClientProtocol`.

#### Scenario: Create the client through the umbrella module

- **GIVEN** a source file whose only LKAIKit-related import statement is `import LKAIKit`
- **WHEN** the file creates an `LKGeminiClient` with an API key and a `URLSession` and assigns it to a value of type `any LKAIChatClientProtocol`
- **THEN** the file compiles without an `import LKAIGemini` or `import LKAICore` statement
