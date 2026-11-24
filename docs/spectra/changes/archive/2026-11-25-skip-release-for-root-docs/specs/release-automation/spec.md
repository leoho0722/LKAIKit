## ADDED Requirements

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

## MODIFIED Requirements

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
