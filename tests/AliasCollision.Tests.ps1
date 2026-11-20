# Importing the module warns when an alias named k would hide the k function. Offline.

Describe 'alias collision on import' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    AfterEach {
        Remove-SpecialKSource
        Remove-Item Alias:\k -Force -ErrorAction Ignore
    }

    It 'warns once when k is aliased to kubectl' {
        Set-Alias -Name k -Value kubectl -Scope Global
        $warnings = @(Import-SpecialKSource 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -Be 1
        $warnings[0].Message | Should -Match "alias 'k'"
        $warnings[0].Message | Should -Match 'Remove-Item Alias:k'
    }

    It 'does not warn when there is no alias' {
        Remove-Item Alias:\k -Force -ErrorAction Ignore
        $warnings = @(Import-SpecialKSource 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -Be 0
    }
}
