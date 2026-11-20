<#
    Smoke test: the BUILT specialK module calling the REAL kubectl against a REAL cluster (kind in CI).
    Never part of `Invoke-Build Test` (tagged Smoke); run it with `Invoke-Build ModuleBuild, SmokeTest`.

    Needs: kubectl on PATH, a current kube context that may create and delete a namespace, and (for the `top`
    cases) a working Metrics API. The suite creates its own namespace with a small deployment and service and
    deletes it afterwards; it touches nothing else.

    Environment knobs:
      SPECIALK_SMOKE_MODULE            folder of the built module (default: <repo>/build/specialK)
      SPECIALK_SMOKE_READY_TIMEOUT     seconds to wait for the sample deployment to roll out (default 180)
      SPECIALK_SMOKE_METRICS_TIMEOUT   seconds to wait for pod metrics to appear (default 120)
#>

BeforeDiscovery {
    # <verb>-<resource>[-ns][-wide]: -ns when -A is given, -wide with -o wide. $ns is filled in at run time.
    $script:typedCases = @(
        @{ Command = 'get pod';                    Kargs = @('get', 'pod', '-n', '{ns}');                 Type = 'get-pod' }
        @{ Command = 'get pod -A';                 Kargs = @('get', 'pod', '-A');                         Type = 'get-pod-ns' }
        @{ Command = 'get pod -o wide';            Kargs = @('get', 'pod', '-n', '{ns}', '-o', 'wide');   Type = 'get-pod-wide' }
        @{ Command = 'get pod -A -o wide';         Kargs = @('get', 'pod', '-A', '-o', 'wide');           Type = 'get-pod-ns-wide' }
        @{ Command = 'get deployment';             Kargs = @('get', 'deployment', '-n', '{ns}');          Type = 'get-deployment' }
        @{ Command = 'get deployment -A';          Kargs = @('get', 'deployment', '-A');                  Type = 'get-deployment-ns' }
        @{ Command = 'get deployment -o wide';     Kargs = @('get', 'deployment', '-n', '{ns}', '-o', 'wide'); Type = 'get-deployment-wide' }
        @{ Command = 'get deployment -A -o wide';  Kargs = @('get', 'deployment', '-A', '-o', 'wide');   Type = 'get-deployment-ns-wide' }
        @{ Command = 'get service';                Kargs = @('get', 'service', '-n', '{ns}');             Type = 'get-service' }
        @{ Command = 'get service -A';             Kargs = @('get', 'service', '-A');                     Type = 'get-service-ns' }
        @{ Command = 'get service -o wide';        Kargs = @('get', 'service', '-n', '{ns}', '-o', 'wide'); Type = 'get-service-wide' }
        @{ Command = 'get service -A -o wide';     Kargs = @('get', 'service', '-A', '-o', 'wide');       Type = 'get-service-ns-wide' }
        @{ Command = 'get events';                 Kargs = @('get', 'events', '-n', '{ns}');              Type = 'get-events' }
        @{ Command = 'get events -A';              Kargs = @('get', 'events', '-A');                      Type = 'get-events-ns' }
        @{ Command = 'get events -o wide';         Kargs = @('get', 'events', '-n', '{ns}', '-o', 'wide'); Type = 'get-events-wide' }
        @{ Command = 'get events -A -o wide';      Kargs = @('get', 'events', '-A', '-o', 'wide');        Type = 'get-events-ns-wide' }
        @{ Command = 'get namespace';              Kargs = @('get', 'namespace');                         Type = 'get-namespace' }
        @{ Command = 'get namespace -o wide';      Kargs = @('get', 'namespace', '-o', 'wide');           Type = 'get-namespace-wide' }
        @{ Command = 'get node';                   Kargs = @('get', 'node');                              Type = 'get-node' }
        @{ Command = 'get node -o wide';           Kargs = @('get', 'node', '-o', 'wide');                Type = 'get-node-wide' }
        @{ Command = 'config get-contexts';        Kargs = @('config', 'get-contexts');                   Type = 'config-get-contexts' }
        @{ Command = 'config get-clusters';        Kargs = @('config', 'get-clusters');                   Type = 'config-get-clusters' }
        @{ Command = 'config get-users';           Kargs = @('config', 'get-users');                      Type = 'config-get-users' }
    )
    # need the Metrics API (metrics-server) and running pods
    $script:topCases = @(
        @{ Command = 'top pod';    Kargs = @('top', 'pod', '-n', '{ns}'); Type = 'top-pod' }
        @{ Command = 'top pod -A'; Kargs = @('top', 'pod', '-A');         Type = 'top-pod-ns' }
        @{ Command = 'top node';   Kargs = @('top', 'node');              Type = 'top-node' }
    )
    $script:aliasCases = @(
        @{ Command = 'get po';      Kargs = @('get', 'po', '-n', '{ns}');            Type = 'get-pod' }
        @{ Command = 'get deploy';  Kargs = @('get', 'deploy', '-n', '{ns}');        Type = 'get-deployment' }
        @{ Command = 'get svc';     Kargs = @('get', 'svc', '-n', '{ns}');           Type = 'get-service' }
        @{ Command = 'get ns';      Kargs = @('get', 'ns');                          Type = 'get-namespace' }
        @{ Command = 'get no';      Kargs = @('get', 'no');                          Type = 'get-node' }
        @{ Command = 'get ev';      Kargs = @('get', 'ev', '-n', '{ns}');            Type = 'get-events' }
        @{ Command = '-n <ns> get po';              Kargs = @('-n', '{ns}', 'get', 'po');                 Type = 'get-pod' }
        @{ Command = '--namespace=<ns> get pods';   Kargs = @('--namespace={ns}', 'get', 'pods');         Type = 'get-pod' }
        @{ Command = '-n <ns> get po -o wide';      Kargs = @('-n', '{ns}', 'get', 'po', '-o', 'wide');   Type = 'get-pod-wide' }
        @{ Command = 'get -n <ns> po';              Kargs = @('get', '-n', '{ns}', 'po');                 Type = 'get-pod' }
    )
}

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $modulePath = $env:SPECIALK_SMOKE_MODULE
    if (-not $modulePath) { $modulePath = Join-Path $script:repoRoot 'build' 'specialK' }
    if (-not (Test-Path (Join-Path $modulePath 'specialK.psd1'))) {
        throw "No built module at '$modulePath'. Run 'Invoke-Build ModuleBuild' first."
    }
    if (-not (Get-Command kubectl -CommandType Application -ErrorAction Ignore)) {
        throw 'kubectl was not found on PATH.'
    }
    Remove-Module specialK -ErrorAction Ignore
    Import-Module (Join-Path $modulePath 'specialK.psd1') -Force

    function Get-EnvSeconds {
        param([string]$Name, [int]$Default)
        $value = [Environment]::GetEnvironmentVariable($Name)
        if ($value -match '^\d+$') { [int]$value } else { $Default }
    }
    # Expands the {ns} placeholder in a data-driven argument list.
    function Expand-Arguments {
        param([string[]]$Arguments)
        $Arguments | ForEach-Object { $_.Replace('{ns}', $script:ns) }
    }

    $script:ns = 'specialk-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    Write-Host "Smoke namespace: $script:ns (context: $(& kubectl config current-context))"

    & kubectl create namespace $script:ns | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create namespace $script:ns" }
    # pause needs no registry credentials beyond registry.k8s.io and has no ports or probes, so it is Ready as soon as it runs
    & kubectl create deployment smoke-web -n $script:ns --image=registry.k8s.io/pause:3.10 --replicas=2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the sample deployment' }
    & kubectl expose deployment smoke-web -n $script:ns --port=80 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the sample service' }

    # Wait (bounded) for the workload and for pod metrics. These do not throw: the tests that depend on them say so.
    $readyTimeout = Get-EnvSeconds 'SPECIALK_SMOKE_READY_TIMEOUT' 180
    & kubectl rollout status deployment/smoke-web -n $script:ns "--timeout=${readyTimeout}s" | Out-Host
    $script:workloadReady = ($LASTEXITCODE -eq 0)

    $script:metricsReady = $false
    if ($script:workloadReady) {
        $deadline = (Get-Date).AddSeconds((Get-EnvSeconds 'SPECIALK_SMOKE_METRICS_TIMEOUT' 120))
        do {
            $null = & kubectl top pod -n $script:ns --no-headers 2>&1
            if ($LASTEXITCODE -eq 0) { $script:metricsReady = $true; break }
            Start-Sleep -Seconds 3
        } while ((Get-Date) -lt $deadline)
    }
    Write-Host "Workload ready: $script:workloadReady, pod metrics ready: $script:metricsReady"
}

