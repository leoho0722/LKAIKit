## Purpose

The lkai-setup-action capability defines a composite GitHub Action that builds `lkai` from the action's own source on a macOS runner and puts it on `PATH`, so that workflows of this repository and of other repositories can run `lkai` without installing it themselves.

## ADDED Requirements

### Requirement: Setup action interface

The repository SHALL provide a composite action defined by `action.yml` at the repository root, so that other repositories use it with `uses: leoho0722/LKAIKit@<ref>` and this repository uses it with `uses: ./`. The action SHALL take no inputs. It SHALL set two outputs: `path`, the absolute path of the `lkai` executable it built, and `version`, the standard output of that executable run with `-v`, without the trailing LF.

#### Scenario: Read the action outputs

- **GIVEN** a workflow job on a macOS runner that uses the action with the id `lkai`
- **AND** `LKAIKitInfo.version` of the action's source is `0.1.0`
- **WHEN** a later step reads `steps.lkai.outputs.path` and `steps.lkai.outputs.version`
- **THEN** `path` is an absolute path whose last component is `lkai` and that names an executable file
- **AND** `version` is `0.1.0`

### Requirement: Build lkai from the action source

The action SHALL build the `lkai` product in the release configuration from the package at the action's own location (`github.action_path`), not from the calling repository's workspace, so the built `lkai` comes from the ref given in `uses:`. It SHALL take the directory that `swift build -c release --show-bin-path` prints for that package, SHALL add that directory to `PATH` for the later steps of the job, and SHALL NOT copy or move `lkai` out of it, because `lkai` loads the `LKAIKit_LKAICore.bundle` and `LKAIKit_LKAIKitCLI.bundle` resource bundles that the build places next to it. A failed build SHALL fail the action, and in that case the action SHALL NOT change `PATH`.

#### Scenario: Use the action from another repository

- **GIVEN** a workflow in another repository that runs `uses: leoho0722/LKAIKit@main` on a macOS runner
- **WHEN** the action finishes
- **THEN** `lkai` was built from the commit that `main` of LKAIKit pointed to when the job resolved the action
- **AND** a later step that runs `lkai -v` in the caller's workspace prints that commit's `LKAIKitInfo.version`

#### Scenario: Report a service failure when run from PATH

- **GIVEN** a job where the action has finished
- **AND** the environment variable `LKAI_ANTHROPIC_API_KEY` holds a key that Anthropic rejects
- **WHEN** a later step runs `lkai --provider anthropic -m claude-opus-5-5 -p hi` in a directory outside the package
- **THEN** `lkai` exits with status 1
- **AND** the first line of stderr starts with `Error: `

#### Scenario: The build fails

- **GIVEN** the action's source does not compile
- **WHEN** the action runs
- **THEN** the action fails
- **AND** a later step does not find `lkai` on `PATH`

### Requirement: macOS runner only

When the job does not run on macOS, the action SHALL fail before building, with an error annotation stating that it needs a macOS runner. The annotation SHALL NOT name a specific runner label, because the action depends only on macOS and its Swift toolchain, not on a label.

#### Scenario: Use the action on a Linux runner

- **GIVEN** a job that runs on `ubuntu-latest`
- **WHEN** the job uses the action
- **THEN** the action fails without running `swift build`
- **AND** the job log shows an error annotation that says a macOS runner is needed
