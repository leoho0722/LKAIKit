## ADDED Requirements

### Requirement: Release script tests in CI

The CI job SHALL run `.github/scripts/release/tests/run-tests.sh` with the runner's default `bash`, after `swift test`, in the job that runs on the same runner label as the release workflow, so that the release scripts are tested with the shell and tools that the release workflow uses. The job SHALL fail when that script exits with a non-zero status. Values that the release script tests set inside their own processes, such as the test key `sk-test-secret`, are not environment variables that the CI job defines in the sense of "Unit tests without real API keys". The rules for the tests themselves are in release-automation "Release script test isolation".

#### Scenario: Run the release script tests

- **GIVEN** a pull request whose release scripts satisfy every test in `.github/scripts/release/tests/`
- **WHEN** the CI job runs `.github/scripts/release/tests/run-tests.sh`
- **THEN** the script exits with status 0

#### Scenario: A release script test fails

- **GIVEN** a pull request that changes `next-version.sh` so that `0.1.0` with `patch` no longer yields `0.1.1`
- **WHEN** the CI job runs `.github/scripts/release/tests/run-tests.sh`
- **THEN** the script exits with a non-zero status
- **AND** the job fails
