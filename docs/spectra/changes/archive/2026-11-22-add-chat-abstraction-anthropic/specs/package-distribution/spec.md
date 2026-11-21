## ADDED Requirements

### Requirement: Test support stays out of the library build

The `LKAITestSupport` target SHALL NOT belong to any product, SHALL depend only on `LKAICore`, and SHALL NOT be a dependency of `LKAIKit` or of any target reachable from `LKAIKit`, so that test doubles never ship inside an app that depends on the `LKAIKit` library product.

#### Scenario: Inspect the manifest for the test support target

- **GIVEN** the package manifest
- **WHEN** the products and target dependencies are inspected with `swift package dump-package`
- **THEN** no product lists `LKAITestSupport` as one of its targets
- **AND** the dependency list of `LKAITestSupport` contains only `LKAICore`
- **AND** `LKAITestSupport` is not reachable from `LKAIKit` through target dependencies
