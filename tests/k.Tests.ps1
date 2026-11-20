# What `k` does with kubectl output and arguments. Runs with no cluster and no network (see TestHelpers.ps1).

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Fixtures `k` converts to typed objects. The slash fixture is `get deployment/web`, checked by its own test.
    $script:converted = Get-FixtureManifest | Where-Object {
        $_.typeName -and $_.name -notmatch 'slash'
    } | ForEach-Object { @{ Name = $_.name; Kargs = @($_.args); TypeName = $_.typeName } }
    # Every fixture whose properties are compared with an independent parse of the fixture text.
    $script:parsed = Get-FixtureManifest | Where-Object {
        $_.typeName -and $_.name -notmatch 'slash'
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

    }

    Context 'k exit code' {
        It 'leaves kubectl''s exit code in $LASTEXITCODE, converted or passed through: <Kargs>' -ForEach @(
            @{ Kargs = @('get', 'pod', 'nope') }
            @{ Kargs = @('describe', 'pod', 'nope') }
        ) {
            Set-FakeKubectl -Arguments $Kargs -ExitCode 1
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'SilentlyContinue'
                $null = k @Kargs
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $LASTEXITCODE | Should -Be 1
        }

        It 'a failure is reported as an error record that names the exit code: <Kargs>' -ForEach @(
            @{ Kargs = @('get', 'pod', 'nope') }
            @{ Kargs = @('describe', 'pod', 'nope') }
        ) {
            Set-FakeKubectl -Arguments $Kargs -ExitCode 4
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                k @Kargs > $null
                $message = "$($Error[0])"
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $Error.Count | Should -BeGreaterThan 0
            $message | Should -Match 'exit code 4'
        }

        It 'names only the verb and the first resource in the error: <Expected>' -ForEach @(
            @{ Kargs = @('get', 'nosuchthing', '-n', 'demo'); Expected = 'kubectl get nosuchthing failed with exit code 1' }
            @{ Kargs = @('version'); Expected = 'kubectl version failed with exit code 1' }
            @{ Kargs = @('--context', 'x'); Expected = 'kubectl failed with exit code 1' }
        ) {
            Set-FakeKubectl -Arguments $Kargs -ExitCode 1
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                k @Kargs > $null
                $record = $Error[0]
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $record.Exception.Message | Should -BeExactly $Expected
            $record.TargetObject | Should -BeExactly ($Expected -replace ' failed with exit code 1$')
        }

        It 'keeps credential arguments out of the error record: <Kargs>' -ForEach @(
            @{ Kargs = @('get', 'nosuchthing', '--token=hunter2xyz') }
            @{ Kargs = @('get', 'nosuchthing', '--token', 'hunter2xyz') }
            @{ Kargs = @('create', 'secret', 'generic', 'db', '--from-literal=pw=hunter2xyz') }
            @{ Kargs = @('--password=hunter2xyz', 'get', 'pod', 'web') }
        ) {
            Set-FakeKubectl -Arguments $Kargs -ExitCode 1
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                k @Kargs > $null
                $record = $Error[0]
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $record | Should -Not -BeNullOrEmpty
            $everything = @($record.Exception.Message, "$($record.TargetObject)", "$record", ($record | Out-String)) -join "`n"
            $everything | Should -Not -Match 'hunter2xyz'
        }

        It 'a successful call writes no error' {
            $Error.Clear()
            k get pod > $null
            $Error.Count | Should -Be 0
        }
    }

    Context 'k passes unsupported commands through unchanged' {
        It 'k <Command> returns kubectl''s raw lines, not objects' -ForEach @(
            @{ Command = 'get daemonset -A'; Kargs = @('get', 'daemonset', '-A'); Fixture = 'get-pod-ns' }
            @{ Command = 'get cronjob -n kube-system'; Kargs = @('get', 'cronjob', '-n', 'kube-system'); Fixture = 'get-pod' }
            @{ Command = 'get pods -w'; Kargs = @('get', 'pods', '-w'); Fixture = 'get-pod' }
            @{ Command = 'get pods -o yaml'; Kargs = @('get', 'pods', '-o', 'yaml'); Fixture = 'get-service-yaml' }
            @{ Command = 'get pods --no-headers'; Kargs = @('get', 'pods', '--no-headers'); Fixture = 'get-pod' }
            @{ Command = 'get pods,svc'; Kargs = @('get', 'pods,svc'); Fixture = 'get-pod' }
            @{ Command = 'get replicaset'; Kargs = @('get', 'replicaset'); Fixture = 'get-pod' }
        ) {
            Set-FakeKubectl -Arguments $Kargs -Fixture $Fixture
            $result = @(k @Kargs)
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
            ($result -join "`n") | Should -Be ((Get-FixtureLines $Fixture) -join "`n")
        }

        It 'k <Command> streams: output reaches the pipeline before kubectl finishes' -ForEach @(
            @{ Command = 'get pods -w'; Kargs = @('get', 'pods', '-w') }
            @{ Command = 'edit deployment web'; Kargs = @('edit', 'deployment', 'web') }
            @{ Command = 'port-forward svc/web 8080:80'; Kargs = @('port-forward', 'svc/web', '8080:80') }
            @{ Command = 'attach web-x'; Kargs = @('attach', 'web-x') }
            @{ Command = 'exec -it web-x -- sh'; Kargs = @('exec', '-it', 'web-x', '--', 'sh') }
            @{ Command = 'logs -f web-x'; Kargs = @('logs', '-f', 'web-x') }
        ) {
            Set-FakeKubectl -Arguments $Kargs -Text "first`nsecond"
            k @Kargs | ForEach-Object { Add-FakeKubectlEvent "consumer: $_" }
            $events = Get-FakeKubectlEvents
            $events[0] | Should -Be 'consumer: first' -Because 'k captured the output instead of passing it straight through'
        }
    }

    Context 'type names' {
        It 'k <Kargs> gets type name <TypeName>' -ForEach @(
            @{ Name = 'get-events'; Kargs = @('get', 'events'); TypeName = 'get-events' }
            @{ Name = 'get-events-wide'; Kargs = @('get', 'events', '-o', 'wide'); TypeName = 'get-events-wide' }
            @{ Name = 'get-events-ns'; Kargs = @('get', 'events', '-A'); TypeName = 'get-events-ns' }
            @{ Name = 'get-events-ns-wide'; Kargs = @('get', 'events', '-A', '-o', 'wide'); TypeName = 'get-events-ns-wide' }
        ) {
            (k @Kargs)[0].PSObject.TypeNames[0] | Should -Be $TypeName
        }

        It 'short name "<Short>" resolves like "<Full>"' -ForEach @(
            @{ Short = 'po'; Full = 'pod'; Fixture = 'get-pod' }
            @{ Short = 'deploy'; Full = 'deployment'; Fixture = 'get-deployment' }
            @{ Short = 'svc'; Full = 'service'; Fixture = 'get-service' }
            @{ Short = 'ns'; Full = 'namespace'; Fixture = 'get-namespace' }
            @{ Short = 'no'; Full = 'node'; Fixture = 'get-node' }
            @{ Short = 'ev'; Full = 'events'; Fixture = 'get-events' }
        ) {
            Set-FakeKubectl -Arguments 'get', $Short -Fixture $Fixture
            (k get $Short)[0].PSObject.TypeNames[0] | Should -Be "get-$Full"
        }

        It 'type/name form "<Form>" resolves to <TypeName>' -ForEach @(
            @{ Form = 'pod/web-x'; Fixture = 'get-pod'; TypeName = 'get-pod' }
            @{ Form = 'deployment/web'; Fixture = 'get-deployment-slash'; TypeName = 'get-deployment' }
            @{ Form = 'deploy/web'; Fixture = 'get-deployment-slash'; TypeName = 'get-deployment' }
        ) {
            Set-FakeKubectl -Arguments 'get', $Form -Fixture $Fixture
            (k get $Form)[0].PSObject.TypeNames[0] | Should -Be $TypeName
        }

        It 'config <Resource> is converted to objects with type config-<Resource>' -ForEach @(
            @{ Resource = 'get-clusters' }
            @{ Resource = 'get-users' }
        ) {
            # The header line is just "NAME" (one column, no trailing space), which the header check misses.
            $result = @(k config $Resource)
            $result[0] | Should -Not -BeOfType [string]
            $result[0].NAME | Should -Be 'k3s-specialk'
            $result[0].PSObject.TypeNames[0] | Should -Be "config-$Resource"
        }
    }

    Context 'global flags and flag position' {
        It 'k <Command> is detected as <TypeName>' -ForEach @(
            @{ Command = '-n kube-system get pods'; Kargs = @('-n', 'kube-system', 'get', 'pods'); TypeName = 'get-pod' }
            @{ Command = '--context foo get pods'; Kargs = @('--context', 'foo', 'get', 'pods'); TypeName = 'get-pod' }
            @{ Command = '--namespace=kube-system get pods'; Kargs = @('--namespace=kube-system', 'get', 'pods'); TypeName = 'get-pod' }
            @{ Command = 'get -n demo pods'; Kargs = @('get', '-n', 'demo', 'pods'); TypeName = 'get-pod' }
        ) {
            Set-FakeKubectl -Arguments $Kargs -Fixture 'get-pod'
            (k @Kargs)[0].PSObject.TypeNames[0] | Should -Be $TypeName
        }
    }

    Context 'robustness and errors' {
        It 'a data line shorter than a header position does not throw' {
            $text = "NAME   READY   STATUS    RESTARTS   AGE`nweb    1/1`n"
            Set-FakeKubectl -Arguments 'get', 'pod' -Text $text
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'Stop'
                $result = @(k get pod)
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $result.Count | Should -Be 1
            $result[0].NAME | Should -Be 'web'
            $result[0].READY | Should -Be '1/1'
        }

        It 'a failing kubectl call (non-zero exit code) surfaces as a PowerShell error' {
            Set-FakeKubectl -Arguments 'get', 'pod', 'nope' -ExitCode 1
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'Stop'
                { k get pod nope } | Should -Throw
            } finally {
                $global:ErrorActionPreference = $previous
            }
        }

        It 'a failing kubectl call keeps its exit code while surfacing the error' {
            Set-FakeKubectl -Arguments 'get', 'pod', 'nope' -ExitCode 3
            $previous = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                $null = k get pod nope
                $errorCount = $Error.Count
            } finally {
                $global:ErrorActionPreference = $previous
            }
            $LASTEXITCODE | Should -Be 3
            $errorCount | Should -BeGreaterThan 0 -Because 'the failure must also be reported as an error record'
        }
    }
}
