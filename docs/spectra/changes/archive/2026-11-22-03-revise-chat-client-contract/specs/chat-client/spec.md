## MODIFIED Requirements

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

## ADDED Requirements

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
