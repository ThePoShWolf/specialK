# specialK

[![CI](https://github.com/ThePoShWolf/specialK/actions/workflows/ci.yml/badge.svg)](https://github.com/ThePoShWolf/specialK/actions/workflows/ci.yml)
[![PowerShell Gallery version](https://img.shields.io/powershellgallery/v/specialK)](https://www.powershellgallery.com/packages/specialK)
[![PowerShell Gallery downloads](https://img.shields.io/powershellgallery/dt/specialK)](https://www.powershellgallery.com/packages/specialK)

This is **NOT** a verb-noun wrapper for `kubectl`. This is a simple, opinionated alias to `kubectl`.

specialK is designed to add PowerShell object functionality to `kubectl` while maintaining original syntax and output. For any command combinations that are supported, it calls `kubectl` directly and converts the output to PowerShell objects. For any command combinations not supported, it calls `kubectl` directly. This means that if you are familiar with `kubectl`, then you'll be familiar with specialK. If you learn specialK, then you'll be familiar with `kubectl` (and miss the objectification if you switch back to bash).

This is so true-to-source that it even works with `kubectl`'s PowerShell auto-completion (you just need to install it with `Add-specialKAutoCompletion`).

## Table of Contents

- [Why](#why)
- [Demo](#demo)
- [Installation](#installation)
- [Available Commands](#available-commands)
- [Usage Example](#usage-example)
- [Current Objectized Outputs](#current-objectized-outputs)
- [How it works and its limits](#how-it-works-and-its-limits)
- [Completion setup](#completion-setup)
- [Building and testing](#building-and-testing)
- [Releasing](#releasing)
- [ChangeLog](#changelog)

## Why

<!-- TODO (Anthony): the problem, for a reader who does not know PowerShell. Cover:
- kubectl prints text; filtering, sorting and selecting means grep/awk/jq or JSONPath
- PowerShell pipelines work on objects, so `Where-Object`, `Sort-Object`, `Select-Object` just work
- specialK is "kubectl, but the output is objects"; same syntax, nothing new to learn
- anything it does not support runs as plain kubectl, so it is never worse than the alias it replaces
- (portfolio angle, your call) tests from captured fixtures, CI against real kind clusters, automated releases
-->

## Demo

<!-- Placeholder: add a GIF or asciinema recording here, e.g. ![demo](docs/demo.gif) -->

<!-- TODO (Anthony): the before/after the recording should show. Facts to draw on:
- before: `kubectl get pods | grep ...` text, or no way to compare RESTARTS numerically
- after: `k get pods | Where-Object RESTARTS -gt 3`
- after: `k get pods | Sort-Object AGE` (RESTARTS and AGE are typed, so they sort and compare correctly; the table looks the same)
- after: `k get pods | Select-Object Name, Status`
-->

## Installation

This module requires `kubectl` to be downloaded and available in the working directory or in the `PATH` variable. You can find directions in the [kubernetes documentation](https://kubernetes.io/docs/tasks/tools/).

The module itself is installed just like any other module:

```powershell
Install-Module specialK -Repository PSGallery
```

To try a preview build (published from the `dev` branch):

```powershell
Install-PSResource specialK -Prerelease
```

## Available commands:

The module itself contains 2 commands:

- `k`
- `Add-specialKAutoCompletion`

`k` is an advanced alias for `kubectl`. For supported command combinations, it will convert the output to a PowerShell object. See [Current Objectified outputs](#current-objectized-outputs) for the full list.

`Add-specialKAutoCompletion` is a simple command that calls `kubectl completion powershell` and replaces `kubectl` with `k` to allow for `kubectl` autocompletion in specialK. specialK does not modify any `kubectl` syntax, so vanilla autocompletion works perfectly.

## Usage example

A simple listing of the pods

```powershell
k get pod
```

Output:

```plaintext
NAME                                     READY STATUS  RESTARTS AGE
----                                     ----- ------  -------- ---
blah-db-deployment-584189c448-6cszs      1/1   Running 0        3d13h
blah-monitor-deployment-7f4d5524cf-wj7nr 1/1   Running 0        21h
blah-monitor-deployment-85f748721d-7qxbq 1/1   Running 0        21h
blah-web-deployment-74bbf734b-4sdps      1/1   Running 0        21h
blah-web-deployment-74bbf734b-gs4mt      1/1   Running 0        21h
blah-web-deployment-74bbf734b-nc8kd      1/1   Running 0        21h
blah-web-deployment-74bbf734b-qddmr      1/1   Running 0        21h
```

Notice the PowerShell table headers? That means you can do:

```powershell
k get pods | ?{$_.Name -like 'blah-web*'} | %{kubectl exec $_.Name -- date}
```

This commands also demonstrates a current limitation of specialK. Since PowerShell doesn't pass `--` as a parameter, running `k exec pod-name -- command` will skip the `--`. In the future, this will be fully supported and there is no issue switching back to calling plain `kubectl` for this use case.

<!-- TODO (Anthony): the sentence above is no longer accurate. Facts:
- a bare `--` is still dropped by PowerShell before `k` sees it, but quoting it works: `k exec pod-name '--' date`
- it will not be "fully supported" in the future: this is PowerShell's parameter binding, not something `k` can fix
- the "switch back to plain kubectl" advice still holds
-->

You can also:

```powershell
k config get-contexts | ?{$_.name -like '*staging*'} | %{k config use-context $_.name}
```

## Current objectized outputs

These `kubectl` command combinations are currently supported:

- get: pod, deployment, namespace, node, service, events, ingress, configmap, secret, pvc, job, statefulset
- top: pod, node
- config: get-contexts, get-clusters, get-users

Do be aware that adding support for additional command combinations is incredibly easy. The formats are all generated at build time using a script, which you can review: [formatUpdater.ps1](repoScripts/formatUpdater.ps1).

<!-- TODO (Anthony): the paragraph above is out of date. Facts:
- the build does not run any commands or need a cluster anymore
- formats are generated at build time from captured kubectl output in tests/fixtures by repoScripts/New-FormatFile.ps1 (formatUpdater.ps1 no longer exists)
- fixtures are refreshed on purpose with repoScripts/Update-Fixtures.ps1 against a cluster
- the allow list of supported commands is src/formats.json
- `events` works now (it was listed here before but did not get its format)
- columns such as RESTARTS and AGE are typed; the default table looks the same
-->

## How it works and its limits

<!-- TODO (Anthony): explain the approach and where it stops. Facts to draw on:
- pass-through rule: anything not in the allow list (src/formats.json) runs as plain kubectl, uncaptured, so streaming and interactive commands (`-w`, `edit`, `port-forward`, `exec -it`) behave like kubectl
- supported commands: kubectl text output is captured and the table columns are sliced into typed-name objects
- design trade-offs: see docs/design/parsing.md
- limit: a bare `--` is dropped by PowerShell before `k` sees it; quote it as `'--'`
- limit: `$?` stays true after a failing `k`; use `$LASTEXITCODE` (or the error record)
- limit: a failed kubectl writes a PowerShell error that only becomes terminating when `$ErrorActionPreference = 'Stop'` is set globally
- limit: a value flag that is not in the parser's list, placed before the verb, can confuse detection of the command
- alias collision: an existing `Set-Alias k kubectl` shadows the function (aliases beat functions); importing warns, fix is `Remove-Item Alias:k`
-->

## Completion setup

```powershell
Add-specialKAutoCompletion -ToProfile
```

<!-- TODO (Anthony): wording for this section. Facts:
- without -ToProfile it registers the completer for the current session only
- -ToProfile adds one marked block (`# >>> specialK completion >>>` ... `# <<< specialK completion <<<`) to your profile that regenerates the completer at startup if kubectl is on PATH
- running it again changes nothing
- -WhatIf shows what would be written; -ProfilePath targets another profile file (default: current user, current host)
- profiles written by older versions contain a static completer snapshot (`Register-ArgumentCompleter ... -CommandName 'k'`): the command warns and does not edit it; remove that block by hand
-->

## Building and testing

Building specialK requires the InvokeBuild module, which can be installed from the PowerShell Gallery:

```powershell
Install-Module InvokeBuild
```

To build the module, ensure your working directory is the root of the repository and run:

```powershell
Invoke-Build -Task modulebuild
```

Be aware that the formats are generated by default. If you want to skip this step, be sure to use the `-ReuseFormats` switch. However, this requires that you already have a `k.format.ps1xml` file in the `build\specialK` directory in the repository.

```powershell
Invoke-Build -Task modulebuild -ReuseFormats
```

This is something that could be improved, so feel free to submit a PR that improves this process.

<!-- TODO (Anthony): the two paragraphs above (-ReuseFormats) are out of date. The build no longer needs a cluster and there is no -ReuseFormats switch; the format file is generated from tests/fixtures every build. -->

Commands:

```powershell
# install InvokeBuild, Pester and PSScriptAnalyzer
./repoScripts/Install-BuildDependency.ps1

# build the module
Invoke-Build ModuleBuild

# offline unit tests (no cluster)
Invoke-Build Test

# smoke tests against the current kube context (needs metrics-server for `k top`)
Invoke-Build ModuleBuild, SmokeTest

# create or reuse a local kind cluster named specialk with metrics-server (needs docker and kind; the devcontainer has both)
./repoScripts/New-LocalCluster.ps1

# refresh the captured kubectl output in tests/fixtures from the current kube context
./repoScripts/Update-Fixtures.ps1

# lint
./repoScripts/Invoke-Lint.ps1
```

## Releasing

1. Bump `ModuleVersion` in `src/specialK.psd1`.
2. Add a `## X.Y.Z` section to `CHANGELOG.md`.
3. Merge to `dev`; CI publishes a preview (`X.Y.Z-previewNNNN`) to test with `Install-PSResource specialK -Prerelease`.
4. Open a PR from `dev` to `main`.
5. Merging to `main` publishes `X.Y.Z` to the PowerShell Gallery, tags `vX.Y.Z` and creates the GitHub Release.

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md).
