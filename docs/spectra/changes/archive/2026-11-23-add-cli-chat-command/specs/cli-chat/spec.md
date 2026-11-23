## Purpose

The cli-chat capability defines how the `lkai` root command turns command-line input into one chat request against Anthropic, OpenAI or Google Gemini, and how it reports the answer, an incomplete answer or a failure through stdout, stderr and the exit status, so that CI/CD pipelines can consume the result.

## ADDED Requirements

### Requirement: Help when no chat option is given

When `lkai` runs without any of the options `--provider`, `-m`/`--model`, `-p`/`--prompt` and `-f`/`--prompt-file`, it SHALL print the usage information to stdout, SHALL print nothing to stderr, SHALL NOT send any chat request, and SHALL exit with status 0. Other options given alone with values that swift-argument-parser accepts, such as `--stream`, `--apiKey`, `--max-output-tokens`, `--timeout` or `--output-language`, SHALL NOT change this behavior. When the version flag or the help flag is given, or swift-argument-parser rejects the input, the requirement that covers that case applies instead of this requirement.

#### Scenario: Only a non-chat option is given

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai --stream` runs
- **THEN** stdout contains `USAGE: lkai`
- **AND** stderr is empty
- **AND** no chat request is sent
- **AND** the process exits with status 0

### Requirement: Chat request construction

When the input passes validation, `lkai` SHALL send exactly one chat request through the client of the selected provider, created with that client's default settings and an ephemeral `URLSession` configured as described in "Network timeout". The request SHALL use the `--model` value unchanged as the model, SHALL contain exactly one message whose role is user and whose text is the prompt text unchanged, SHALL have no system prompt, and SHALL use the `--max-output-tokens` value as the maximum output tokens, which is 4096 when the option is not given.

#### Scenario: Map the provider to its client

- **GIVEN** valid input with a prompt and an API key
- **WHEN** `lkai` runs with `--provider <provider>`
- **THEN** the request is sent through the client listed for that provider

##### Example: provider values

| `--provider` value | Client | Client description |
| ------------------ | ------ | ------------------ |
| `anthropic` | `LKAnthropicClient` | `LKAnthropicClient(refusalFallback: disabled)` |
| `openai` | `LKOpenAIClient` | `LKOpenAIClient(shouldStoreResponses: false)` |
| `google` | `LKGeminiClient` | `LKGeminiClient(shouldStoreResponses: false)` |

#### Scenario: Build the request from the options

- **GIVEN** the API key `sk-test` is given with `--apiKey`
- **WHEN** `lkai --provider anthropic -m claude-opus-5-5 -p "Reply with OK."` runs
- **THEN** the request's model is `claude-opus-5-5`
- **AND** the request's messages are exactly one user message with the text `Reply with OK.`
- **AND** the request's system prompt is nil
- **AND** the request's maximum output tokens is 4096

#### Scenario: Send the prompt file content unchanged

- **GIVEN** a UTF-8 file `prompt.md` whose content is `# Title` followed by an LF and `Body` followed by an LF
- **WHEN** `lkai --provider openai -m gpt-6-luna -f prompt.md --apiKey sk-test` runs
- **THEN** the text of the request's only message is the file content, including the trailing LF

### Requirement: Prompt sources

`lkai` SHALL take the prompt from exactly one of `-p`/`--prompt` and `-f`/`--prompt-file`. A prompt file SHALL be accepted only when its path extension, compared case-insensitively, is `txt` or `md`, and its content SHALL be read as UTF-8. A prompt that is empty or consists only of whitespace and line terminators SHALL be rejected, whichever option supplied it. A prompt text that begins with `-` followed by at least one more character, passed as the separate argument after `-p` or `--prompt`, SHALL be rejected by swift-argument-parser with exit status 64; the same text SHALL be accepted when passed as `--prompt=<text>` or through `--prompt-file`, and the help text of `--prompt` SHALL name these two alternatives in both output languages. A prompt that is exactly `-` SHALL be accepted as the separate argument.

