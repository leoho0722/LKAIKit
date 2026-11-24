# release-automation Specification

## Purpose

The release-automation capability defines how a merge to `main` becomes a tagged GitHub Release of LKAIKit: when the release workflow runs and in which mode, how the next version is chosen from an AI answer about the changes, how the version commit, the tag, the release and the release notes are produced, and how a failed run leaves the repository in a state that the next run recovers from.

## Requirements

### Requirement: Release workflow trigger

The repository SHALL provide a GitHub Actions workflow at `.github/workflows/release.yml` that runs on a push to `main`, except when every file changed by the push is release-neutral, as defined in "Release-neutral files", which also lists examples of pushes that run or do not run the workflow. The workflow SHALL also run on `workflow_dispatch` with three inputs: `provider` and `model`, strings that default to empty, and `dry_run`, a boolean that defaults to `false`. Its job SHALL run on the GitHub-hosted runner labeled `xcode-27`, SHALL be granted the `contents: write` permission, and SHALL stop after 30 minutes. Runs that can release SHALL share one concurrency group in which at most one run executes at a time and a newer run SHALL NOT cancel a run in progress; dry runs SHALL use a separate concurrency group, so that a dry run never replaces a waiting run that can release. The job SHALL check out the tip of `main` at the time the job starts, with the full history and all tags and with the credentials that the checkout stores kept for later pushes, rather than the commit that triggered the run; it SHALL then use the setup action with `uses: ./` and run `.github/scripts/release/release.sh`.

#### Scenario: A push by the release workflow itself

- **GIVEN** the release workflow pushed a version commit and a tag with the repository's `GITHUB_TOKEN`
- **WHEN** GitHub evaluates the triggers of the release workflow
- **THEN** no new run of the workflow starts

#### Scenario: Two pushes in quick succession

- **GIVEN** a run of the release workflow is in progress
- **WHEN** another push to `main` triggers the workflow
- **THEN** the new run waits until the run in progress ends
- **AND** the new run checks out the tip of `main` at the time its job starts

#### Scenario: A dry run while a release run waits

- **GIVEN** a release run is in progress and another release run is waiting
- **WHEN** the owner starts a dry run with `workflow_dispatch`
- **THEN** the waiting release run is not cancelled


<!-- @trace
source: skip-release-for-root-docs
updated: 2026-11-25
code:
  - .github/scripts/release/release.sh
  - .github/workflows/release.yml
  - AGENTS.md
  - CLAUDE.md
  - README.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release mode

`release.sh` SHALL choose its mode from `LKAI_RELEASE_DRY_RUN` before it reads the version or sends any AI request: when the variable is unset, empty or `true`, the mode SHALL be a dry run; when it is `false`, the mode SHALL be a release, but only when `GITHUB_ACTIONS` is `true`; when it is `false` and `GITHUB_ACTIONS` is not `true`, the run SHALL fail with a message saying that a release only runs in GitHub Actions; any other value SHALL fail the run with a message that names the value. The workflow SHALL set `LKAI_RELEASE_DRY_RUN` to `true` when the `dry_run` input of `workflow_dispatch` is `true`, and to `false` otherwise, including on a push.

#### Scenario: Choose the mode

- **GIVEN** the values of `LKAI_RELEASE_DRY_RUN` and `GITHUB_ACTIONS` listed
- **WHEN** `release.sh` starts
- **THEN** the result is the one listed

##### Example: modes

| `LKAI_RELEASE_DRY_RUN` | `GITHUB_ACTIONS` | Result |
| ---------------------- | ---------------- | ------ |
| not set | not set | dry run |
| empty string | `true` | dry run |
| `true` | `true` | dry run |
| `false` | `true` | release |
| `false` | not set | rejected, message says a release only runs in GitHub Actions |
| `TRUE` | `true` | rejected, message names `TRUE` |
| `1` | not set | rejected, message names `1` |


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release provider and model selection

