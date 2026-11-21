## Purpose

The package-distribution capability defines how LKAIKit is delivered to app projects as a Swift Package library product. It guarantees the supported platforms, a single import entry point, a single source of the package version, a fixed module dependency direction, and a library build graph that contains no external packages.

## ADDED Requirements

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

### Requirement: Single import entry point

Code that imports only the `LKAIKit` module SHALL be able to use every public declaration of every library target that the `LKAIKit` target depends on, without importing those targets directly.

#### Scenario: Use a core declaration through the umbrella module

- **GIVEN** a source file whose only LKAIKit-related import statement is `import LKAIKit`
- **WHEN** the file references `LKAIKitInfo.version`, which `LKAICore` declares
- **THEN** the file compiles without an `import LKAICore` statement

### Requirement: Package version information

The `LKAIKit` library SHALL expose the package version as `LKAIKitInfo.version`, a string in the form `MAJOR.MINOR.PATCH` where each part is a non-negative integer without leading zeros and the string has no `v` prefix.

#### Scenario: Read the package version

- **GIVEN** a module that imports `LKAIKit`
- **WHEN** the module reads `LKAIKitInfo.version`
- **THEN** the value matches the pattern `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`

### Requirement: Library free of external package dependencies

The `LKAIKit` target and every target reachable from it through target dependencies SHALL depend only on targets declared in this package, so that building the `LKAIKit` library product never builds a third-party package.

#### Scenario: Inspect the library build graph

- **GIVEN** the package manifest
- **WHEN** the target dependencies are inspected with `swift package dump-package`
- **THEN** every dependency of `LKAIKit` and of each target reachable from `LKAIKit` names a target declared in this package

### Requirement: Module dependency direction

In this requirement, a library target is a target that the manifest declares with `.target`, which excludes `.executableTarget` and `.testTarget` declarations. The `LKAICore` target SHALL NOT depend on any target or package. Every library target other than `LKAICore` and `LKAIKit` SHALL depend only on `LKAICore`. The `LKAIKit` target SHALL depend only on library targets of this package. Among the targets of this package, the `LKAIKitCLI` target SHALL depend only on `LKAIKit`.

#### Scenario: Inspect target dependency direction

- **GIVEN** the package manifest
- **WHEN** the target dependencies are inspected with `swift package dump-package`
- **THEN** the dependency list of `LKAICore` is empty
- **AND** every library target other than `LKAICore` and `LKAIKit` lists only `LKAICore` as a dependency
- **AND** every dependency of `LKAIKit` is a library target of this package
- **AND** the only dependency of `LKAIKitCLI` that is a target of this package is `LKAIKit`
