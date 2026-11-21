# cli-root-command Specification

## Purpose

The cli-root-command capability defines the `lkai` executable that CI/CD pipelines run on macOS. It covers the root command's help output, version output, and rejection of invalid input before any subcommand exists.

## Requirements

### Requirement: Executable product for CI/CD

The package SHALL provide an executable product named `lkai` that runs on macOS 26.0 or later, and running it without arguments SHALL print the usage information to stdout and exit with status 0.

#### Scenario: Run the executable without arguments

- **GIVEN** the `lkai` executable built on macOS 26
- **WHEN** `lkai` runs with no arguments
- **THEN** stdout contains `USAGE: lkai`
- **AND** the process exits with status 0


<!-- @trace
source: add-swift-package-foundation
updated: 2026-11-21
code:
  - .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
  - Package.resolved
  - Package.swift
  - Sources/LKAICore/LKAIKitInfo.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIKitCLI/LKAICommand.swift
  - Tests/LKAICoreTests/LKAIKitInfoTests.swift
  - Tests/LKAIKitCLITests/LKAICommandTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Help output

Running `lkai --help` or `lkai -h` SHALL print usage information that names the command and lists the `--version` option to stdout, and SHALL exit with status 0.

#### Scenario: Request help with the long flag

- **GIVEN** the `lkai` executable built on macOS 26
- **WHEN** `lkai --help` runs
- **THEN** stdout contains `USAGE: lkai`
- **AND** stdout lists the `--version` option
- **AND** the process exits with status 0

#### Scenario: Request help with the short flag

- **GIVEN** the `lkai` executable built on macOS 26
- **WHEN** `lkai -h` runs
- **THEN** stdout contains `USAGE: lkai`
- **AND** stdout lists the `--version` option
- **AND** the process exits with status 0


<!-- @trace
source: add-swift-package-foundation
updated: 2026-11-21
code:
  - .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
  - Package.resolved
  - Package.swift
  - Sources/LKAICore/LKAIKitInfo.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIKitCLI/LKAICommand.swift
  - Tests/LKAICoreTests/LKAIKitInfoTests.swift
  - Tests/LKAIKitCLITests/LKAICommandTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Version output

Running `lkai --version` SHALL print exactly the value of `LKAIKitInfo.version` as a single line to stdout and SHALL exit with status 0.

#### Scenario: Request the version

- **GIVEN** `LKAIKitInfo.version` is `0.1.0`
- **WHEN** `lkai --version` runs
- **THEN** stdout is exactly `0.1.0` followed by a newline
- **AND** the process exits with status 0


<!-- @trace
source: add-swift-package-foundation
updated: 2026-11-21
code:
  - .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
  - Package.resolved
  - Package.swift
  - Sources/LKAICore/LKAIKitInfo.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIKitCLI/LKAICommand.swift
  - Tests/LKAICoreTests/LKAIKitInfoTests.swift
  - Tests/LKAIKitCLITests/LKAICommandTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->

---
### Requirement: Invalid input rejection

When `lkai` receives an option or argument it does not define, it SHALL print an error that names the offending input to stderr, SHALL print nothing to stdout, and SHALL exit with status 64.

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

<!-- @trace
source: add-swift-package-foundation
updated: 2026-11-21
code:
  - .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
  - Package.resolved
  - Package.swift
  - Sources/LKAICore/LKAIKitInfo.swift
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAIKitCLI/LKAICommand.swift
  - Tests/LKAICoreTests/LKAIKitInfoTests.swift
  - Tests/LKAIKitCLITests/LKAICommandTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->