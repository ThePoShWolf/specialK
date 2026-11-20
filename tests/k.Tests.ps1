# Behavior that works today. Runs with no cluster and no network (see TestHelpers.ps1).
# The KnownBug tests live in k.KnownBugs.Tests.ps1.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Fixtures `k` converts to typed objects today. events is typed by a KnownBug test (type name bug),
    # and config get-clusters/get-users are not converted at all today (KnownBug).
    $script:converted = Get-FixtureManifest | Where-Object {
        $_.typeName -and $_.name -notmatch '^(get-events|config-get-(clusters|users))' -and $_.name -notmatch 'slash'
    } | ForEach-Object { @{ Name = $_.name; Kargs = @($_.args); TypeName = $_.typeName } }
    # Same, but every fixture whose properties `k` gets right, typed or not.
    $script:parsed = Get-FixtureManifest | Where-Object {
        $_.typeName -and $_.name -notmatch '^config-get-(clusters|users)' -and $_.name -notmatch 'slash'
    } | ForEach-Object { @{ Name = $_.name; Kargs = @($_.args) } }
    $script:raw = Get-FixtureManifest | Where-Object { -not $_.typeName -and -not $_.allowEmpty } |
        Where-Object { $_.name -match 'json|yaml' } | ForEach-Object { @{ Name = $_.name; Kargs = @($_.args) } }
}