`release.sh` SHALL read four environment variables: `LKAI_RELEASE_PROVIDER` and `LKAI_RELEASE_MODEL`, the choice for this run, and `LKAI_RELEASE_DEFAULT_PROVIDER` and `LKAI_RELEASE_DEFAULT_MODEL`, the default of the repository. The provider SHALL be the first non-empty value of `LKAI_RELEASE_PROVIDER` and `LKAI_RELEASE_DEFAULT_PROVIDER`, or `anthropic` when both are empty or unset. When `LKAI_RELEASE_PROVIDER` is not empty, the model SHALL be `LKAI_RELEASE_MODEL`; otherwise it SHALL be the first non-empty value of `LKAI_RELEASE_MODEL` and `LKAI_RELEASE_DEFAULT_MODEL`, or `claude-opus-5-5` when both are empty or unset and `LKAI_RELEASE_DEFAULT_PROVIDER` is also empty or unset. When no model results, the run SHALL fail before any AI request, with a message that names `LKAI_RELEASE_MODEL` and `LKAI_RELEASE_DEFAULT_MODEL`. `release.sh` SHALL NOT check the provider value or the presence of an API key itself; it SHALL pass the provider and the model to `lkai` unchanged, and a rejection by `lkai` is handled as described in "Failed AI request". The workflow SHALL set `LKAI_RELEASE_PROVIDER` and `LKAI_RELEASE_MODEL` to the `provider` and `model` inputs of `workflow_dispatch`, which are empty on a push, SHALL set `LKAI_RELEASE_DEFAULT_PROVIDER` and `LKAI_RELEASE_DEFAULT_MODEL` to the repository variables of the same names, and SHALL pass the repository secrets `LKAI_ANTHROPIC_API_KEY`, `LKAI_OPENAI_API_KEY` and `LKAI_GEMINI_API_KEY` to `release.sh` as environment variables of the same names.

#### Scenario: Resolve the provider and the model

- **GIVEN** the values of the four variables listed
- **WHEN** `release.sh` resolves the provider and the model
- **THEN** the result is the one listed

##### Example: provider and model resolution

| `LKAI_RELEASE_PROVIDER` | `LKAI_RELEASE_MODEL` | `LKAI_RELEASE_DEFAULT_PROVIDER` | `LKAI_RELEASE_DEFAULT_MODEL` | Provider | Model |
| ----------------------- | -------------------- | ------------------------------- | ---------------------------- | -------- | ----- |
| not set | not set | not set | not set | `anthropic` | `claude-opus-5-5` |
| empty string | empty string | `openai` | `gpt-6-luna` | `openai` | `gpt-6-luna` |
| `google` | empty string | `anthropic` | `claude-sonnet-5-5` | rejected, message names `LKAI_RELEASE_MODEL` and `LKAI_RELEASE_DEFAULT_MODEL` | none |
| `openai` | `gpt-6-luna` | `anthropic` | `claude-sonnet-5-5` | `openai` | `gpt-6-luna` |
| empty string | `claude-sonnet-5-5` | not set | not set | `anthropic` | `claude-sonnet-5-5` |
| not set | not set | not set | `claude-sonnet-5-5` | `anthropic` | `claude-sonnet-5-5` |
| not set | not set | `openai` | not set | rejected, message names `LKAI_RELEASE_MODEL` and `LKAI_RELEASE_DEFAULT_MODEL` | none |
| `gemini` | `x` | not set | not set | `gemini`, then rejected by `lkai` | `x` |

#### Scenario: Map the workflow inputs and repository variables

- **GIVEN** a push to `main`, with the repository variables `LKAI_RELEASE_DEFAULT_PROVIDER` set to `openai` and `LKAI_RELEASE_DEFAULT_MODEL` set to `gpt-6-luna`
- **WHEN** the release workflow sets the environment of `release.sh`
- **THEN** `LKAI_RELEASE_PROVIDER` and `LKAI_RELEASE_MODEL` are empty
- **AND** `LKAI_RELEASE_DEFAULT_PROVIDER` is `openai` and `LKAI_RELEASE_DEFAULT_MODEL` is `gpt-6-luna`

#### Scenario: lkai rejects the provider

- **GIVEN** `LKAI_RELEASE_PROVIDER` is `gemini` and `LKAI_RELEASE_MODEL` is `x`
- **WHEN** `release.sh` sends its first AI request
- **THEN** `lkai` exits with status 64
- **AND** `release.sh` exits with status 1 as described in "Failed AI request"


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release plan

In this requirement, a version tag is a tag whose name matches `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`, and the current version is the value of the `LKAIKitInfo.version` declaration in `Sources/LKAICore/LKAIKitInfo.swift` as committed at `HEAD`, not as it is in the working tree, read with the same rule that `package-version.sh` uses to change it. Versions are compared part by part as integers. `release.sh` SHALL choose exactly one plan, in this order:

