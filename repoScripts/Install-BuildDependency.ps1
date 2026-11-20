<#
.SYNOPSIS
    Installs the PowerShell modules the build, tests and lint need, from the PowerShell Gallery. Used by CI.
.DESCRIPTION
    Uses PSResourceGet (ships with PowerShell 7.4+, on every GitHub-hosted runner). Modules that are already
    installed in the pinned range are skipped, so a restored module cache makes this a no-op.
    Version ranges are NuGet style: '[5.6.0,6.0.0)' means 5.6.0 up to, but not including, 6.0.0.
    Pester stays on 5.x on purpose: Pester 6 is a different major version and may break the suite.
#>
[CmdletBinding()]
param (
    [ValidateSet('InvokeBuild', 'Pester', 'PSScriptAnalyzer')]
    [string[]]$Name = @('InvokeBuild', 'Pester', 'PSScriptAnalyzer')
)
$ErrorActionPreference = 'Stop'

# module name -> install range (NuGet syntax) and the minimum/maximum for the "already installed?" check
$pins = @{
    InvokeBuild      = @{ Range = '[5.11.0,6.0.0)'; Min = [version]'5.11.0'; Max = [version]'6.0.0' }
    Pester           = @{ Range = '[5.6.0,6.0.0)'; Min = [version]'5.6.0'; Max = [version]'6.0.0' }
    PSScriptAnalyzer = @{ Range = '[1.22.0,2.0.0)'; Min = [version]'1.22.0'; Max = [version]'2.0.0' }
}

foreach ($module in $Name) {
    $pin = $pins[$module]
    $installed = Get-Module $module -ListAvailable |
        Where-Object { $_.Version -ge $pin.Min -and $_.Version -lt $pin.Max } |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($installed) {
        Write-Output "$module $($installed.Version) is already installed."
        continue
    }
    Write-Output "Installing $module $($pin.Range) from the PowerShell Gallery"
    Install-PSResource -Name $module -Version $pin.Range -Repository PSGallery -Scope CurrentUser -TrustRepository -Quiet
    $installed = Get-Module $module -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    Write-Output "$module $($installed.Version) installed."
}
