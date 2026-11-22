## MODIFIED Requirements

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
