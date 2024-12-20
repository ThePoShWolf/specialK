# https://kubernetes.io/docs/tasks/tools/included/optional-kubectl-configs-pwsh/
# but we are going to switch the completer to 'k' from 'kubectl'
Function Add-specialKAutoCompletion {
    [cmdletbinding()]
    param (
        [switch]$ToProfile
    )
    $toReplace = "-CommandName 'kubectl'"
    $argCompleter = (kubectl completion powershell) -replace $toReplace, "-CommandName 'k'"
    if ($argCompleter -like 'error*') {
        throw $argCompleter
    }

    if ($null -ne $argCompleter) {
        $argCompleter | Out-String | Invoke-Expression
    }

    if ($ToProfile.IsPresent) {
        $argCompleter | Out-File $PROFILE -Append
    }
}