# Add-specialKAutoCompletion with a fake kubectl and a temp profile. No cluster, no network.

Describe 'Add-specialKAutoCompletion, offline' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        Enable-RealKubectlTripwire
        $module = Import-SpecialKSource
        Install-FakeKubectl -Module $module
        $script:completer = "Register-ArgumentCompleter -CommandName 'kubectl' -ScriptBlock { 'x' }"
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "specialK-profile-$([guid]::NewGuid().ToString('N'))"
        New-Item $script:tempDir -ItemType Directory | Out-Null
        $script:marker = '# >>> specialK completion >>>'
    }

    AfterAll {
        Remove-FakeKubectl
        Remove-SpecialKSource
        Disable-RealKubectlTripwire
        Remove-Item $script:tempDir -Recurse -Force -ErrorAction Ignore
    }

    BeforeEach {
        Reset-FakeKubectl
        Set-FakeKubectl -Arguments 'completion', 'powershell' -Text $script:completer
        $script:profilePath = Join-Path $script:tempDir "$([guid]::NewGuid().ToString('N'))/profile.ps1"
    }

    AfterEach {
        Assert-RealKubectlNotCalled
    }

    It 'creates a missing profile and its folder with one marked block' {
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath
        $text = Get-Content $script:profilePath -Raw
        ([regex]::Matches($text, [regex]::Escape($script:marker))).Count | Should -Be 1
        $text | Should -Match 'Get-Command kubectl'
        $text | Should -Match 'Add-specialKAutoCompletion'
        $text | Should -Match '# <<< specialK completion <<<'
        $text | Should -Not -Match 'Register-ArgumentCompleter'
    }

    It 'is idempotent: a second run changes nothing' {
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath
        $first = Get-Content $script:profilePath -Raw
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath
        Get-Content $script:profilePath -Raw | Should -BeExactly $first
    }

    It 'keeps existing profile content and appends the block' {
        New-Item (Split-Path $script:profilePath) -ItemType Directory | Out-Null
        Set-Content $script:profilePath 'Set-Alias ll Get-ChildItem' -NoNewline
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath
        $lines = Get-Content $script:profilePath
        $lines[0] | Should -BeExactly 'Set-Alias ll Get-ChildItem'
        $lines | Should -Contain $script:marker
    }

    It 'writes nothing with -WhatIf' {
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath -WhatIf
        Test-Path $script:profilePath | Should -BeFalse
        Test-Path (Split-Path $script:profilePath) | Should -BeFalse
    }

    It 'warns about an old static snapshot and leaves it untouched' {
        New-Item (Split-Path $script:profilePath) -ItemType Directory | Out-Null
        $old = "$script:completer".Replace("'kubectl'", "'k'")
        Set-Content $script:profilePath $old
        $warnings = @()
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 1
        $warnings[0].Message | Should -Match 'static copy'
        (Get-Content $script:profilePath -Raw) | Should -Match ([regex]::Escape($old))
    }

    It 'does not warn when there is no old snapshot' {
        $warnings = @()
        Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 0
    }

    It 'does not touch any profile without -ToProfile' {
        Add-specialKAutoCompletion -ProfilePath $script:profilePath
        Test-Path $script:profilePath | Should -BeFalse
    }

    It 'throws when kubectl prints an error' {
        Set-FakeKubectl -Arguments 'completion', 'powershell' -Text 'error: unknown command'
        { Add-specialKAutoCompletion -ToProfile -ProfilePath $script:profilePath } | Should -Throw '*error*'
        Test-Path $script:profilePath | Should -BeFalse
    }
}
