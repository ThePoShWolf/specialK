# Changelog

Releases are tagged `vMAJOR.MINOR.PATCH`. The version lives in `src/specialK.psd1`; merging to `main` releases it.

## 0.5.0

- Offline Pester suite with a fake kubectl and recorded fixtures; known bugs are pinned as tests
- Build no longer needs a cluster: format views are generated from the fixtures
- `k` passes unsupported commands straight through to kubectl by default
- Resource name and flag handling fixed (plural/short names, flags before and after the resource)
- A failing kubectl is reported as a PowerShell error
- CI: lint (PSScriptAnalyzer), unit tests on Linux and Windows, smoke test against kind on three Kubernetes versions
- Preview builds (`0.5.0-previewNNNN`) publish to the Gallery from `dev`; merging to `main` publishes the release, tags it and creates the GitHub Release
- Manifest cleanup: explicit exports, `CompatiblePSEditions`, broader tags, release notes link
- Typed columns (RESTARTS, AGE, LAST SEEN, READY, CPU, MEMORY and others) sort and filter by value but print exactly as kubectl does
- `k get` objectifies ingress, configmap, secret (names, types and counts only), persistentvolumeclaim, job and statefulset
- Completion setup with `-ToProfile` is idempotent and supports `-WhatIf`
- Import warns when an alias `k` hides the `k` function
- Devcontainer trimmed and given Docker-in-Docker and kind for a local cluster
- TODO (Anthony): reword

## Earlier releases

### 0.4.0

- Added support for `-o wide`
- Added support for `--all-namespaces`

### 0.3.0

- Improved parameter handling
- Improved parsing decision logic
- Added `get events` to objectized output
- Added `get namespace` to objectized output (#5, thanks [@Relinator](https://github.com/Relinator))
- Added support for plural subcommands on the get command (#2, thanks [@Relinator](https://github.com/Relinator))

### 0.2.1

- Fixed issue from the switch to semicolons.

### 0.2

- Now internally uses `;` as the delimiter to generate the objects, improving output for services with multiple ports.

### 0.1.1

- Minor change to build script to preserve the private data on build (Tags, ProjectUri, LicenseUri)

### 0.1.0

Initial release
