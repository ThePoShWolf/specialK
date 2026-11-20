# repoScripts/Get-ReleaseInfo.ps1 reads the version from the manifest and a version's notes from the changelog. Offline.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:script = Join-Path $script:RepoRoot 'repoScripts' 'Get-ReleaseInfo.ps1'
    $script:work = Join-Path ([System.IO.Path]::GetTempPath()) "specialK-release-test-$([guid]::NewGuid().ToString('N'))"
    New-Item $script:work -ItemType Directory | Out-Null

    $script:manifest = Join-Path $script:work 'm.psd1'
    Set-Content $script:manifest "@{ ModuleVersion = '1.2.3' }"
    $script:changelog = Join-Path $script:work 'CHANGELOG.md'
    # CRLF on purpose: the repo's text files are CRLF
    $text = "# Changelog`r`n`r`n## 1.2.3`r`n`r`n- newest thing`r`n- another`r`n`r`n## 1.2.2`r`n`r`n- older`r`n`r`n## ChangeLog`r`n`r`n### 1.0.0`r`n`r`n- first`r`n`r`n### 0.9.0`r`n`r`n- before`r`n"
    [System.IO.File]::WriteAllText($script:changelog, $text)
}

AfterAll {
    Remove-Item $script:work -Recurse -Force -ErrorAction Ignore
}

Describe 'Get-ReleaseInfo' {
    It 'reads the version from the manifest and builds the tag' {
        $info = & $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog
        $info.Version | Should -Be '1.2.3'
        $info.Tag | Should -Be 'v1.2.3'
    }

    It 'extracts only the requested section, without its heading' {
        $info = & $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog
        $info.HasChangelogSection | Should -BeTrue
        $info.Notes | Should -Be "- newest thing`n- another"
    }

    It 'stops a ### section at the next ### heading and takes older-style headings' {
        (& $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog -Version 1.0.0 -NotesOnly) | Should -Be '- first'
    }

    It 'reports a missing section instead of guessing' {
        $info = & $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog -Version 9.9.9
        $info.HasChangelogSection | Should -BeFalse
        $info.Notes | Should -BeNullOrEmpty
    }

    It 'does not match a version that is only a prefix of another' {
        (& $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog -Version 1.2.30).HasChangelogSection | Should -BeFalse
    }

    It 'throws with -NotesOnly when there is no section' {
        { & $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog -Version 9.9.9 -NotesOnly } | Should -Throw '*no section*9.9.9*'
    }

    It 'treats a missing changelog as having no section' {
        (& $script:script -ManifestPath $script:manifest -ChangelogPath (Join-Path $script:work 'nope.md')).HasChangelogSection | Should -BeFalse
    }

    It 'rejects a version that is not MAJOR.MINOR.PATCH' {
        { & $script:script -ManifestPath $script:manifest -ChangelogPath $script:changelog -Version 1.2 } | Should -Throw '*MAJOR.MINOR.PATCH*'
    }

    It 'reads the real manifest' {
        $info = & $script:script
        $info.Version | Should -Be (Import-PowerShellDataFile (Join-Path $script:RepoRoot 'src' 'specialK.psd1')).ModuleVersion
    }
}
