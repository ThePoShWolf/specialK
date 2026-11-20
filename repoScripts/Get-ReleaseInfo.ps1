<#
.SYNOPSIS
    Reads the module version from the source manifest and pulls a version's section out of CHANGELOG.md.
.DESCRIPTION
    Used by the release guard and the release job in CI, and by tests/ReleaseInfo.Tests.ps1. Offline; touches nothing.
    The changelog headings look like '## 0.5.0' (or '### 0.4.0' for older entries); the section runs up to the next
    heading of the same or a higher level.
.PARAMETER ManifestPath
    The source manifest. Defaults to src/specialK.psd1.
.PARAMETER ChangelogPath
    The changelog. Defaults to CHANGELOG.md in the repo root.
.PARAMETER Version
    Which version's section to extract. Defaults to the manifest's ModuleVersion.
.PARAMETER NotesOnly
    Writes just the section text (without its heading) instead of an info object. Throws when there is no section.
.OUTPUTS
    [pscustomobject] with Version, Tag ('v' + Version), HasChangelogSection and Notes; or the notes string with -NotesOnly.
#>
[CmdletBinding()]
param (
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..' 'src' 'specialK.psd1'),
    [string]$ChangelogPath = (Join-Path $PSScriptRoot '..' 'CHANGELOG.md'),
    [string]$Version,
    [switch]$NotesOnly
)
$ErrorActionPreference = 'Stop'

if (-not $Version) {
    $Version = [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version '$Version' is not MAJOR.MINOR.PATCH."
}

$notes = $null
if (Test-Path $ChangelogPath) {
    $lines = [System.IO.File]::ReadAllText((Resolve-Path $ChangelogPath).Path) -split '\r?\n'
    $start = -1
    $level = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(#{2,6})\s+v?(\d+\.\d+\.\d+)\s*$' -and $Matches[2] -eq $Version) {
            $start = $i
            $level = $Matches[1].Length
            break
        }
    }
    if ($start -ge 0) {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^(#{1,6})\s' -and $Matches[1].Length -le $level) {
                $end = $i
                break
            }
        }
        $body = ($lines[($start + 1)..($end - 1)] -join "`n").Trim()
        if ($body) {
            $notes = $body
        }
    }
}

if ($NotesOnly) {
    if (-not $notes) {
        throw "CHANGELOG.md has no section (or an empty one) for version $Version."
    }
    return $notes
}

[pscustomobject]@{
    Version             = $Version
    Tag                 = "v$Version"
    HasChangelogSection = [bool]$notes
    Notes               = $notes
}