#### Scenario: Check the prompt file extension

- **GIVEN** a readable UTF-8 file with non-blank content at the given path
- **WHEN** `lkai` runs with `--prompt-file <path>` and otherwise valid input
- **THEN** the file is accepted or rejected as listed

##### Example: prompt file paths

| Path | Result |
| ---- | ------ |
| `notes.txt` | accepted |
| `README.MD` | accepted |
| `docs/plan.Md` | accepted |
| `prompt.markdown` | rejected |
| `prompt` | rejected |
| `prompt.txt.bak` | rejected |

#### Scenario: Reject a blank prompt

- **GIVEN** otherwise valid input
- **WHEN** `lkai` runs with the blank prompt source listed
- **THEN** the input is rejected as described in "Input validation failures"
- **AND** stderr's first line contains the token listed

##### Example: blank prompt sources

| Prompt source | Token in the message |
| ------------- | -------------------- |
| `--prompt` set to a string made only of spaces, tabs and LF characters | `--prompt` |
| `--prompt-file blank.md`, where `blank.md` contains only spaces and LF characters | `blank.md` |

#### Scenario: Pass a prompt that begins with a dash

- **GIVEN** otherwise valid input
- **WHEN** `lkai` runs with the prompt arguments listed
- **THEN** the result is the one listed

##### Example: dash-prefixed prompt text

| Prompt arguments | Result |
| ---------------- | ------ |
| `-p "- item"` | exit status 64, stderr's first line is `Error: Missing value for '-p <prompt>'` |
| `-p "--- a/file"` | exit status 64, stderr's first line is `Error: Invalid option: --- a/file` |
| `-p -` | accepted, the message text is `-` |
| `"--prompt=- item"` | accepted, the message text is `- item` |
| `"--prompt=--- a/file"` | accepted, the message text is `--- a/file` |

#### Scenario: Name the alternatives in the prompt help

- **GIVEN** the output language listed
- **WHEN** the help of `lkai` is generated
- **THEN** the help text of `--prompt` contains `--prompt=` and `--prompt-file`

##### Example: help languages

| Output language |
| --------------- |
| `en-US` |
| `zh-TW` |

### Requirement: API key resolution

`lkai` SHALL use the `--apiKey` value as the API key when it is not empty. Otherwise it SHALL use the value of the environment variable listed for the selected provider when that value is not empty. When neither is available, the input SHALL be rejected with a message that names both `--apiKey` and that environment variable. The help of `lkai` SHALL list the environment variable of every provider in both output languages. The text that `lkai` writes itself, namely the help, the messages of the input validation failures, the warnings, and the `Error: ` and `Details: ` lines it writes for service failures and answer write failures, SHALL NOT contain the API key. The error messages that swift-argument-parser generates repeat an argument it cannot parse as given, so a key passed as a stray argument appears in that message. The answer text SHALL be written as received, without redaction, so an answer that repeats a key contained in the prompt reaches stdout unchanged.

#### Scenario: Choose the API key source

- **GIVEN** the provider `openai`
- **WHEN** `lkai` resolves the API key from the inputs listed
- **THEN** the resolved key is the one listed

##### Example: key sources for openai

| `--apiKey` | `LKAI_OPENAI_API_KEY` | Resolved key |
| ---------- | --------------------- | ------------ |
| `sk-flag` | `sk-env` | `sk-flag` |
| not given | `sk-env` | `sk-env` |
| empty string | `sk-env` | `sk-env` |
| not given | not set | rejected, message names `--apiKey` and `LKAI_OPENAI_API_KEY` |
| not given | empty string | rejected, message names `--apiKey` and `LKAI_OPENAI_API_KEY` |

#### Scenario: Read the environment variable of the selected provider

- **GIVEN** `--apiKey` is not given
- **AND** `LKAI_ANTHROPIC_API_KEY`, `LKAI_OPENAI_API_KEY` and `LKAI_GEMINI_API_KEY` are all set, each to a different value
- **WHEN** `lkai` runs with `--provider <provider>`
- **THEN** the API key is the value of the environment variable listed for that provider