1. The declaration is not found exactly once, or the current version does not match the version pattern: the run SHALL fail.
2. Some version tag is greater than the current version: the run SHALL fail, with a message that names the highest version tag.
3. A tag named the current version exists: after "Release repair", when `HEAD` has no commit after that tag, or every file that differs between that tag and `HEAD` is release-neutral, as defined in "Release-neutral files", the run SHALL end with status 0 without releasing and SHALL say that there is nothing to release; otherwise the plan is a version bump, whose previous version is the current version and whose next version is computed as described in "Next version computation" from the level given in "AI bump level answer".
4. Otherwise the plan is a release as-is: the next version is the current version, and the previous version is the highest version tag that is an ancestor of `HEAD`, or none when no such tag exists.

#### Scenario: Choose the plan

- **GIVEN** the current version, the version tags and the changes after the tag of the current version listed
- **AND** every version tag listed has a release
- **WHEN** `release.sh` chooses the plan
- **THEN** the plan is the one listed

##### Example: plans

| Current version | Version tags | Changes after the tag of the current version | Plan | Previous version | Next version |
| --------------- | ------------ | -------------------------------------------- | ---- | ---------------- | ------------ |
| `0.1.0` | none | not applicable | release as-is | none | `0.1.0` |
| `0.1.0` | `0.1.0` | 3 commits that change `Sources/` | version bump | `0.1.0` | from the AI answer |
| `0.1.0` | `0.1.0` | no commit | nothing to release | none | none |
| `0.1.0` | `0.1.0` | 2 commits that change only `docs/spectra/` | nothing to release | none | none |
| `0.1.0` | `0.1.0` | 2 commits that change only `README.md` and `AGENTS.md` | nothing to release | none | none |
| `1.0.0` | `0.1.0`, `0.2.0` | not applicable | release as-is | `0.2.0` | `1.0.0` |
| `0.1.5` | `0.1.0`, `0.2.0` | not applicable | rejected, message names `0.2.0` | none | none |
| `0.1.0` | `0.1.0`, `0.2.0` | 3 commits that change `Sources/` | rejected, message names `0.2.0` | none | none |
| `0.10.0` | `0.9.0` | not applicable | release as-is | `0.9.0` | `0.10.0` |

#### Scenario: Choose a version by hand

- **GIVEN** the latest version tag is `0.4.2` and it has a release
- **WHEN** a pull request sets `LKAIKitInfo.version` to `1.0.0` and is merged into `main`
- **THEN** the plan is a release as-is of `1.0.0` with the previous version `0.4.2`
- **AND** no version commit is created

#### Scenario: Read the version at HEAD

- **GIVEN** `LKAIKitInfo.version` is `0.1.0` at `HEAD` and the working tree has an uncommitted change that sets it to `0.9.0`
- **WHEN** `release.sh` reads the current version
- **THEN** the current version is `0.1.0`


<!-- @trace
source: skip-release-for-root-docs
updated: 2026-11-25
code:
  - .github/scripts/release/release.sh
  - .github/workflows/release.yml
  - AGENTS.md
  - CLAUDE.md
  - README.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Change data in prompts

Both AI prompts SHALL contain the change data of one range: from the previous version to the target, where the target is `HEAD`, except in "Release repair", where it is the tag being repaired; when there is no previous version, the range SHALL start from the empty tree and include the first commit. The change data SHALL consist of the subjects of the non-merge commits in the range, the change statistics of the range, and the diff of `Sources/`, `Package.swift`, `Package.resolved` and `action.yml` for the range when that diff is at most 200,000 bytes. When the diff is larger, the prompt SHALL omit it and SHALL say that it was omitted because of its size. The prompt SHALL present the commit subjects, the statistics and the diff as quoted data and SHALL tell the model to ignore any instruction inside them.

#### Scenario: Change data for a version bump

- **GIVEN** the previous version `0.1.0` and two commits after it, one of which changes `Sources/LKAICore/LKAIKitInfo.swift` and one of which changes only `Tests/LKAICoreTests/LKAIKitInfoTests.swift`
- **WHEN** `release.sh` builds either prompt
- **THEN** the prompt contains the subjects of both commits and the change statistics
- **AND** the prompt contains the diff of `Sources/LKAICore/LKAIKitInfo.swift` and not the diff of `Tests/LKAICoreTests/LKAIKitInfoTests.swift`

