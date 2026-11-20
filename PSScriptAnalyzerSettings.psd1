# PSScriptAnalyzer settings for specialK. Used by repoScripts/Invoke-Lint.ps1 (and so by CI).
# CI fails on Error and Warning; Information findings are not reported.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # repoScripts/*.ps1 and the build script are command-line tools whose progress output is meant for the console.
        'PSAvoidUsingWriteHost'
    )
}