AfterAll {
    if ($script:ns) {
        & kubectl delete namespace $script:ns --wait=false --ignore-not-found | Out-Null
    }
    Remove-Module specialK -ErrorAction Ignore
}

Describe 'k against a real cluster' -Tag 'Smoke' {
    Context 'sample workload' {
        It 'the sample deployment rolls out' {
            $script:workloadReady | Should -BeTrue -Because 'the pods in the smoke namespace must reach Ready'
        }

        It 'every sample pod is Running and Ready' {
            $pods = @(k get pod -n $script:ns)
            $pods.Count | Should -Be 2
            $pods | ForEach-Object {
                $_.STATUS | Should -Be 'Running'
                $_.READY | Should -Be '1/1'
            }
        }
    }

    Context 'objectified commands' {
        It 'k <Command> returns <Type> objects' -ForEach $script:typedCases {
            $kubectlArgs = @(Expand-Arguments $Kargs)
            $result = @(k @kubectlArgs)
            $result.Count | Should -BeGreaterThan 0
            $result | ForEach-Object {
                $_ | Should -Not -BeOfType [string]
                $_.PSObject.TypeNames[0] | Should -Be $Type
                $_.PSObject.Properties.Name | Should -Contain 'NAME'
            }
            if ($Type -like '*-ns*' -and $Type -notlike 'config-*') {
                $result[0].PSObject.Properties.Name | Should -Contain 'NAMESPACE'
            }
        }

        It 'finds the sample objects by name' {
            (k get deployment -n $script:ns).NAME | Should -Contain 'smoke-web'
            (k get service -n $script:ns).NAME | Should -Contain 'smoke-web'
            (k get namespace).NAME | Should -Contain $script:ns
            (k get pod -A | Where-Object NAMESPACE -eq $script:ns).Count | Should -Be 2
        }

        It 'k <Command> returns <Type> objects (needs the Metrics API)' -ForEach $script:topCases {
            $script:metricsReady | Should -BeTrue -Because 'metrics-server must be serving pod metrics'
            $kubectlArgs = @(Expand-Arguments $Kargs)
            $result = @(k @kubectlArgs)
            $result.Count | Should -BeGreaterThan 0
            $result | ForEach-Object {
                $_ | Should -Not -BeOfType [string]
                $_.PSObject.TypeNames[0] | Should -Be $Type
            }
        }
    }

    Context 'short names and flag position' {
        It 'k <Command> is detected as <Type>' -ForEach $script:aliasCases {
            $kubectlArgs = @(Expand-Arguments $Kargs)
            $result = @(k @kubectlArgs)
            $result.Count | Should -BeGreaterThan 0
            $result | ForEach-Object {
                $_ | Should -Not -BeOfType [string]
                $_.PSObject.TypeNames[0] | Should -Be $Type
            }
        }
    }

    Context 'pass-through' {
        It 'unsupported get (configmap) returns kubectl''s raw text lines' {
            $result = @(k get configmap -n kube-system)
            $result.Count | Should -BeGreaterThan 1
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
            $result[0] | Should -Match '^NAME\s'
        }

        It 'unsupported output format (-o yaml) returns raw text lines' {
            $result = @(k get pod -n $script:ns -o yaml)
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
            ($result -join "`n") | Should -Match 'kind: List'
        }

        It 'a streaming command (get pods -w) returns on its own and emits the table' {
            $started = Get-Date
            $lines = @(k get pod -n $script:ns -w --request-timeout=5s 2>&1)
            ((Get-Date) - $started).TotalSeconds | Should -BeLessThan 60
            ($lines | Out-String) | Should -Match 'NAME'
            ($lines | Out-String) | Should -Match 'smoke-web'
        }
    }

    Context 'errors' {
        It 'a failing command writes a PowerShell error and keeps a non-zero exit code' {
            $previous = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'SilentlyContinue'
                $Error.Clear()
                $null = k get nosuchthing
                $errorCount = $Error.Count
                $exitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $previous
            }
            $exitCode | Should -Not -Be 0
            $errorCount | Should -BeGreaterThan 0
        }

        It 'a failing command throws under ErrorActionPreference Stop' {
            $previous = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Stop'
                { k get nosuchthing } | Should -Throw
            } finally {
                $ErrorActionPreference = $previous
            }
        }
    }
}
