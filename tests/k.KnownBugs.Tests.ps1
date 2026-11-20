# Each test states the behavior `k` SHOULD have and fails today. They pin the findings in the review so
# the fixing phase can turn them green. Run without them: Invoke-Build Test -ExcludeTag KnownBug

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

Describe 'k, known bugs' -Tag 'KnownBug' {
    BeforeEach {
        Reset-FakeKubectl
        Register-ManifestFixtures
    }
    AfterEach {
        Assert-RealKubectlNotCalled
    }

    Context 'finding 2: unsupported commands pass through unchanged' {
        It 'k <Command> returns kubectl''s raw lines, not objects' -ForEach @(
            @{ Command = 'get secrets -A'; Kargs = @('get', 'secrets', '-A'); Fixture = 'get-secrets-ns' }
            @{ Command = 'get configmap -n kube-system'; Kargs = @('get', 'configmap', '-n', 'kube-system'); Fixture = 'get-configmap' }
            @{ Command = 'get pods -w'; Kargs = @('get', 'pods', '-w'); Fixture = 'get-pod' }
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
        ) {
            Set-FakeKubectl -Arguments $Kargs -Text "first`nsecond"
            k @Kargs | ForEach-Object { Add-FakeKubectlEvent "consumer: $_" }
            $events = Get-FakeKubectlEvents
            $events[0] | Should -Be 'consumer: first' -Because 'k captured the output instead of passing it straight through'
        }
    }

    Context 'finding 3: type names' {
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

    Context 'finding 3: global flags and flag position' {
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

    Context 'robustness' {
        It 'a data line shorter than a header position does not throw' {
            $text = "NAME   READY   STATUS    RESTARTS   AGE`nweb    1/1`n"
            Set-FakeKubectl -Arguments 'get', 'pod' -Text $text
            $previous = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Stop'
                $result = @(k get pod)
            } finally {
                $ErrorActionPreference = $previous
            }
            $result.Count | Should -Be 1
            $result[0].NAME | Should -Be 'web'
            $result[0].READY | Should -Be '1/1'
        }

        It 'a failing kubectl call (non-zero exit code) surfaces as a PowerShell error' {
            Set-FakeKubectl -Arguments 'get', 'pod', 'nope' -ExitCode 1
            $previous = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Stop'
                { k get pod nope } | Should -Throw
            } finally {
                $ErrorActionPreference = $previous
            }
        }

        It 'a failing kubectl call keeps its exit code while surfacing the error' {
            Set-FakeKubectl -Arguments 'get', 'pod', 'nope' -ExitCode 3
            $previous = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                $null = k get pod nope
                $errorCount = $Error.Count
            } finally {
                $ErrorActionPreference = $previous
            }
            $LASTEXITCODE | Should -Be 3
            $errorCount | Should -BeGreaterThan 0 -Because 'the failure must also be reported as an error record'
        }
    }
}
