<#
.SYNOPSIS
    Creates (or reuses) a local kind cluster named specialk with metrics-server, for the smoke tests.
.DESCRIPTION
    Needs docker, kind and kubectl on PATH (the devcontainer has all three). Re-running it reuses an existing
    cluster and only makes sure its kubectl context is selected and metrics-server is installed.
    Run the smoke tests afterwards with: Invoke-Build ModuleBuild, SmokeTest
#>
[CmdletBinding()]
param (
    [string]$Name = 'specialk',
    # Same version CI installs
    [string]$MetricsServerVersion = 'v0.7.2'
)
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param([Parameter(Mandatory)][string]$Description, [Parameter(Mandatory)][scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE." }
}

foreach ($tool in 'docker', 'kind', 'kubectl') {
    if (-not (Get-Command $tool -ErrorAction Ignore)) { throw "'$tool' was not found on PATH." }
}

$existing = @(kind get clusters 2>$null)
if ($existing -contains $Name) {
    Write-Output "kind cluster '$Name' already exists; reusing it."
    Invoke-Native "Selecting the kind-$Name context" { kind export kubeconfig --name $Name }
} else {
    Invoke-Native "Creating kind cluster '$Name'" { kind create cluster --name $Name }
}

$context = "kind-$Name"
$manifestUrl = "https://github.com/kubernetes-sigs/metrics-server/releases/download/$MetricsServerVersion/components.yaml"
Invoke-Native 'Installing metrics-server' {
    kubectl --context $context apply -f $manifestUrl
}
# kind's kubelets use self-signed certificates; add the flag only once
$deployment = kubectl --context $context get deployment metrics-server -n kube-system -o json | ConvertFrom-Json
if ($deployment.spec.template.spec.containers[0].args -notcontains '--kubelet-insecure-tls') {
    Invoke-Native 'Patching metrics-server with --kubelet-insecure-tls' {
        kubectl --context $context patch deployment metrics-server -n kube-system --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
    }
}
Invoke-Native 'Waiting for metrics-server' {
    kubectl --context $context rollout status deployment/metrics-server -n kube-system --timeout=180s
}
Write-Output "Cluster '$Name' is ready (context $context). Metrics can take a minute to appear for 'k top'."
