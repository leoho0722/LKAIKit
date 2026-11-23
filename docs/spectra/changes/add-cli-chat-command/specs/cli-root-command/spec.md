## MODIFIED Requirements

### Requirement: Version output

Running `lkai --version` or `lkai -v` SHALL print exactly the value of `LKAIKitInfo.version` as a single line to stdout and SHALL exit with status 0. The version flag SHALL take precedence over the checks of the chat options, so no chat request is sent when it is given; values that swift-argument-parser itself rejects still fail with exit status 64. The version flag SHALL also take precedence over the rejection of options and arguments that `lkai` does not define, so such input given together with the version flag still prints the version and exits with status 0. The `-h` and `--help` flags SHALL take precedence over the version flag, in either order.

#### Scenario: Request the version

- **GIVEN** `LKAIKitInfo.version` is `0.1.0`
- **WHEN** `lkai --version` runs
- **THEN** stdout is exactly `0.1.0` followed by an LF
- **AND** the process exits with status 0

#### Scenario: Request the version with the short flag

- **GIVEN** `LKAIKitInfo.version` is `0.1.0`
- **WHEN** `lkai -v` runs
- **THEN** stdout is exactly `0.1.0` followed by an LF
- **AND** stderr is empty
- **AND** the process exits with status 0

#### Scenario: Request the version together with chat options

- **GIVEN** `LKAIKitInfo.version` is `0.1.0`
- **WHEN** `lkai -v --provider openai -m gpt-6-luna -p hi` runs
- **THEN** stdout is exactly `0.1.0` followed by an LF
- **AND** no chat request is sent
- **AND** the process exits with status 0

#### Scenario: Request the version together with undefined input

- **GIVEN** `LKAIKitInfo.version` is `0.1.0`
- **WHEN** `lkai` runs with the arguments listed
- **THEN** stdout is exactly `0.1.0` followed by an LF
- **AND** stderr is empty
- **AND** the process exits with status 0

##### Example: version with undefined input

| Arguments |
| --------- |
| `-v --bogus` |
| `-v foo` |
| `--version --bogus` |

#### Scenario: Request help together with the version flag

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai` runs with the arguments listed
- **THEN** stdout has a line that starts with `USAGE: lkai ` (with the trailing space)
- **AND** the process exits with status 0

##### Example: help with the version flag

| Arguments |
| --------- |
| `-v -h` |
| `-h -v` |
| `--version --help` |

### Requirement: Invalid input rejection

When `lkai` receives an option or argument it does not define, it SHALL print an error that names the offending input to stderr, SHALL print nothing to stdout, and SHALL exit with status 64. When the help flag (`-h` or `--help`) or the version flag (`-v` or `--version`) is given together with such input, the requirement that covers that flag applies instead of this requirement, so the help or the version is printed and the process exits with status 0.

#### Scenario: Reject undefined input

- **GIVEN** the `lkai` executable built on macOS 26
- **WHEN** `lkai` runs with input it does not define
- **THEN** stderr contains an error message that names the input
- **AND** stdout is empty
- **AND** the process exits with status 64

##### Example: unknown option and unexpected argument

| Input | Expected stderr first line | Exit status |
| ----- | -------------------------- | ----------- |
| `--bogus` | `Error: Unknown option '--bogus'` | 64 |
| `foo` | `Error: Unexpected argument 'foo'` | 64 |

#### Scenario: Request help together with undefined input

- **GIVEN** the `lkai` executable built on macOS 26 or later
- **WHEN** `lkai` runs with the arguments listed
- **THEN** stdout has a line that starts with `USAGE: lkai ` (with the trailing space)
- **AND** stderr is empty
- **AND** the process exits with status 0

##### Example: help with undefined input

| Arguments |
| --------- |
| `-h --bogus` |
| `--help foo` |
| `--bogus -h` |
