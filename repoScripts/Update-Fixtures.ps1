<#
.SYNOPSIS
    Captures the kubectl output that the tests use as fixtures.

.DESCRIPTION
    Reads tests/fixtures/fixtures.json, runs each entry's kubectl arguments against the
    current kube context (kubectl is called directly, never through `k`), and writes
    stdout to the entry's file under tests/fixtures/.

    Any failure is a terminating error that names the command: a non-zero exit code,
    output (stdout or stderr) starting with 'error:', or empty stdout for an entry that
    is not marked "allowEmpty". Nothing is skipped silently.

    Entries marked "metrics": true need a cluster with the Metrics API (kubectl top).
    On a cluster without one, pass -SkipTop; the skipped entries are listed in a warning
    and their existing (hand-written) fixture files are left alone. When such an entry is
    captured, its "source" in the manifest is updated to "captured".

    The first line of each fixture is the column header line; later phases generate the
    format file from these fixtures, so they are the source of truth for column headers.

.PARAMETER SkipTop
    Do not capture entries that need the Metrics API (top pod / top node).

.PARAMETER ManifestPath
    Path to the manifest. Defaults to tests/fixtures/fixtures.json.
#>
[CmdletBinding()]
param (
    [switch]$SkipTop,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..' 'tests' 'fixtures' 'fixtures.json')
)
$ErrorActionPreference = 'Stop'

$ManifestPath = (Resolve-Path $ManifestPath).Path
$fixtureDir = Split-Path $ManifestPath -Parent
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -Depth 10

if (-not (Get-Command kubectl -CommandType Application -ErrorAction Ignore)) {
    throw 'kubectl was not found on PATH.'
}
Write-Host "Context: $(& kubectl config current-context)"

$errFile = New-TemporaryFile
$changed = $false
$skipped = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($entry in $manifest.fixtures) {
        $display = "kubectl $($entry.args -join ' ')"
        if ($entry.metrics -and $SkipTop) {
            $skipped.Add("$($entry.file) ($display)")
            continue
        }

        $stdout = & kubectl @($entry.args) 2> $errFile
        $exit = $LASTEXITCODE
        $stderr = (Get-Content $errFile -Raw)
        if ($null -eq $stderr) { $stderr = '' }
        $lines = @($stdout)

        if ($exit -ne 0) {
            throw "'$display' failed with exit code $exit. stderr: $($stderr.Trim())"
        }
        if ($stderr -match '^\s*error:' -or ($lines.Count -gt 0 -and "$($lines[0])" -match '^\s*error:')) {
            throw "'$display' reported an error. stderr: $($stderr.Trim()); stdout: $($lines -join ' ')"
        }
        if ($lines.Count -eq 0 -and -not $entry.allowEmpty) {
            throw "'$display' returned no output, and the manifest entry '$($entry.name)' does not set allowEmpty."
        }

        # LF line endings, trailing newline, UTF-8 without BOM. Empty output is a zero-byte file.
        $text = if ($lines.Count -eq 0) { '' } else { ($lines -join "`n") + "`n" }
        [System.IO.File]::WriteAllText((Join-Path $fixtureDir $entry.file), $text, [System.Text.UTF8Encoding]::new($false))
        Write-Host "captured $($entry.file) <- $display"

        if ($entry.source -ne 'captured') {
            $entry.source = 'captured'
            $changed = $true
        }
    }
} finally {
    Remove-Item $errFile -ErrorAction Ignore
}

if ($changed) {
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $ManifestPath -Encoding utf8NoBOM
    Write-Host 'Manifest updated: some entries are now captured.'
}
if ($skipped.Count -gt 0) {
    Write-Warning "-SkipTop: not captured, existing files kept:`n  $($skipped -join "`n  ")"
}
