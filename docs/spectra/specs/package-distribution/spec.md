# package-distribution Specification

## Purpose

The package-distribution capability defines how LKAIKit is delivered to app projects as a Swift Package library product. It guarantees the supported platforms, a single import entry point, a single source of the package version, a fixed module dependency direction, and a library build graph that contains no external packages.

## Requirements

### Requirement: Library product for app integration

The package SHALL provide a library product named `LKAIKit` that builds for iOS 26.0 or later and for macOS 26.0 or later, and the manifest SHALL declare exactly iOS 26.0 and macOS 26.0 as its minimum platforms.

#### Scenario: Build the library for an iOS simulator

- **GIVEN** a checkout of the LKAIKit package that contains `.swiftpm/xcode/package.xcworkspace`
- **WHEN** the `LKAIKit` scheme of that workspace is built for an iOS 26 simulator destination
- **THEN** the build succeeds

#### Scenario: Build the library for macOS

- **GIVEN** a checkout of the LKAIKit package on macOS 26
- **WHEN** `swift build` runs at the package root
- **THEN** the build succeeds

#### Scenario: Inspect the declared minimum platforms

- **GIVEN** the package manifest
- **WHEN** the manifest is inspected with `swift package dump-package`
- **THEN** the declared platforms are exactly iOS 26.0 and macOS 26.0


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
### Requirement: Single import entry point

Code that imports only the `LKAIKit` module SHALL be able to use every public declaration of every library target that the `LKAIKit` target depends on, without importing those targets directly.

#### Scenario: Use a core declaration through the umbrella module

- **GIVEN** a source file whose only LKAIKit-related import statement is `import LKAIKit`
- **WHEN** the file references `LKAIKitInfo.version`, which `LKAICore` declares
- **THEN** the file compiles without an `import LKAICore` statement


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
### Requirement: Package version information

The `LKAIKit` library SHALL expose the package version as `LKAIKitInfo.version`, a string in the form `MAJOR.MINOR.PATCH` where each part is a non-negative integer without leading zeros and the string has no `v` prefix.

#### Scenario: Read the package version

- **GIVEN** a module that imports `LKAIKit`
- **WHEN** the module reads `LKAIKitInfo.version`
- **THEN** the value matches the pattern `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`


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
### Requirement: Library free of external package dependencies

The `LKAIKit` target and every target reachable from it through target dependencies SHALL depend only on targets declared in this package, so that building the `LKAIKit` library product never builds a third-party package.

#### Scenario: Inspect the library build graph

- **GIVEN** the package manifest
- **WHEN** the target dependencies are inspected with `swift package dump-package`
- **THEN** every dependency of `LKAIKit` and of each target reachable from `LKAIKit` names a target declared in this package


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
### Requirement: Module dependency direction

In this requirement, a library target is a target that the manifest declares with `.target`, which excludes `.executableTarget` and `.testTarget` declarations. The `LKAICore` target SHALL NOT depend on any target or package. Every library target other than `LKAICore` and `LKAIKit` SHALL depend only on `LKAICore`. The `LKAIKit` target SHALL depend only on library targets of this package. Among the targets of this package, the `LKAIKitCLI` target SHALL depend only on `LKAIKit`.

#### Scenario: Inspect target dependency direction

- **GIVEN** the package manifest
- **WHEN** the target dependencies are inspected with `swift package dump-package`
- **THEN** the dependency list of `LKAICore` is empty
- **AND** every library target other than `LKAICore` and `LKAIKit` lists only `LKAICore` as a dependency
- **AND** every dependency of `LKAIKit` is a library target of this package
- **AND** the only dependency of `LKAIKitCLI` that is a target of this package is `LKAIKit`

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
### Requirement: Test support stays out of the library build

The `LKAITestSupport` target SHALL NOT belong to any product, SHALL depend only on `LKAICore`, and SHALL NOT be a dependency of `LKAIKit` or of any target reachable from `LKAIKit`, so that test doubles never ship inside an app that depends on the `LKAIKit` library product.

#### Scenario: Inspect the manifest for the test support target

- **GIVEN** the package manifest
- **WHEN** the products and target dependencies are inspected with `swift package dump-package`
- **THEN** no product lists `LKAITestSupport` as one of its targets
- **AND** the dependency list of `LKAITestSupport` contains only `LKAICore`
- **AND** `LKAITestSupport` is not reachable from `LKAIKit` through target dependencies

<!-- @trace
source: add-chat-abstraction-anthropic
updated: 2026-11-22
code:
  - Package.swift
  - Sources/LKAIAnthropic/LKAnthropicClient.swift
  - Sources/LKAIAnthropic/LKAnthropicErrorBody.swift
  - Sources/LKAIAnthropic/LKAnthropicMessagesRequestBody.swift
  - Sources/LKAIAnthropic/LKAnthropicRefusalFallback.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamEvent.swift
  - Sources/LKAIAnthropic/LKAnthropicStreamState.swift
  - Sources/LKAICore/Chat/LKAIChatClientProtocol.swift
  - Sources/LKAICore/Chat/LKAIChatCompletion.swift
  - Sources/LKAICore/Chat/LKAIChatRequest.swift
  - Sources/LKAICore/Chat/LKAIChatResponse.swift
  - Sources/LKAICore/Chat/LKAIChatStream.swift
  - Sources/LKAICore/Chat/LKAIChatStreamEvent.swift
  - Sources/LKAICore/Chat/LKAIError.swift
  - Sources/LKAICore/Chat/LKAIFinishReason.swift
  - Sources/LKAICore/Chat/LKAIMessage.swift
  - Sources/LKAICore/Chat/LKAIMessageRole.swift
  - Sources/LKAICore/Chat/LKAIUsage.swift
  - Sources/LKAICore/Networking/LKAIHTTPClient.swift
  - Sources/LKAICore/Networking/LKAIHTTPLineSplitter.swift
  - Sources/LKAICore/Networking/LKAIHTTPLines.swift
  - Sources/LKAICore/Networking/LKAIHTTPResponse.swift
  - Sources/LKAICore/Networking/LKAIServerSentEvent.swift
  - Sources/LKAICore/Networking/LKAIServerSentEventParser.swift
  - Sources/LKAICore/Resources/Localizable.xcstrings
  - Sources/LKAIKit/Exports.swift
  - Sources/LKAITestSupport/LKAIMockHTTPClient.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientCancellationTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientErrorTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientLiveTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientStreamTests.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTestSupport.swift
  - Tests/LKAIAnthropicTests/LKAnthropicClientTests.swift
  - Tests/LKAICoreTests
  - Tests/LKAICoreTests/LKAIChatClientProtocolTests.swift
  - Tests/LKAICoreTests/LKAIChatRequestTests.swift
  - Tests/LKAICoreTests/LKAIChatStreamTests.swift
  - Tests/LKAICoreTests/LKAIErrorTests.swift
  - Tests/LKAICoreTests/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/LKAIHTTPLineSplitterTests.swift
  - Tests/LKAICoreTests/LKAIServerSentEventParserTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPClientTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTestSupport.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPLinesTests.swift
  - Tests/LKAICoreTests/Networking/LKAIHTTPResponseTests.swift
  - Tests/LKAIKitTests/ExportsTests.swift
-->