##### Example: environment variables

| `--provider` value | Environment variable |
| ------------------ | -------------------- |
| `anthropic` | `LKAI_ANTHROPIC_API_KEY` |
| `openai` | `LKAI_OPENAI_API_KEY` |
| `google` | `LKAI_GEMINI_API_KEY` |

#### Scenario: List every environment variable in the help

- **GIVEN** the output language `en-US` or `zh-TW`
- **WHEN** the help of `lkai` is generated
- **THEN** it contains the environment variable of every `--provider` value listed in "environment variables"

#### Scenario: Keep the key out of error output

- **GIVEN** the API key `sk-secret-123` is given with `--apiKey`
- **WHEN** `lkai --provider openai -m gpt-6-luna -p hi --apiKey sk-secret-123 --max-output-tokens 0` runs
- **THEN** stderr's first line starts with `Error: ` and contains `--max-output-tokens`
- **AND** neither stdout nor stderr contains `sk-secret-123`
- **AND** the process exits with status 64

#### Scenario: Write an answer that repeats the key unchanged

- **GIVEN** the API key in use is `sk-secret-123`
- **AND** the chat call completes with the finish reason `completed` and the text `key: sk-secret-123`
- **WHEN** `lkai` runs without `--stream`
- **THEN** stdout is exactly `key: sk-secret-123` followed by an LF
- **AND** stderr is empty

### Requirement: Network timeout

`lkai` SHALL accept `--timeout <seconds>`, an integer that SHALL be at least 1 and is 60 when the option is not given. It SHALL use the value as the longest time to wait without receiving any data from the AI service, both before the response starts and between two pieces of the response, by setting it as the request timeout interval of the ephemeral `URLSession` configuration. When the time elapses, the chat call fails with `transport(underlying: URLError(.timedOut))`, which is reported as described in "Service failure reporting".

#### Scenario: Configure the timeout

- **GIVEN** otherwise valid input
- **WHEN** `lkai` runs with the timeout arguments listed
- **THEN** the request timeout interval of the session configuration used for the request is the value listed

##### Example: timeout values

| Timeout arguments | Request timeout interval |
| ----------------- | ------------------------ |
| none | 60 seconds |
| `--timeout 300` | 300 seconds |
| `--timeout 1` | 1 second |

#### Scenario: Report a timeout

- **GIVEN** the output language `en-US`
- **WHEN** the chat call fails with `transport(underlying: URLError(.timedOut))`
- **THEN** stderr's second line is exactly `Details: URLError -1001`
- **AND** the process exits with status 1

### Requirement: Input validation failures

When at least one chat option is given and the input is invalid, `lkai` SHALL check the rules below in the listed order and report only the first rule that fails. It SHALL print to stderr a first line that starts with `Error: ` and names the option, file path or environment variable listed for that rule, followed by the usage information; SHALL print nothing to stdout; SHALL NOT send any chat request; and SHALL exit with status 64. Values that swift-argument-parser itself rejects, such as an unknown `--provider` value or a non-integer `--max-output-tokens`, SHALL also exit with status 64.

#### Scenario: Report the first failing rule

- **GIVEN** the `lkai` executable built on macOS 26 or later and no `LKAI_*_API_KEY` environment variable set
- **WHEN** `lkai` runs with input that breaks a rule listed below
- **THEN** stderr's first line starts with `Error: ` and contains the named token
- **AND** stdout is empty
- **AND** the process exits with status 64

##### Example: validation rules in order