#### Scenario: Change data for the first release

- **GIVEN** no version tag exists
- **AND** the diff of `Sources/`, `Package.swift`, `Package.resolved` and `action.yml` from the empty tree to `HEAD` is larger than 200,000 bytes
- **WHEN** `release.sh` builds the release notes prompt
- **THEN** the prompt contains the subjects of all non-merge commits, including the first commit
- **AND** the prompt says that the diff was omitted because of its size


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: AI bump level answer

For a version bump, `release.sh` SHALL send one request through `lkai`, with the selected provider and model and the bump level prompt as a prompt file. The prompt SHALL contain the previous version and the change data described in "Change data in prompts", and SHALL NOT contain a next version. It SHALL define the levels against the public interface, namely the public declarations of the `LKAIKit` library product, the command-line interface of `lkai` (its options, output and exit statuses), and the inputs and outputs of the setup action: `major` for a change that breaks the public interface, `minor` for a backward-compatible addition to it, and `patch` for every other change. It SHALL ask for exactly one of the three words. The answer SHALL be the standard output of `lkai` with leading and trailing spaces, tabs, CR and LF removed, and SHALL be accepted only when it is exactly `major`, `minor` or `patch`. Any other answer SHALL fail the run before any file is changed, with an error that contains at most the first 200 bytes of the answer, with an incomplete UTF-8 character at the end of those bytes removed, written as described in "AI text in the job log".

#### Scenario: Read the AI answer

- **GIVEN** a version bump whose `lkai` request exits with status 0 and the standard output listed
- **WHEN** `release.sh` reads the answer
- **THEN** the result is the one listed

##### Example: answers

| Standard output of `lkai` | Result |
| ------------------------- | ------ |
| `minor` followed by an LF | level `minor` |
| two spaces, `patch`, CR, LF | level `patch` |
| `Major` followed by an LF | rejected |
| `minor.` followed by an LF | rejected |
| `patch` LF `because the change only fixes a bug` LF | rejected |
| empty | rejected |

#### Scenario: Shorten a long rejected answer

- **GIVEN** an answer of 67 CJK characters of 3 bytes each in UTF-8
- **WHEN** `release.sh` rejects the answer
- **THEN** the error contains the first 66 characters of the answer and not the 67th
- **AND** stderr contains no message from the tool that removed the incomplete character


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Next version computation

`.github/scripts/release/next-version.sh` SHALL take a version in the version pattern and a level, and SHALL print the next version followed by an LF. When MAJOR is at least 1, `major` SHALL increase MAJOR and reset MINOR and PATCH to 0, `minor` SHALL increase MINOR and reset PATCH to 0, and `patch` SHALL increase PATCH. When MAJOR is 0, `major` SHALL increase MINOR and reset PATCH to 0, and both `minor` and `patch` SHALL increase PATCH, so that a version bump never reaches `1.0.0`. A version outside the version pattern or a level other than the three SHALL make the script exit with a non-zero status and print nothing to stdout.

#### Scenario: Compute the next version

- **GIVEN** the version and the level listed
- **WHEN** `next-version.sh` runs
- **THEN** it prints the result listed

##### Example: next versions

| Version | Level | Result |
| ------- | ----- | ------ |
| `0.1.0` | `major` | `0.2.0` |
| `0.1.3` | `major` | `0.2.0` |
| `0.1.0` | `minor` | `0.1.1` |
| `0.1.0` | `patch` | `0.1.1` |
| `0.9.9` | `major` | `0.10.0` |
| `1.2.3` | `major` | `2.0.0` |
| `1.2.3` | `minor` | `1.3.0` |
| `1.2.3` | `patch` | `1.2.4` |
| `v1.2.3` | `patch` | rejected |
| `1.02.3` | `patch` | rejected |
| `1.2.3` | `huge` | rejected |


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release notes generation

