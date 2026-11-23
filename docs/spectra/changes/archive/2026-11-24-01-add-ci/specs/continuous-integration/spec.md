## Purpose

The continuous-integration capability defines the checks that run on every pull request, so that a change reaches `main` only after they pass, without using any real AI API key.

## ADDED Requirements

### Requirement: Pull request workflow trigger and runner

The repository SHALL provide a GitHub Actions workflow at `.github/workflows/ci.yml` that runs for every pull request on the `opened`, `synchronize` and `reopened` activity types, whatever files the pull request changes. Its job SHALL run on the GitHub-hosted runner labeled `xcode-27`, SHALL be granted only the `contents: read` permission, and SHALL stop after 30 minutes. A newer run for the same pull request SHALL cancel the run that is still in progress for it.

#### Scenario: Open a pull request

- **GIVEN** a branch that changes `Sources/LKAICore/LKAIKitInfo.swift`
- **WHEN** a pull request is opened from that branch
- **THEN** the CI workflow starts one job on a runner labeled `xcode-27`
- **AND** the job runs the setup action smoke check and the unit tests

#### Scenario: Open a pull request that changes only Spectra documents

- **GIVEN** a branch whose only changed file is `docs/spectra/changes/x/tasks.md`
- **WHEN** a pull request is opened from that branch
- **THEN** the CI workflow runs the same job as for any other pull request

#### Scenario: Push a new commit while a run is in progress

- **GIVEN** a CI run for a pull request is in progress
- **WHEN** a new commit is pushed to the branch of that pull request
- **THEN** the in-progress run is cancelled
- **AND** a new run starts for the new commit

### Requirement: Unit tests without real API keys

The CI job SHALL run `swift test` at the package root. It SHALL NOT define any environment variable whose name starts with `LKAI_` and ends with `_API_KEY` and SHALL NOT reference any repository secret, so the tests that need a real API key are reported as skipped through their existing `.enabled(if:)` conditions. The job SHALL fail when `swift test` exits with a non-zero status.

#### Scenario: Run the unit tests on a pull request

- **GIVEN** a pull request whose code passes every test that does not need a real API key
- **WHEN** the CI job runs `swift test`
- **THEN** `swift test` exits with status 0
- **AND** every test whose `.enabled(if:)` condition reads an `LKAI_*_API_KEY` environment variable is reported as skipped

#### Scenario: A unit test fails

- **GIVEN** a pull request that makes one test in `LKAICoreTests` fail
- **WHEN** the CI job runs `swift test`
- **THEN** the job fails
- **AND** the pull request shows the CI check as failed

### Requirement: Setup action smoke check

The CI job SHALL use the setup action of the same commit with `uses: ./` after the checkout and before any step that builds the package, so that the action runs in a clean checkout as it does in other workflows. It SHALL then run `lkai -v` from a working directory outside the package root. The job SHALL fail unless that command exits with status 0, its output matches `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`, and the output equals the action's `version` output, and unless the action's `path` output names an executable file whose last path component is `lkai` and that prints the same output when run with `-v`.

#### Scenario: Smoke check the setup action

- **GIVEN** a pull request whose `LKAIKitInfo.version` is `0.1.0`
- **WHEN** the CI job runs the setup action and then runs `lkai -v` in the runner's temporary directory
- **THEN** the command prints `0.1.0` and exits with status 0
- **AND** the action's `version` output is `0.1.0`
- **AND** the file named by the action's `path` output is executable, its last path component is `lkai`, and it prints `0.1.0` when run with `-v`

#### Scenario: The action looks for lkai in the debug build directory

- **GIVEN** a version of the setup action that builds the release configuration but takes the directory of the debug configuration
- **WHEN** the CI job runs the action in a clean checkout, before any other build
- **THEN** the action fails because that directory has no `lkai`
- **AND** the job fails