| Order | Rule broken | Example input | Named token |
| ----- | ----------- | ------------- | ----------- |
| 1 | `--provider` is missing | `-m x -p hi` | `--provider` |
| 2 | `--model` is missing or empty | `--provider openai -p hi` | `--model` |
| 3 | both prompt options are given | `--provider openai -m x -p hi -f a.txt` | `--prompt-file` |
| 4 | neither prompt option is given | `--provider openai -m x` | `--prompt` |
| 5 | the prompt file extension is not `txt` or `md` | `--provider openai -m x -f a.json` | `--prompt-file` |
| 6 | the prompt file cannot be read as UTF-8 | `--provider openai -m x -f missing.txt` | `missing.txt` |
| 7 | the prompt is blank | `--provider openai -m x -p " "` | `--prompt` |
| 8 | `--max-output-tokens` is less than 1 | `--provider openai -m x -p hi --max-output-tokens 0` | `--max-output-tokens` |
| 9 | `--timeout` is less than 1 | `--provider openai -m x -p hi --timeout 0` | `--timeout` |
| 10 | no API key is available | `--provider openai -m x -p hi` | `LKAI_OPENAI_API_KEY` |

#### Scenario: Reject a value the parser does not accept

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai --provider bogus -m x -p hi` runs
- **THEN** stderr's first line starts with `Error: ` and contains `bogus`
- **AND** stdout is empty
- **AND** the process exits with status 64

### Requirement: Invoke output

Without `--stream`, `lkai` SHALL wait until the whole answer is complete and only then write the answer text to stdout. When the text is not empty and its last byte in UTF-8 is not LF, it SHALL write one LF after the text. Nothing else SHALL be written to stdout. When the finish reason is `completed` and every write to stdout succeeds, stderr SHALL be empty and the process SHALL exit with status 0. A failed write to stdout is handled as described in "Answer write failure".

#### Scenario: Print the complete answer

- **GIVEN** the chat call completes with the finish reason `completed` and the text listed
- **WHEN** `lkai` runs without `--stream`
- **THEN** stdout is exactly the output listed
- **AND** stderr is empty
- **AND** the process exits with status 0

##### Example: trailing line terminator

| Answer text | stdout |
| ----------- | ------ |
| `Hello` | `Hello` followed by an LF |
| `Hello` followed by an LF | `Hello` followed by an LF |
| `Hello` followed by a CR and an LF | `Hello` followed by a CR and an LF |
| empty | empty |

### Requirement: Stream output

With `--stream`, `lkai` SHALL write each text delta to stdout as soon as it is received, before reading the next stream event. After the stream ends, whether it finishes or fails, `lkai` SHALL write one LF when at least one byte was written and the last written byte is not LF. Nothing else SHALL be written to stdout. When the finish reason is `completed` and every write to stdout succeeds, stderr SHALL be empty and the process SHALL exit with status 0. A failed write to stdout is handled as described in "Answer write failure". When the stream ends without a finish event and without an error, `lkai` SHALL report it as `invalidResponse(reason: "Stream ended before a finish event")`, as described in "Service failure reporting".

#### Scenario: Write deltas as they arrive

- **GIVEN** a stream that yields the text deltas `Hel` and `lo`, then a finish event with the reason `completed`
- **WHEN** `lkai --stream` handles the stream
- **THEN** `Hel` is written to stdout before the second event is read
- **AND** stdout is exactly `Hello` followed by an LF
- **AND** the process exits with status 0

#### Scenario: Apply the trailing line terminator rule to a stream

- **GIVEN** a stream that yields the text deltas listed, then a finish event with the reason `completed`
- **WHEN** `lkai --stream` handles the stream
- **THEN** stdout is exactly the output listed

##### Example: streamed line terminators

| Text deltas | stdout |
| ----------- | ------ |
| `Hel`, `lo` | `Hello` followed by an LF |
| `Hel`, `lo` followed by an LF | `Hello` followed by an LF |
| `Hel`, `lo` followed by a CR and an LF | `Hello` followed by a CR and an LF |
| `Hel`, an empty string | `Hel` followed by an LF |
| none | empty |

#### Scenario: Report a stream that ends without a finish event

- **GIVEN** the output language `en-US`
- **AND** a stream that yields the text delta `Hel` and then ends without a finish event or an error
- **WHEN** `lkai --stream` handles the stream
- **THEN** stdout is exactly `Hel` followed by an LF
- **AND** stderr's second line is exactly `Details: Stream ended before a finish event`
- **AND** the process exits with status 1

### Requirement: Incomplete answer reporting

When the finish event's reason is anything other than `completed`, `lkai` SHALL still write the answer text to stdout as described for the output mode in use, SHALL write a warning to stderr whose first line starts with `Warning: `, and SHALL exit with status 2. When a write to stdout fails, "Answer write failure" applies instead of this requirement.

#### Scenario: Warn about an answer that stopped early

- **GIVEN** the output language `en-US`
- **AND** the chat call ends with the finish reason listed and the text `Partial`
- **WHEN** `lkai` runs with and without `--stream`
- **THEN** stdout is exactly `Partial` followed by an LF in both modes
- **AND** stderr's first line starts with `Warning: ` and contains the token listed
- **AND** the process exits with status 2

##### Example: finish reasons

| Finish reason | Token in the warning |
| ------------- | -------------------- |
| `maxOutputTokens` | `--max-output-tokens` |
| `contextWindowExceeded` | `context window` |

### Requirement: Service failure reporting

When the chat call fails with an `LKAIError`, `lkai` SHALL write to stderr a first line that is `Error: ` followed by the error's description in the output language. When the error carries technical detail, it SHALL write a second line that is `Details: ` followed by the detail listed below, untranslated, with every occurrence of the API key in use replaced by `[REDACTED]`. Apart from that replacement, the detail SHALL be written as the provider gave it, so a detail that contains LF or CR characters spans more than one line of stderr. It SHALL NOT print the usage information, and SHALL exit with status 1. Without `--stream`, stdout SHALL be empty. With `--stream`, stdout SHALL contain only the text received before the failure, followed by the line terminator rule of "Stream output". When a write to stdout fails, "Answer write failure" applies instead of this requirement.

#### Scenario: Report the error and its detail

- **GIVEN** the output language `en-US`
- **WHEN** the chat call fails with the error listed, without `--stream`
- **THEN** stderr's first line is `Error: ` followed by the `en` description of that error
- **AND** stderr's second line is the one listed, or stderr has only one line when none is listed
- **AND** stdout is empty
- **AND** the process exits with status 1

##### Example: detail lines

| Error | Second line of stderr |
| ----- | --------------------- |
| `invalidRequest(message: "model not found")` | `Details: model not found` |
| `invalidRequest(message: nil)` | none |
| `refused(detail: "cyber")` | `Details: cyber` |
| `refused(detail: nil)` | none |
| `invalidResponse(reason: "Stream ended before a finish event")` | `Details: Stream ended before a finish event` |
| `transport(underlying: URLError(.timedOut))` | `Details: URLError -1001` |
| `rateLimited(retryAfter: .seconds(30))` | `Details: retry after 30 seconds` |
| `rateLimited(retryAfter: nil)` | none |
| `serviceUnavailable(statusCode: 503, retryAfter: nil)` | `Details: status 503` |
| `serviceUnavailable(statusCode: 529, retryAfter: .seconds(10))` | `Details: status 529, retry after 10 seconds` |
| `invalidAPIKey`, `permissionDenied`, `quotaExceeded`, `cancelled` | none |

#### Scenario: Redact the API key in the detail

- **GIVEN** the API key in use is `sk-secret-123`
- **WHEN** the chat call fails with `invalidRequest(message: "Incorrect API key provided: sk-secret-123")`
- **THEN** stderr's second line is exactly `Details: Incorrect API key provided: [REDACTED]`
- **AND** stderr does not contain `sk-secret-123`

#### Scenario: Keep a multi-line detail as received

- **GIVEN** the output language `en-US`
- **WHEN** the chat call fails with `invalidRequest(message:)` whose message is `first`, an LF and `second`, without `--stream`
- **THEN** stderr is exactly `Error: ` followed by the `en` description of `invalidRequest`, an LF, `Details: first`, an LF, `second` and an LF
- **AND** the process exits with status 1

#### Scenario: Keep partial streamed text on failure

- **GIVEN** a stream that yields the text delta `Hel`, then fails with `serviceUnavailable(statusCode: 500, retryAfter: nil)`
- **WHEN** `lkai --stream` handles the stream
- **THEN** stdout is exactly `Hel` followed by an LF
- **AND** that LF is written to stdout before anything is written to stderr
- **AND** stderr's first line starts with `Error: `
- **AND** the process exits with status 1

#### Scenario: Fail a stream before any text

- **GIVEN** a stream that fails with `serviceUnavailable(statusCode: 500, retryAfter: nil)` before yielding any text
- **WHEN** `lkai --stream` handles the stream
- **THEN** stdout is empty
- **AND** the process exits with status 1

### Requirement: Answer write failure

When a write to stdout fails with an error while `lkai` writes the answer text, a text delta or the trailing LF, `lkai` SHALL stop writing the answer, and with `--stream` it SHALL NOT read another stream event. It SHALL write to stderr a first line that is `Error: ` followed by the answer write failure message in the output language, and a second line that is `Details: ` followed by the error's domain, a space and the error's code, untranslated, for example `Details: NSCocoaErrorDomain 640`. It SHALL NOT write a `Warning: ` line, even when the finish reason is not `completed`, and SHALL exit with status 1. A failed write to stderr SHALL be ignored. When stdout is a pipe whose reading end has closed, the operating system terminates the process with SIGPIPE before any write error is reported, so that case is outside this requirement.

#### Scenario: Report a failed write of the answer

- **GIVEN** the output language `en-US`
- **AND** the chat call completes with the finish reason `completed` and the text `Hello`
- **AND** the write listed fails with `CocoaError(.fileWriteOutOfSpace)`
- **WHEN** `lkai` runs without `--stream`
- **THEN** stderr's first line is `Error: ` followed by the `en` answer write failure message
- **AND** stderr's second line is exactly `Details: NSCocoaErrorDomain 640`
- **AND** the process exits with status 1

##### Example: failing writes

| Failing write | Writes attempted to stdout |
| ------------- | -------------------------- |
| the answer text `Hello` | `Hello` |
| the trailing LF | `Hello`, then an LF |

#### Scenario: Stop reading the stream after a failed write

- **GIVEN** a stream that yields the text deltas `Hel` and `lo`, then a finish event with the reason `completed`
- **AND** the write of `Hel` to stdout fails with `CocoaError(.fileWriteOutOfSpace)`
- **WHEN** `lkai --stream` handles the stream
- **THEN** only the first stream event is read
- **AND** no LF is written after the failed write
- **AND** stderr's second line is exactly `Details: NSCocoaErrorDomain 640`
- **AND** the process exits with status 1

#### Scenario: Report a failed write instead of a warning

- **GIVEN** the chat call ends with the finish reason `maxOutputTokens` and the text `Partial`
- **AND** the write of `Partial` to stdout fails with `CocoaError(.fileWriteOutOfSpace)`
- **WHEN** `lkai` runs with and without `--stream`
- **THEN** stderr's first line starts with `Error: `
- **AND** no line of stderr starts with `Warning: `
- **AND** the process exits with status 1

#### Scenario: Report a failed write of the trailing LF in a stream

- **GIVEN** the output language `en-US`
- **AND** a stream that yields the text deltas `Hel` and `lo`, then ends as listed
- **AND** the write of the trailing LF to stdout fails with `CocoaError(.fileWriteOutOfSpace)`
- **WHEN** `lkai --stream` handles the stream
- **THEN** the writes attempted to stdout are `Hel`, `lo`, then an LF
- **AND** stderr is exactly `Error: ` followed by the `en` answer write failure message, an LF, `Details: NSCocoaErrorDomain 640` and an LF
- **AND** the process exits with status 1

##### Example: stream endings

| Stream ending |
| ------------- |
| a finish event with the reason `completed` |
| fails with `serviceUnavailable(statusCode: 500, retryAfter: nil)` |
