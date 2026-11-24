## ADDED Requirements

### Requirement: Release tag matches the package version

Every release tag of the repository SHALL be named exactly the value of `LKAIKitInfo.version` in the commit that the tag points to, in the `MAJOR.MINOR.PATCH` form without a `v` prefix, so that an app that resolves LKAIKit by a version tag builds a library whose `LKAIKitInfo.version` equals that tag.

#### Scenario: Inspect a release tag

- **GIVEN** the release tag `0.1.1` created by the release workflow
- **WHEN** `git show 0.1.1:Sources/LKAICore/LKAIKitInfo.swift` is inspected
- **THEN** the declaration of `LKAIKitInfo.version` has the value `0.1.1`
- **AND** `lkai -v` built from that commit prints `0.1.1`
