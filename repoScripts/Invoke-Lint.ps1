<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the repo's PowerShell code with PSScriptAnalyzerSettings.psd1. Used locally and by CI.
.DESCRIPTION
    Analyzes the .ps1 files under src/, repoScripts/ and tests/, plus the build script, and fails (throws) on any
    Error or Warning. The .psd1 files are skipped on purpose: the source manifest points at a format file that only
    exists in a built module, so the analyzer cannot validate it.
    tests/ gets two more exclusions, because its helpers are test scaffolding rather than a public API
    (plural nouns such as Get-FixtureLines, and state-changing verbs without ShouldProcess).
#>
[CmdletBinding()]
param ()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$testOnlyExcludes = @('PSUseSingularNouns', 'PSUseShouldProcessForStateChangingFunctions')

$findings = @()
foreach ($target in @('src', 'repoScripts', 'tests')) {
    $files = Get-ChildItem (Join-Path $root $target) -Filter *.ps1 -File -Recurse
    $config = Import-PowerShellDataFile $settings
    if ($target -eq 'tests') {
        $config.ExcludeRules = @($config.ExcludeRules) + $testOnlyExcludes
    }
    foreach ($file in $files) {
        $findings += Invoke-ScriptAnalyzer -Path $file.FullName -Settings $config
    }
}
# The build script's parameters are read inside InvokeBuild tasks, which the analyzer cannot see, so it reports
# them as unused.
$buildConfig = Import-PowerShellDataFile $settings
$buildConfig.ExcludeRules = @($buildConfig.ExcludeRules) + 'PSReviewUnusedParameter'
$findings += Invoke-ScriptAnalyzer -Path (Join-Path $root 'specialK.build.ps1') -Settings $buildConfig

if ($findings) {
    $findings | ForEach-Object { "$($_.Severity): $($_.RuleName) $($_.ScriptPath):$($_.Line) $($_.Message)" } | Write-Output
    throw "PSScriptAnalyzer found $(@($findings).Count) problem(s)."
}
Write-Output 'PSScriptAnalyzer: no Error or Warning findings.'