Describe 'k, offline' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        Enable-RealKubectlTripwire
        $module = Import-SpecialKSource
        Install-FakeKubectl -Module $module
    }

    AfterAll {
        Remove-FakeKubectl
        Remove-SpecialKSource
        Disable-RealKubectlTripwire
    }

    BeforeEach {
        Reset-FakeKubectl
        Register-ManifestFixtures
    }

    AfterEach {
        Assert-RealKubectlNotCalled
    }

    Context 'test harness' {
        It 'resolves kubectl to the fake function, not an executable, inside the module' {
            $type = & (Get-Module specialKTest) { (Get-Command kubectl).CommandType }
            $type | Should -Be 'Function'
        }
        It 'fails loudly when a call has no registered response' {
            { k get nothing-registered } | Should -Throw '*FAKE KUBECTL*'
        }
        It 'loads objectCommands from formats.json through src/onload.ps1' {
            $commands = & (Get-Module specialKTest) { $script:objectCommands }
            $commands['get'] | Should -Contain 'pod'
            $commands['top'] | Should -Contain 'node'
        }
    }

    Context 'k converts supported kubectl tables to typed objects' {
        It '<Name>: type name is <TypeName>' -ForEach $script:converted {
            $result = @(k @Kargs)
            $result.Count | Should -BeGreaterThan 0
            foreach ($item in $result) {
                $item.PSObject.TypeNames[0] | Should -Be $TypeName
            }
        }

        It '<Name>: calls kubectl once with the arguments it was given' -ForEach $script:parsed {
            $null = k @Kargs
            $calls = Get-FakeKubectlCalls
            $calls.Count | Should -Be 1
            ($calls[0] -join ' ') | Should -Be ($Kargs -join ' ')
        }

        It '<Name>: property names and values match the fixture' -ForEach $script:parsed {
            $expected = Get-ExpectedTable (Get-FixtureLines $Name)
            $result = @(k @Kargs)
            $result.Count | Should -Be $expected.Rows.Count
            $result.Count | Should -BeGreaterThan 0
            ($result[0].PSObject.Properties.Name -join '|') | Should -Be ($expected.Columns -join '|')
            for ($i = 0; $i -lt $result.Count; $i++) {
                foreach ($column in $expected.Columns) {
                    "$($result[$i].$column)" | Should -Be $expected.Rows[$i].$column -Because "row $i column '$column'"
                }
            }
        }

        It 'get pod -A: first row has the expected cells' {
            $first = (k get pod -A)[0]
            $first.NAMESPACE | Should -Be 'default'
            $first.NAME | Should -Match '^web-'
            $first.READY | Should -Be '0/1'
            $first.STATUS | Should -Be 'ContainerCreating'
            $first.RESTARTS | Should -Be '0'
        }

        It 'config get-contexts: marks the current context and tolerates the empty NAMESPACE cell' {
            $ctx = k config get-contexts
            $ctx.CURRENT | Should -Be '*'
            $ctx.NAME | Should -Be 'k3s-specialk'
            $ctx.NAMESPACE | Should -BeNullOrEmpty
        }

        It 'top node: has the five metric columns (hand-written fixture)' {
            $node = k top node
            ($node.PSObject.Properties.Name -join '|') | Should -Be 'NAME|CPU(cores)|CPU(%)|MEMORY(bytes)|MEMORY(%)'
        }

        It 'plural resource names resolve: <Plural> -> <TypeName>' -ForEach @(
            @{ Plural = 'pods'; Fixture = 'get-pod'; TypeName = 'get-pod' }
            @{ Plural = 'deployments'; Fixture = 'get-deployment'; TypeName = 'get-deployment' }
            @{ Plural = 'services'; Fixture = 'get-service'; TypeName = 'get-service' }
            @{ Plural = 'namespaces'; Fixture = 'get-namespace'; TypeName = 'get-namespace' }
            @{ Plural = 'nodes'; Fixture = 'get-node'; TypeName = 'get-node' }
        ) {
            Set-FakeKubectl -Arguments 'get', $Plural -Fixture $Fixture
            (k get $Plural)[0].PSObject.TypeNames[0] | Should -Be $TypeName
        }

        It 'a resource name after the type keeps the type: get deployment web' {
            (k get deployment web).PSObject.TypeNames[0] | Should -Be 'get-deployment'
        }

        It 'detects wide output from <Flag>' -ForEach @(
            @{ Flag = '-o wide'; Extra = @('-o', 'wide') }
            @{ Flag = '-owide'; Extra = @('-owide') }
            @{ Flag = '-o=wide'; Extra = @('-o=wide') }
            @{ Flag = '--output wide'; Extra = @('--output', 'wide') }
            @{ Flag = '--output=wide'; Extra = @('--output=wide') }
        ) {
            Set-FakeKubectl -Arguments (@('get', 'pod') + $Extra) -Fixture 'get-pod-wide'
            (k get pod @Extra)[0].PSObject.TypeNames[0] | Should -Be 'get-pod-wide'
        }
    }

    Context 'k leaves other output alone' {
        It '<Name>: -o json/yaml output is returned unchanged, as strings' -ForEach $script:raw {
            $result = @(k @Kargs)
            ($result -join "`n") | Should -Be ((Get-FixtureLines $Name) -join "`n")
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
        }

        It 'empty output returns nothing' {
            $result = @(k get pod -n kube-public)
            $result.Count | Should -Be 0
        }

        It '<Verb> output is returned as raw lines' -ForEach @(
            @{ Verb = 'delete'; Arguments = @('delete', 'pod', 'web-x'); Text = 'pod "web-x" deleted' }
            @{ Verb = 'logs'; Arguments = @('logs', 'web-x'); Text = "line one`nline two" }
            @{ Verb = 'describe'; Arguments = @('describe', 'pod', 'web-x'); Text = "Name:         web-x`nNamespace:    default" }
        ) {
            Set-FakeKubectl -Arguments $Arguments -Text $Text
            $result = @(k @Arguments)
            ($result -join "`n") | Should -Be $Text
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
        }

        It 'a deny-listed verb streams: output reaches the pipeline before kubectl finishes' {
            Set-FakeKubectl -Arguments 'logs', '-f', 'web-x' -Text "one`ntwo"
            k logs -f web-x | ForEach-Object { Add-FakeKubectlEvent "consumer: $_" }
            $events = Get-FakeKubectlEvents
            $events[0] | Should -Be 'consumer: one'
        }
    }

    Context 'k exit code' {
        It 'leaves kubectl''s exit code in $LASTEXITCODE' {
            Set-FakeKubectl -Arguments 'get', 'pod', 'nope' -ExitCode 1
            $null = k get pod nope
            $LASTEXITCODE | Should -Be 1
        }
    }

}
