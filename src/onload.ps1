<#
    Code in this file will be added to the end of the .psm1. For example,
    you should set variables or other environment settings here.
#>
$script:objectCommands = Get-Content $PSScriptRoot\formats.json | ConvertFrom-Json -AsHashtable

# An alias beats a function in PowerShell's command resolution, so an existing alias named k hides the k function.
$existingAlias = Get-Alias -Name k -ErrorAction Ignore
if ($existingAlias -and $existingAlias.Definition -ne 'k') {
    Write-Warning "An alias 'k' for '$($existingAlias.Definition)' exists, and PowerShell prefers aliases over functions, so typing k runs '$($existingAlias.Definition)' and not specialK's k. Remove the alias to use specialK: Remove-Item Alias:k (and delete the Set-Alias line from your profile)."
}
Remove-Variable existingAlias