For every plan that releases and for "Release repair", `release.sh` SHALL send one request through `lkai`, with the selected provider and model and the release notes prompt as a prompt file. The prompt SHALL contain the version being released; the previous version or a statement that this is the first release; and the change data described in "Change data in prompts". It SHALL ask for release notes in Traditional Chinese, in Markdown, grouped under headings for breaking changes, new features, fixes and other changes, with groups that have no item left out. The release notes SHALL be the standard output of `lkai`; when it is empty or consists only of whitespace, the run SHALL fail without changing any file, creating any commit or tag, pushing, or creating any release other than one that "Release repair" created earlier in the same run.

#### Scenario: Build the release notes prompt for a version bump

- **GIVEN** the previous version `0.1.0` and the next version `0.1.1`
- **WHEN** `release.sh` builds the release notes prompt
- **THEN** the prompt contains `0.1.1` and `0.1.0`

#### Scenario: Build the release notes prompt for the first release

- **GIVEN** no version tag exists and the current version is `0.1.0`
- **WHEN** `release.sh` builds the release notes prompt
- **THEN** the prompt contains `0.1.0` and says that this is the first release

#### Scenario: The release notes are blank

- **GIVEN** no version tag exists
- **AND** `lkai` exits with status 0 for the release notes request and writes only spaces and an LF
- **WHEN** `release.sh` reads the release notes
- **THEN** it exits with status 1
- **AND** no file is changed and no tag or release is created


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Failed AI request

When `lkai` exits with a status other than 0 for the bump level request or a release notes request, including status 2 for an incomplete answer and status 64 for an input it rejects, the run SHALL fail at that point and SHALL keep the stderr of `lkai` in its own stderr. It SHALL NOT change any file, create any commit or tag, push, or create any release other than one that "Release repair" created earlier in the same run.

#### Scenario: The AI service rejects the request

- **GIVEN** a version bump from the tag `0.1.0`, which has a release
- **AND** `lkai` exits with status 1 for the bump level request and writes `Error: test failure` to stderr
- **WHEN** `release.sh` runs
- **THEN** it exits with status 1 and its stderr contains `Error: test failure`
- **AND** `Sources/LKAICore/LKAIKitInfo.swift` is unchanged, no commit is pushed, and no tag or release is created

#### Scenario: The release notes are cut off

- **GIVEN** a version bump from the tag `0.1.0`, which has a release
- **AND** `lkai` exits with status 2 for the release notes request
- **WHEN** `release.sh` runs
- **THEN** it exits with status 1
- **AND** no tag or release is created

#### Scenario: A request fails after a repair

- **GIVEN** the tag `0.1.1` has no release and a commit that changes `Sources/` was merged after it
- **AND** the release notes request for the repair succeeds and the bump level request fails
- **WHEN** `release.sh` runs as a release
- **THEN** a release exists for the tag `0.1.1`
- **AND** `release.sh` exits with status 1 without creating a commit, the tag `0.1.2` or another release


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Version commit and tag push

For a version bump, after both AI answers are accepted, `release.sh` SHALL set the `LKAIKitInfo.version` declaration in `Sources/LKAICore/LKAIKitInfo.swift` to the next version with `.github/scripts/release/package-version.sh`, which SHALL fail without changing the file when the declaration is not found exactly once. `release.sh` SHALL rebuild `lkai` in the release configuration and SHALL fail before committing unless the `lkai` in the directory that `swift build -c release --show-bin-path` prints for the package prints the next version with `-v`. It SHALL commit only that file, with both the author and the committer named `github-actions[bot]` with the email `41898282+github-actions[bot]@users.noreply.github.com` and the message `chore: 版本號更新為 <next version>`, SHALL create the tag named the next version on that commit, and SHALL push the commit to `main` and the tag in one atomic push without force, so that either both reach the remote or neither does. When the push is rejected, the run SHALL fail without creating a release other than one that "Release repair" created earlier in the same run. For a release as-is, `release.sh` SHALL NOT create a commit; it SHALL create the tag named the next version on `HEAD` and push only that tag.

#### Scenario: Bump the version

- **GIVEN** the current version `0.1.0`, the tag `0.1.0` with a release, a commit after it that changes `Sources/` and the AI answer `minor`
- **WHEN** `release.sh` runs as a release
- **THEN** the remote `main` has a new commit whose only change sets `LKAIKitInfo.version` to `0.1.1`, with the message `chore: 版本號更新為 0.1.1` and with `github-actions[bot]` as author and committer
- **AND** the remote tag `0.1.1` points to that commit

#### Scenario: Main moved during the run

