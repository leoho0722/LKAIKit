## MODIFIED Requirements

### Requirement: Version output

Running `lkai --version` or `lkai -v` SHALL print exactly the value of `LKAIKitInfo.version` as a single line to stdout and SHALL exit with status 0. The version flag SHALL take precedence over the checks of the chat options, so no chat request is sent when it is given; values that swift-argument-parser itself rejects still fail with exit status 64.

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
