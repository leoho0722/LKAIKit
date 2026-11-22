## MODIFIED Requirements

### Requirement: Error mapping

In this requirement, the policy codes are `cyber_policy`, `bio_policy`, and `misalignment_policy_violation`, and the quota codes are `insufficient_quota`, `billing_hard_limit_reached`, `credit_balance_exhausted`, `organization_spend_limit_exceeded`, `project_spend_limit_exceeded`, and `organization_usage_limit_exceeded`.

`LKOpenAIClient` SHALL classify an HTTP response whose status code is outside 200-299 by the `error` object in its JSON body, applying the first rule that matches: a policy code in `error.code` SHALL be reported as refused with the code as detail; a quota code in `error.code`, or `error.type` equal to `insufficient_quota`, SHALL be reported as quota exceeded; any other decodable body whose status code is a 4xx status other than 401, 402, 403, and 429 SHALL be reported as invalid request carrying `error.message`. Every other response, including a body it cannot decode, SHALL fall back to the default HTTP status classification of the chat-client capability. The body SHALL count as decodable when it holds an `error` object, whether or not `error.message`, `error.type`, or `error.code` is present.

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