- **GIVEN** a version bump from the tag `0.1.0`, which has a release
- **AND** another commit reached the remote `main` after the run checked it out
- **WHEN** `release.sh` pushes the version commit and the tag
- **THEN** the push is rejected
- **AND** the remote has neither the version commit nor the tag `0.1.1`
- **AND** the run exits with status 1 without creating a release


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release creation

After the tag is on the remote, `release.sh` SHALL create the GitHub Release with `gh release create <next version> --verify-tag`, with the next version as the title and the release notes as the notes. When the call fails, the run SHALL fail; the tag stays on the remote and "Release repair" creates the release in a later run.

#### Scenario: Release as-is for the first time

- **GIVEN** no version tag exists and `LKAIKitInfo.version` on `main` is `0.1.0`
- **WHEN** the release workflow runs
- **THEN** the tag `0.1.0` points to the commit at the tip of `main` that the run checked out
- **AND** a GitHub Release titled `0.1.0` with the release notes exists for that tag


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release repair

When a tag named the current version exists, `release.sh` SHALL check whether a GitHub Release exists for it before deciding between a version bump and nothing to release, by listing the tag names of the latest 100 releases with `gh release list`. When that command fails, the run SHALL fail. When the tag is not in the list, `release.sh` SHALL send a release notes request for the range from the previous version to that tag, where the previous version is the highest version tag lower than the current version that is an ancestor of the tag, or none, and SHALL create the release as described in "Release creation", then SHALL continue with the plan. A failure of that release notes request or of that release creation SHALL be reported as a failure of the repair.

#### Scenario: Recover after a failed release creation

- **GIVEN** a run pushed the version commit and the tag `0.1.1` and then failed to create the release
- **AND** the tag `0.1.0` has a release
- **WHEN** the release workflow runs again without new commits
- **THEN** a GitHub Release titled `0.1.1` exists for the tag `0.1.1`, with release notes for the range from `0.1.0` to `0.1.1`
- **AND** the run then ends with nothing to release

#### Scenario: Recover when a new change was merged

- **GIVEN** the tag `0.1.1` has no release and the tag `0.1.0` has a release
- **AND** a commit that changes `Sources/` was merged after the tag `0.1.1`
- **AND** the AI answer for the bump level is `patch`
- **WHEN** the release workflow runs
- **THEN** a GitHub Release titled `0.1.1` exists for the tag `0.1.1`, with release notes for the range from `0.1.0` to `0.1.1`
- **AND** the run then releases `0.1.2` as a version bump whose previous version is `0.1.1`

#### Scenario: The release list cannot be read

- **GIVEN** the tag of the current version exists
- **AND** `gh release list` exits with status 1
- **WHEN** `release.sh` checks the releases
- **THEN** it exits with status 1 without sending any AI request or creating any release


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Dry run

In the dry run mode, `release.sh` SHALL choose the plan and send the AI requests as in a release, including the release notes request of "Release repair", SHALL then print the plan and the release notes, and SHALL end with status 0 without changing any file, creating any commit or tag, pushing, or creating any release.

#### Scenario: Dry run a version bump

- **GIVEN** the current version `0.1.0`, the tag `0.1.0` with a release, one commit after it that changes `Sources/` and the AI answer `patch`
- **AND** `LKAI_RELEASE_DRY_RUN` is `true`
- **WHEN** `release.sh` runs
- **THEN** stdout names the plan, the previous version `0.1.0`, the next version `0.1.1`, the provider and the model, followed by the release notes
- **AND** the working tree, the remote `main`, the tags and the releases are unchanged
- **AND** it exits with status 0


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Run report

At every exit after the mode is chosen, `release.sh` SHALL print a report to stdout that names the mode, the provider and the model when they are resolved, the plan when one was chosen, and the previous version and the next version when they are known. A report of a run that ends with status 0 SHALL also contain the release notes of every release it created or, in the dry run mode, would create; a report of a failed run SHALL also name the step that failed. When the environment variable `GITHUB_STEP_SUMMARY` names a file, `release.sh` SHALL append the same report to that file.

#### Scenario: Report a release in the job summary

- **GIVEN** a run that releases `0.1.1` in GitHub Actions
- **WHEN** the run ends
- **THEN** the job summary shows the mode, the plan, `0.1.0`, `0.1.1`, the provider, the model and the release notes

#### Scenario: Report nothing to release

