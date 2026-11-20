# The build runs on a clean machine: no cluster, no kubectl. Offline (see TestHelpers.ps1).
# Format views are generated from the fixtures; a full ModuleBuild output must import cleanly.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:fixtureViews = Get-FixtureManifest | Where-Object typeName |
        Group-Object typeName | ForEach-Object { @{ TypeName = $_.Name; Fixture = $_.Group[0].name } }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:generator = Join-Path $script:RepoRoot 'repoScripts' 'New-FormatFile.ps1'
    $script:pwsh = (Get-Process -Id $PID).Path
    $script:work = Join-Path ([System.IO.Path]::GetTempPath()) "specialK-build-test-$([guid]::NewGuid().ToString('N'))"
    New-Item $script:work -ItemType Directory | Out-Null

    # a copy of the manifest and fixtures that a test can break without touching the real ones
    function New-FixtureCopy {
        param([string]$Name)
        $dir = Join-Path $script:work $Name
        Copy-Item $script:FixtureDir $dir -Recurse
        $dir
    }
}

AfterAll {
    Remove-Item $script:work -Recurse -Force -ErrorAction Ignore
}

Describe 'format file generation' {
    BeforeAll {
        $script:formatFile = Join-Path $script:work 'gen' 'k.format.ps1xml'
        & $script:generator -OutPath $script:formatFile 6>$null
        $script:xml = [xml](Get-Content $script:formatFile -Raw)
    }

    It 'writes well-formed XML with one view per distinct type name' {
        $distinct = @(Get-FixtureManifest | Where-Object typeName | Select-Object -ExpandProperty typeName -Unique)
        $names = @($script:xml.Configuration.ViewDefinitions.View.Name)
        $names.Count | Should -Be $distinct.Count
        $names | Sort-Object | Should -Be ($distinct | Sort-Object)
    }

    It 'is accepted by Update-FormatData' {
        # in a child process so the test session keeps its own format data
        $out = & $script:pwsh -NoProfile -NonInteractive -c "`$ErrorActionPreference='Stop'; Update-FormatData -PrependPath '$($script:formatFile)'; (Get-FormatData -TypeName get-pod-ns).TypeNames -join ','"
        $LASTEXITCODE | Should -Be 0
        $out | Should -Be 'get-pod-ns'
    }

    It 'gives <TypeName> the columns of its fixture header, in order' -ForEach $script:fixtureViews {
        $expected = (Get-ExpectedTable (Get-FixtureLines $Fixture)).Columns
        $view = $script:xml.Configuration.ViewDefinitions.View | Where-Object Name -eq $TypeName
        @($view.TableControl.TableHeaders.TableColumnHeader.Label) | Should -Be $expected
        @($view.TableControl.TableRowEntries.TableRowEntry.TableColumnItems.TableColumnItem.PropertyName) | Should -Be $expected
        @($view.ViewSelectedBy.TypeName) | Should -Be @($TypeName)
    }

    It 'puts NAMESPACE first in the -ns views, like kubectl' {
        $view = $script:xml.Configuration.ViewDefinitions.View | Where-Object Name -eq 'get-pod-ns'
        @($view.TableControl.TableHeaders.TableColumnHeader.Label)[0] | Should -Be 'NAMESPACE'
    }

    It 'keeps multi-word and punctuated headers whole' {
        $labels = @($script:xml.Configuration.ViewDefinitions.View | Where-Object Name -eq 'get-events' |
            ForEach-Object { $_.TableControl.TableHeaders.TableColumnHeader.Label })
        $labels | Should -Contain 'LAST SEEN'
        $top = @($script:xml.Configuration.ViewDefinitions.View | Where-Object Name -eq 'top-pod' |
            ForEach-Object { $_.TableControl.TableHeaders.TableColumnHeader.Label })
        $top | Should -Contain 'CPU(cores)'
    }

    It 'has a view for every type name k can emit for every entry in formats.json' {
        # k emits <verb>-<resource>, plus -wide (get only) and -ns (namespaced resources) variants
        $commands = Get-Content (Join-Path $script:RepoRoot 'src' 'formats.json') -Raw | ConvertFrom-Json -AsHashtable
        $views = @($script:xml.Configuration.ViewDefinitions.View.Name)
        $notNamespaced = 'namespace', 'node'
        $emittable = foreach ($verb in $commands.Keys) {
            foreach ($resource in $commands[$verb]) {
                "$verb-$resource"
                $namespaced = $verb -ne 'config' -and $notNamespaced -notcontains $resource
                if ($verb -eq 'get') { "$verb-$resource-wide" }
                if ($namespaced) { "$verb-$resource-ns" }
                if ($verb -eq 'get' -and $namespaced) { "$verb-$resource-ns-wide" }
            }
        }
        $emittable.Count | Should -BeGreaterThan 10
        $missing = @($emittable | Where-Object { $views -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because "k would stamp these type names but no view formats them: $($missing -join ', ')"
    }

    It 'is deterministic' {
        $again = Join-Path $script:work 'gen2' 'k.format.ps1xml'
        & $script:generator -OutPath $again 6>$null
        (Get-FileHash $again).Hash | Should -Be (Get-FileHash $script:formatFile).Hash
    }

    It 'fails, naming the view, when a required fixture is missing' {
        $dir = New-FixtureCopy 'missing'
        $manifestPath = Join-Path $dir 'fixtures.json'
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $m.fixtures = @($m.fixtures | Where-Object name -ne 'get-pod-ns-wide')
        $m | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
        $out = Join-Path $script:work 'missing-out' 'k.format.ps1xml'
        { & $script:generator -OutPath $out -ManifestPath $manifestPath 6>$null } | Should -Throw '*get-pod-ns-wide*'
        Test-Path $out | Should -BeFalse
    }

    It 'fails when two fixtures give one type name different columns' {
        $dir = New-FixtureCopy 'disagree'
        $manifestPath = Join-Path $dir 'fixtures.json'
        # get-deployment-by-name shares the type name get-deployment with get-deployment
        Set-Content (Join-Path $dir 'get-deployment-by-name.txt') "NAME   READY   OTHER`nweb   1/1   x`n"
        $out = Join-Path $script:work 'disagree-out' 'k.format.ps1xml'
        { & $script:generator -OutPath $out -ManifestPath $manifestPath 6>$null } | Should -Throw '*disagree*'
    }

    It 'fails when a fixture file is empty' {
        $dir = New-FixtureCopy 'noheader'
        $manifestPath = Join-Path $dir 'fixtures.json'
        Set-Content (Join-Path $dir 'get-node.txt') -Value '' -NoNewline
        $out = Join-Path $script:work 'noheader-out' 'k.format.ps1xml'
        { & $script:generator -OutPath $out -ManifestPath $manifestPath 6>$null } | Should -Throw '*no header*'
    }

    It 'never calls kubectl' {
        Get-Content $script:generator -Raw | Should -Not -Match '(?m)^\s*(&\s*)?kubectl\b'
        Get-Content $script:generator -Raw | Should -Not -Match '(?m)^\s*k\s'
    }
}

Describe 'ModuleBuild output' {
    BeforeAll {
        $script:buildDir = Join-Path $script:work 'build'
        $buildFile = Join-Path $script:RepoRoot 'specialK.build.ps1'
        # a child process, as a clean machine would run it; KUBECONFIG points nowhere
        $script:buildOutput = & $script:pwsh -NoProfile -NonInteractive -c "`$env:KUBECONFIG='$($script:work)/no-such-kubeconfig'; Invoke-Build ModuleBuild -File '$buildFile' -BuildPath '$($script:buildDir)' *>&1 | Out-String"
        $script:buildExit = $LASTEXITCODE
        $script:built = Join-Path $script:buildDir 'specialK'
    }

    It 'builds without a cluster' {
        $script:buildExit | Should -Be 0 -Because $script:buildOutput
        Join-Path $script:built 'specialK.psd1' | Should -Exist
        Join-Path $script:built 'k.format.ps1xml' | Should -Exist
    }

    It 'imports cleanly and exports k and Add-specialKAutoCompletion' {
        $manifest = Join-Path $script:built 'specialK.psd1'
        $json = & $script:pwsh -NoProfile -NonInteractive -c "`$ErrorActionPreference='Stop'; Import-Module '$manifest' -Force; [pscustomobject]@{ Commands = @((Get-Command -Module specialK).Name); Views = @((Get-FormatData -TypeName get-pod, get-events-ns-wide, top-node, config-get-contexts).TypeNames) } | ConvertTo-Json -Compress"
        $LASTEXITCODE | Should -Be 0
        $result = $json | ConvertFrom-Json
        $result.Commands | Should -Contain 'k'
        $result.Commands | Should -Contain 'Add-specialKAutoCompletion'
        $result.Views | Should -Contain 'get-pod'
        $result.Views | Should -Contain 'get-events-ns-wide'
        $result.Views | Should -Contain 'top-node'
        $result.Views | Should -Contain 'config-get-contexts'
    }
}
