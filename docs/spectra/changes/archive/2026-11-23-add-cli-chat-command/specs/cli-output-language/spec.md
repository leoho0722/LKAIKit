## Purpose

The cli-output-language capability defines how the `--output-language` option of `lkai` selects English or Traditional Chinese for the text that `lkai` itself writes, which text stays in English because swift-argument-parser generates it, and that the option never changes the chat request, so the language of the AI's answer stays under the prompt's control.

## ADDED Requirements

### Requirement: Output language option

`lkai` SHALL accept `--output-language` with exactly the values `en-US` and `zh-TW`, compared case-sensitively, in both the `--output-language <value>` and `--output-language=<value>` forms, and SHALL use `en-US` when the option is not given. The value SHALL apply to all translated output of the same run, including help requested with `-h` or `--help`, wherever the option appears before a `--` terminator. When the option is given more than once and every value is supported, the last value SHALL apply. When any occurrence has an unsupported value, swift-argument-parser SHALL reject the input with exit status 64, and all translated output of that run SHALL use `en-US`.

#### Scenario: Apply the language wherever the option appears

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai` runs with the arguments listed
- **THEN** stdout contains the `zh-Hant` abstract that the `LKAIKitCLI` String Catalog defines
- **AND** the process exits with status 0

##### Example: option positions

| Arguments |
| --------- |
| `--output-language zh-TW -h` |
| `-h --output-language zh-TW` |
| `--output-language=zh-TW --help` |
| `--output-language en-US --output-language zh-TW -h` |
| `--output-language zh-TW` |

#### Scenario: Reject an unsupported language

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai` runs with the arguments listed
- **THEN** stderr's first line starts with `Error: ` and contains `ja-JP`
- **AND** stderr has a line that starts with `Help:` and contains the `en` help text of `--output-language`
- **AND** stdout is empty
- **AND** the process exits with status 64

##### Example: unsupported values

| Arguments |
| --------- |
| `--output-language ja-JP --provider openai` |
| `--output-language ja-JP --output-language zh-TW --provider openai` |

### Requirement: Translated command text

The following text SHALL be looked up in the String Catalog localization that matches the output language, `en` for `en-US` and `zh-Hant` for `zh-TW`, independently of the system's preferred languages: the command's abstract and discussion, the help text of every option that `lkai` declares, including where an error's `Help:` line repeats it, the messages of the input validation failures, the incomplete answer warnings and the answer write failure defined by the cli-chat capability, and the description of an `LKAIError`, which comes from the `LKAICore` String Catalog. The `Error: `, `Warning: `, `Details: ` and `Help:` prefixes and the `Details: ` content SHALL NOT be translated. Every string that `LKAIKitCLI` looks up SHALL have a non-empty `en` and `zh-Hant` value in its String Catalog.

#### Scenario: Use English by default even on a Chinese system

- **GIVEN** a macOS system whose preferred languages start with `zh-Hant`
- **WHEN** `lkai -h` runs
- **THEN** stdout contains the `en` abstract that the `LKAIKitCLI` String Catalog defines

#### Scenario: Translate a validation failure

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai --output-language zh-TW -m x -p hi` runs
- **THEN** stderr's first line is `Error: ` followed by the `zh-Hant` message that the `LKAIKitCLI` String Catalog defines for a missing `--provider`
- **AND** the process exits with status 64

#### Scenario: Translate an error from the AI service

- **GIVEN** the output language `zh-TW`
- **WHEN** the chat call fails with `LKAIError.invalidAPIKey`
- **THEN** stderr's first line is `Error: ` followed by the `zh-Hant` value of the `LKAICore` String Catalog key `error.lkai.invalidAPIKey`
- **AND** the process exits with status 1

#### Scenario: Translate an incomplete answer warning

- **GIVEN** the output language `zh-TW`
- **WHEN** the chat call ends with the finish reason `maxOutputTokens`
- **THEN** stderr's first line is `Warning: ` followed by the `zh-Hant` warning that the `LKAIKitCLI` String Catalog defines for that finish reason
- **AND** the process exits with status 2

#### Scenario: Provide both translations for every CLI string

- **GIVEN** the `LKAIKitCLI` String Catalog
- **WHEN** every string that `LKAIKitCLI` looks up is resolved in `en` and in `zh-Hant`
- **THEN** each result is non-empty and differs from its key

### Requirement: Parser-generated text stays in English

Text that swift-argument-parser generates SHALL remain in English for every output language. This covers the `OVERVIEW:`, `USAGE:` and `OPTIONS:` headings, the help text of `-h, --help`, the `(default: …)` and `(values: …)` annotations, the messages of the parse errors that it reports, the `Help:` prefix, and the `Usage:` and `See 'lkai --help' for more information.` lines that follow an error. The custom usage text that `lkai` declares SHALL also stay the same for every output language.

#### Scenario: Keep a parse error in English

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai --output-language zh-TW --bogus` runs
- **THEN** stderr's first line is exactly `Error: Unknown option '--bogus'`
- **AND** stdout is empty
- **AND** the process exits with status 64

#### Scenario: Keep the help headings in English

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai --output-language zh-TW -h` runs
- **THEN** stdout has a line that starts with `USAGE: lkai ` (with the trailing space)
- **AND** stdout has a line that is exactly `OPTIONS:`
- **AND** stdout contains the `zh-Hant` abstract that the `LKAIKitCLI` String Catalog defines

### Requirement: Answer language unaffected

The output language SHALL NOT change the chat request that `lkai` sends: for the same other input, the model, the messages, the system prompt and the maximum output tokens SHALL be identical for `en-US` and `zh-TW`.

#### Scenario: Send the same request in both languages

- **GIVEN** the input `--provider anthropic -m claude-opus-5-5 -p hi --apiKey sk-test`
- **WHEN** the request is built once with `--output-language en-US` and once with `--output-language zh-TW`
- **THEN** the two requests are equal
- **AND** the system prompt of both is nil
