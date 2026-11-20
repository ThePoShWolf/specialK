function Write-KubectlExitError {
    <#
        Reports a failed kubectl call as a PowerShell error. It is non-terminating: it lands in $Error and
        on the error stream, and $ErrorActionPreference = 'Stop' turns it into an exception. $LASTEXITCODE is
        not touched, and is the reliable failure signal: `$?` stays true after any script function returns,
        whatever it wrote to the error stream. kubectl's own message already went to stderr.
        The message and TargetObject name only the verb and the first positional after it, never the whole
        argument list, which can hold --token, --password or --from-literal values.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ExitCode,
        [string[]]$Arguments
    )
    if ($null -eq $ExitCode -or $ExitCode -eq 0) { return }
    $info = Get-KubectlArgumentInfo -Arguments $Arguments
    $what = @($info.Verb, ($info.Positionals | Select-Object -First 1)) | Where-Object { $_ }
    $target = (@('kubectl') + $what) -join ' '
    $message = "$target failed with exit code $ExitCode"
    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($message),
        'KubectlFailed',
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $target
    )
    # No -ErrorAction here on purpose: a module function sees $ErrorActionPreference from the global
    # scope only, not from the caller's script or function scope. Set globally (as in a profile or an
    # interactive session) it turns this into a terminating error; a plain `k` call just reports it.
    Write-Error -ErrorRecord $record
}