- **GIVEN** a run whose plan is nothing to release
- **WHEN** the run ends with status 0
- **THEN** the job summary says that there is nothing to release

#### Scenario: Report a failed run

- **GIVEN** a version bump from the tag `0.1.0`, which has a release, whose bump level request fails
- **WHEN** the run ends with status 1
- **THEN** the job summary names the plan and says that the bump level request failed

#### Scenario: Report a failure before the version is read

- **GIVEN** `LKAI_RELEASE_PROVIDER` is `google` and `LKAI_RELEASE_MODEL` is empty
- **WHEN** the run ends with status 1
- **THEN** the job summary names the mode and says that resolving the provider and the model failed


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: AI text in the job log

When `GITHUB_ACTIONS` is `true`, wherever `release.sh` writes text that comes from an AI answer to stdout or stderr, including the release notes and a rejected answer, it SHALL write a line `::stop-commands::<token>` before the text and a line `::<token>::` after it to the same stream as the text, where `<token>` is a random string of at least 32 hexadecimal digits chosen once per run, so that GitHub Actions does not run a workflow command contained in the text. A workflow command line that `release.sh` writes itself, such as an `::error::` line, SHALL NOT contain text from an AI answer; a rejected answer SHALL be written in the enclosed lines after that error line.

#### Scenario: Release notes contain a workflow command

- **GIVEN** `GITHUB_ACTIONS` is `true`
- **AND** the release notes contain the line `::error::injected`
- **WHEN** `release.sh` prints the release notes
- **THEN** the line `::error::injected` appears after a line `::stop-commands::<token>` and before the matching line `::<token>::` in the same stream

#### Scenario: A rejected answer contains a workflow command

- **GIVEN** `GITHUB_ACTIONS` is `true`
- **AND** the bump level answer is `upgrade` LF `::add-mask::x`
- **WHEN** `release.sh` rejects the answer
- **THEN** stderr has an `::error::` line that contains neither `upgrade` nor `::add-mask::x`
- **AND** the line `::add-mask::x` appears in stderr after a line `::stop-commands::<token>` and before the matching line `::<token>::`


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: API keys stay in the environment

`release.sh` SHALL pass the API key to `lkai` only through the environment variable that `lkai` reads for the selected provider. It SHALL NOT pass the key as a command-line argument, and SHALL NOT write the key or the whole environment to stdout, stderr, the job summary, a prompt file or the release notes.

#### Scenario: Inspect the lkai invocation

- **GIVEN** `LKAI_ANTHROPIC_API_KEY` is `sk-test-secret`
- **WHEN** `release.sh` runs a version bump with a test double of `lkai` that records its arguments
- **THEN** none of the recorded arguments contains `sk-test-secret`
- **AND** stdout, stderr, the job summary and the prompt files do not contain `sk-test-secret`


<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release script test isolation

The tests in `.github/scripts/release/tests/`, run by `.github/scripts/release/tests/run-tests.sh`, SHALL replace `lkai`, `gh` and `swift` with test doubles and SHALL use temporary git repositories whose git configuration does not depend on the global or system git configuration of the machine. Before each test, `run-tests.sh` SHALL unset `GITHUB_ACTIONS`, `GITHUB_STEP_SUMMARY`, `GH_REPO`, `GH_TOKEN`, every variable whose name starts with `LKAI_RELEASE_`, and every variable whose name starts with `LKAI_` and ends with `_API_KEY`, so that a test sets each of them itself and the results are the same inside and outside GitHub Actions. The tests SHALL capture the output of the scripts under test, so that no line of it reaches the job log as a workflow command. They send no AI request, change no GitHub repository and do not build the package. `run-tests.sh` SHALL exit with status 0 when every test passes and with a non-zero status otherwise; the CI job that runs it is described in continuous-integration "Release script tests in CI".

#### Scenario: Run the tests inside GitHub Actions

- **GIVEN** `GITHUB_ACTIONS` is `true` and `GITHUB_STEP_SUMMARY` names a file
- **WHEN** `run-tests.sh` runs
- **THEN** every test has the same result as when neither variable is set
- **AND** the file named by `GITHUB_STEP_SUMMARY` is unchanged
- **AND** no line of the output of `run-tests.sh` starts with `::`

