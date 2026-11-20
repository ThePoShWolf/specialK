<#
    Shared helpers for the specialK tests. No cluster and no network are needed.

    How the code under test is loaded: the build concatenates src/using.ps1, src/public/*.ps1 and
    src/onload.ps1 into one .psm1 and ships formats.json beside it. Import-SpecialKSource does the
    same into a temp folder (same order, unmodified source files), so `k` runs inside a real module
    and finds $script:objectCommands exactly as it does when installed. It does not use ModuleBuild,
    which needs a cluster.

    How kubectl is faked: PowerShell resolves functions before executables, so a `kubectl` function
    defined inside the module's scope is what `k` calls. It serves registered responses, records the
    arguments it received, and throws if it is asked for something nobody registered. As a second
    safety net, a stub `kubectl` executable is put first on PATH. If anything ever bypasses the fake
    and reaches PATH, the stub writes a tripwire file and exits 97, and Assert-RealKubectlNotCalled
    fails the test.
#>

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'

function Get-FixtureManifest {
    (Get-Content (Join-Path $script:FixtureDir 'fixtures.json') -Raw | ConvertFrom-Json).fixtures
}

function Get-FixtureText {
    param([Parameter(Mandatory)][string]$Name)
    $entry = Get-FixtureManifest | Where-Object name -eq $Name
    if (-not $entry) { throw "No fixture named '$Name' in fixtures.json" }
    [System.IO.File]::ReadAllText((Join-Path $script:FixtureDir $entry.file))
}

function Get-FixtureLines {
    param([Parameter(Mandatory)][string]$Name)
    $text = Get-FixtureText $Name
    if ($text.Length -eq 0) { return @() }
    $text.TrimEnd("`n") -split "`n"
}

function Import-SpecialKSource {
    $src = Join-Path $script:RepoRoot 'src'
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "specialK-test-$([guid]::NewGuid().ToString('N'))"
    New-Item $dir -ItemType Directory | Out-Null
    Copy-Item (Join-Path $src 'formats.json') $dir
    $parts = & {
        Get-Item (Join-Path $src 'using.ps1')
        Get-ChildItem (Join-Path $src 'public') -Filter *.ps1 -File
        Get-Item (Join-Path $src 'onload.ps1')
    }
    $psm1 = Join-Path $dir 'specialKTest.psm1'
    $parts | ForEach-Object { Get-Content $_.FullName -Raw } | Set-Content $psm1 -Encoding utf8
    $script:TestModuleDir = $dir
    Import-Module $psm1 -Force -PassThru
}

function Remove-SpecialKSource {
    Get-Module specialKTest | Remove-Module -Force
    if ($script:TestModuleDir) { Remove-Item $script:TestModuleDir -Recurse -Force -ErrorAction Ignore }
}

function Install-FakeKubectl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module)
    & $Module {
        $script:FakeKubectl = @{
            Responses = @{}
            Calls     = [System.Collections.Generic.List[object]]::new()
            Events    = [System.Collections.Generic.List[string]]::new()
        }
        function script:kubectl {
            # `k` calls `& kubectl $args`; a function receives that array as ONE argument, a native
            # command would receive it splatted. Flatten so the fake sees what real kubectl would.
            $argv = @($args | ForEach-Object { $_ })
            $script:FakeKubectl.Calls.Add($argv)
            $key = $argv -join ' '
            if (-not $script:FakeKubectl.Responses.ContainsKey($key)) {
                throw "FAKE KUBECTL: no response registered for 'kubectl $key'. Tests must register every call they expect."
            }
            $response = $script:FakeKubectl.Responses[$key]
            $global:LASTEXITCODE = $response.ExitCode
            $lines = if ($response.Text.Length -eq 0) { @() } else { $response.Text.TrimEnd("`n") -split "`n" }
            foreach ($line in $lines) {
                $line
                # Lets a test tell streaming from buffering: this runs after the consumer saw $line
                # only when the caller did not capture our output.
                $script:FakeKubectl.Events.Add("kubectl: after emitting '$line'")
            }
        }
    }
}

function Set-FakeKubectl {
    <# Register what `kubectl <Arguments>` returns. Use -Fixture, or -Text for inline output. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Fixture,
        [string]$Text = '',
        [int]$ExitCode = 0
    )
    if ($Fixture) { $Text = Get-FixtureText $Fixture }
    $key = $Arguments -join ' '
    & (Get-Module specialKTest) {
        param($key, $text, $exit)
        $script:FakeKubectl.Responses[$key] = @{ Text = $text; ExitCode = $exit }
    } $key $Text $ExitCode
}

function Register-ManifestFixtures {
    # Every manifest entry answers to exactly the arguments that produced it.
    foreach ($entry in Get-FixtureManifest) {
        Set-FakeKubectl -Arguments $entry.args -Fixture $entry.name
    }
}

function Get-FakeKubectlCalls {
    & (Get-Module specialKTest) { , @($script:FakeKubectl.Calls) }
}

function Get-FakeKubectlEvents {
    & (Get-Module specialKTest) { , @($script:FakeKubectl.Events) }
}

function Add-FakeKubectlEvent {
    param([string]$Message)
    & (Get-Module specialKTest) { param($m) $script:FakeKubectl.Events.Add($m) } $Message
}

function Reset-FakeKubectl {
    & (Get-Module specialKTest) {
        $script:FakeKubectl.Responses.Clear()
        $script:FakeKubectl.Calls.Clear()
        $script:FakeKubectl.Events.Clear()
    }
    $global:LASTEXITCODE = 0
}

function Remove-FakeKubectl {
    $m = Get-Module specialKTest
    if ($m) { & $m { Remove-Item function:script:kubectl -ErrorAction Ignore; $script:FakeKubectl = $null } }
}

function Enable-RealKubectlTripwire {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "specialK-tripwire-$([guid]::NewGuid().ToString('N'))"
    New-Item $dir -ItemType Directory | Out-Null
    $script:TripwireDir = $dir
    $script:TripwireFile = Join-Path $dir 'REAL-KUBECTL-CALLED'
    $script:OriginalPath = $env:PATH
    $env:SPECIALK_TRIPWIRE = $script:TripwireFile
    if ($IsWindows) {
        Set-Content (Join-Path $dir 'kubectl.cmd') "@echo off`r`necho called> `"%SPECIALK_TRIPWIRE%`"`r`necho specialK tests must not call the real kubectl 1>&2`r`nexit /b 97"
    } else {
        $stub = Join-Path $dir 'kubectl'
        Set-Content $stub "#!/bin/sh`necho called > `"`$SPECIALK_TRIPWIRE`"`necho 'specialK tests must not call the real kubectl' >&2`nexit 97"
        & chmod +x $stub
    }
    $env:PATH = $dir + [System.IO.Path]::PathSeparator + $env:PATH
}

function Assert-RealKubectlNotCalled {
    if (Test-Path $script:TripwireFile) {
        throw 'The REAL kubectl executable was called during a test. The fake was bypassed.'
    }
}

function Disable-RealKubectlTripwire {
    if ($script:OriginalPath) { $env:PATH = $script:OriginalPath }
    Remove-Item Env:\SPECIALK_TRIPWIRE -ErrorAction Ignore
    if ($script:TripwireDir) { Remove-Item $script:TripwireDir -Recurse -Force -ErrorAction Ignore }
}

function Get-ExpectedTable {
    <#
        Independent reference parse of kubectl's fixed-width table text, used to check `k`.
        Column starts are the header's words that follow two or more spaces (or begin the line);
        a cell is the text from its column start to the next one, trimmed. Header-only layout,
        so empty cells are fine.
    #>
    param([Parameter(Mandatory)][string[]]$Lines)
    $header = $Lines[0]
    $starts = @([regex]::Matches($header, '(?:^|(?<=\s\s))\S') | ForEach-Object { $_.Index })
    $columns = for ($i = 0; $i -lt $starts.Count; $i++) {
        $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1] } else { $header.Length }
        $header.Substring($starts[$i], $end - $starts[$i]).Trim()
    }
    $rows = foreach ($line in $Lines | Select-Object -Skip 1) {
        $row = [ordered]@{}
        for ($i = 0; $i -lt $starts.Count; $i++) {
            $cell = ''
            if ($line.Length -gt $starts[$i]) {
                $end = if ($i + 1 -lt $starts.Count) { [Math]::Min($starts[$i + 1], $line.Length) } else { $line.Length }
                $cell = $line.Substring($starts[$i], $end - $starts[$i]).Trim()
            }
            $row[$columns[$i]] = $cell
        }
        [pscustomobject]$row
    }
    [pscustomobject]@{ Columns = @($columns); Rows = @($rows) }
}
