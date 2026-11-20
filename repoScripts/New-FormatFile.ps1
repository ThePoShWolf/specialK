<#
.SYNOPSIS
    Generates k.format.ps1xml from the kubectl fixtures. Never runs kubectl.

.DESCRIPTION
    Every entry in tests/fixtures/fixtures.json that has a "typeName" becomes one table view with
    that name. Its columns are the words of the fixture's header line, in the same order. The
    fixtures are the single source of truth for column headers; to pick up a new kubectl layout,
    refresh them on purpose with repoScripts/Update-Fixtures.ps1 and review the diff.

    Header splitting follows how `k` slices kubectl's tables: columns are separated by two or
    more spaces, so 'LAST SEEN' and 'CPU(cores)' stay whole.

    Two fixtures with the same typeName (e.g. 'get deployment' and 'get deployment web') are
    deduplicated, and must have identical columns or generation fails.

    Required views. For every verb/resource in src/formats.json the build needs the views that
    `k` can emit for it, and generation fails, listing every gap, if one has no fixture:
      - base view                  '<verb>-<resource>'                       always
      - wide view                  '<verb>-<resource>-wide'                  verbs other than top and config
                                                                             (kubectl has no -o wide for them)
      - all-namespaces view        '<verb>-<resource>-ns'                    namespaced resources only
      - all-namespaces wide view   '<verb>-<resource>-ns-wide'               namespaced resources, verbs with wide
    Cluster-scoped resources (see $clusterScoped) have no -A form, so no -ns views. 'config'
    subcommands (get-contexts and friends) are not namespaced resources either.

    Generation is deterministic: the same fixtures always give the same file.

.PARAMETER OutPath
    Where to write k.format.ps1xml.

.PARAMETER FormatsPath
    The verb -> resources allow list. Defaults to src/formats.json.

.PARAMETER ManifestPath
    The fixture manifest. Defaults to tests/fixtures/fixtures.json.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$OutPath,
    [string]$FormatsPath = (Join-Path $PSScriptRoot '..' 'src' 'formats.json'),
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..' 'tests' 'fixtures' 'fixtures.json')
)
$ErrorActionPreference = 'Stop'

# Resources with no namespace, so no `-A` and no '-ns' views.
$clusterScoped = @('namespace', 'node')
# Verbs whose output has no `-o wide` form.
$noWideVerbs = @('top', 'config')
# Verbs whose resources are not namespaced resources at all.
$noNamespaceVerbs = @('config')

function Get-HeaderColumn {
    param([string]$Header)
    @($Header.Trim() -split '\s{2,}' | Where-Object { $_ -ne '' })
}

function New-FormatView {
    param(
        [string]$name,
        [string[]]$props
    )
    $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
    # create the view
    '        <View>'
    '            <Name>{0}</Name>' -f (& $esc $name)
    '            <ViewSelectedBy>'
    '                <TypeName>{0}</TypeName>' -f (& $esc $name)
    '            </ViewSelectedBy>'
    '            <TableControl>'
    '                <TableHeaders>'
    # create the headers
    foreach ($header in $props) {
        '                    <TableColumnHeader><Label>{0}</Label></TableColumnHeader>' -f (& $esc $header)
    }
    '                </TableHeaders>'
    '                <TableRowEntries>'
    '                    <TableRowEntry>'
    '                        <TableColumnItems>'
    # create the column items
    foreach ($tci in $props) {
        '                            <TableColumnItem><PropertyName>{0}</PropertyName></TableColumnItem>' -f (& $esc $tci)
    }
    '                        </TableColumnItems>'
    '                    </TableRowEntry>'
    '                </TableRowEntries>'
    '            </TableControl>'
    '        </View>'
}

$manifestFull = (Resolve-Path $ManifestPath).Path
$fixtureDir = Split-Path $manifestFull -Parent
$entries = (Get-Content $manifestFull -Raw | ConvertFrom-Json).fixtures | Where-Object { $_.typeName }

# typeName -> columns, from each fixture's header line
$views = [ordered]@{}
$viewSource = @{}
foreach ($entry in $entries) {
    $file = Join-Path $fixtureDir $entry.file
    if (-not (Test-Path $file)) {
        throw "Fixture '$($entry.name)' lists file '$($entry.file)' but it does not exist."
    }
    $header = [System.IO.File]::ReadAllText($file) -split "`r?`n" | Select-Object -First 1
    $columns = Get-HeaderColumn $header
    if ($columns.Count -eq 0) {
        throw "Fixture '$($entry.name)' ($($entry.file)) has no header line, so no view can be generated for '$($entry.typeName)'."
    }
    if ($views.Contains($entry.typeName)) {
        if (($views[$entry.typeName] -join "`n") -ne ($columns -join "`n")) {
            throw ("Fixtures '{0}' and '{1}' both provide '{2}' but disagree on columns:`n  [{3}]`n  [{4}]" -f
                $viewSource[$entry.typeName], $entry.name, $entry.typeName,
                ($views[$entry.typeName] -join ' | '), ($columns -join ' | '))
        }
        continue
    }
    $views[$entry.typeName] = $columns
    $viewSource[$entry.typeName] = $entry.name
}

# every view `k` can emit for a listed resource must exist
$commands = Get-Content $FormatsPath -Raw | ConvertFrom-Json -AsHashtable
$missing = foreach ($verb in $commands.Keys | Sort-Object) {
    foreach ($resource in $commands[$verb]) {
        $base = "$verb-$resource"
        $required = [System.Collections.Generic.List[string]]::new()
        $required.Add($base)
        $namespaced = ($verb -notin $noNamespaceVerbs) -and ($resource -notin $clusterScoped)
        $hasWide = $verb -notin $noWideVerbs
        if ($hasWide) { $required.Add("$base-wide") }
        if ($namespaced) { $required.Add("$base-ns") }
        if ($namespaced -and $hasWide) { $required.Add("$base-ns-wide") }
        foreach ($name in $required) {
            if (-not $views.Contains($name)) { $name }
        }
    }
}
if ($missing) {
    throw ("No fixture provides these views, which 'src/formats.json' makes necessary: {0}. " -f ($missing -join ', ') +
        "Add a fixture with that typeName to tests/fixtures/fixtures.json (repoScripts/Update-Fixtures.ps1 captures them).")
}

$addViews = foreach ($name in $views.Keys) {
    New-FormatView -name $name -props $views[$name]
}

$outDir = Split-Path $OutPath -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item $outDir -ItemType Directory | Out-Null }
@(
    '<Configuration>'
    '    <ViewDefinitions>'
    $addViews
    '    </ViewDefinitions>'
    '</Configuration>'
) | Out-File $OutPath -Force -Encoding utf8
Write-Host "Generated $($views.Count) views in $OutPath"