<!-- @trace
source: 02-add-release-automation
updated: 2026-11-24
code:
  - .github/scripts/release/make-prompt.sh
  - .github/scripts/release/next-version.sh
  - .github/scripts/release/package-version.sh
  - .github/scripts/release/prompts/bump-level.md
  - .github/scripts/release/prompts/release-notes.md
  - .github/scripts/release/release.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Sources/LKAICore/LKAIKitInfo.swift
  - docs/adding-a-provider.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/fakes/fake-common.sh
  - .github/scripts/release/tests/fakes/gh
  - .github/scripts/release/tests/fakes/lkai
  - .github/scripts/release/tests/fakes/swift
  - .github/scripts/release/tests/helpers.sh
  - .github/scripts/release/tests/run-tests.sh
  - .github/scripts/release/tests/test-make-prompt.sh
  - .github/scripts/release/tests/test-next-version.sh
  - .github/scripts/release/tests/test-package-version.sh
  - .github/scripts/release/tests/test-release.sh
-->

---
### Requirement: Release-neutral files

A release-neutral file is a file whose path from the repository root is under `docs/spectra/`, or is exactly `README.md`, `CLAUDE.md` or `AGENTS.md`. Outside `docs/spectra/`, a file with one of those three names in a subdirectory, such as `docs/README.md`, SHALL NOT be release-neutral. The release workflow trigger and the release plan SHALL use this same set: the `paths-ignore` list of `.github/workflows/release.yml` SHALL hold exactly one pattern that matches every file under `docs/spectra/`, exactly one pattern for each of `README.md`, `CLAUDE.md` and `AGENTS.md`, and no other pattern, and for every pattern in that list, `release.sh` SHALL treat a change to a file that matches the pattern as a change to a release-neutral file. `release.sh` SHALL apply the set on every run, including a run started with `workflow_dispatch`, which `paths-ignore` does not filter.

#### Scenario: Decide whether a push to main runs the workflow

- **GIVEN** a push to `main` that changes the files listed
- **WHEN** GitHub evaluates the triggers of the release workflow
- **THEN** the workflow runs or does not run as listed

##### Example: changed files and whether the workflow runs

| Files changed by the push | Workflow runs |
| ------------------------- | ------------- |
| `docs/spectra/changes/x/tasks.md` | no |
| `docs/spectra/changes/x/tasks.md`, `docs/spectra/specs/cli-chat/spec.md` | no |
| `README.md` | no |
| `CLAUDE.md`, `AGENTS.md`, `docs/spectra/changes/x/tasks.md` | no |
| `docs/spectra/specs/cli-chat/spec.md`, `Sources/LKAICore/LKAIKitInfo.swift` | yes |
| `README.md`, `Sources/LKAICore/LKAIKitInfo.swift` | yes |
| `docs/README.md` | yes |
| `docs/adding-a-provider.md` | yes |
| `.github/workflows/ci.yml` | yes |

#### Scenario: Classify the file changed after the tag

- **GIVEN** the current version `0.1.0` has a tag and that tag has a release
- **AND** the only commit after the tag changes the file listed
- **WHEN** `release.sh` chooses the plan
- **THEN** the plan is the one listed

##### Example: changed file and plan

| File changed after the tag | Plan |
| -------------------------- | ---- |
| `docs/spectra/changes/x/tasks.md` | nothing to release |
| `docs/spectra/README.md` | nothing to release |
| `README.md` | nothing to release |
| `CLAUDE.md` | nothing to release |
| `AGENTS.md` | nothing to release |
| `docs/README.md` | version bump |
| `Sources/README.md` | version bump |
| `docs/adding-a-provider.md` | version bump |

#### Scenario: Every pattern the workflow ignores is release-neutral to the script

- **GIVEN** a pattern in the `paths-ignore` list of `.github/workflows/release.yml`
- **AND** the current version has a tag that has a release
- **AND** every commit after the tag changes only files that match patterns in that list, and the last of those commits changes a file that matches the given pattern
- **WHEN** `release.sh` chooses the plan
- **THEN** the plan is nothing to release

<!-- @trace
source: skip-release-for-root-docs
updated: 2026-11-25
code:
  - .github/scripts/release/release.sh
  - .github/workflows/release.yml
  - AGENTS.md
  - CLAUDE.md
  - README.md
  - docs/releasing.md
tests:
  - .github/scripts/release/tests/test-release.sh
-->