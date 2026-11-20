function Write-KubectlExitError {
    <#
        Reports a failed kubectl call as a PowerShell error. It is non-terminating, so `$?` is false and
        -ErrorAction Stop (or $ErrorActionPreference = 'Stop') in the caller turns it into an exception.
        $LASTEXITCODE is not touched. kubectl's own message already went to stderr.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ExitCode,
        [string[]]$Arguments
    )
    if ($null -eq $ExitCode -or $ExitCode -eq 0) { return }
    $message = "kubectl $($Arguments -join ' ') failed with exit code $ExitCode"
    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($message),
        'KubectlFailed',
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $Arguments
    )
    # No -ErrorAction here on purpose: a module function sees $ErrorActionPreference from the global
    # scope only, not from the caller's script or function scope. Set globally (as in a profile or an
    # interactive session) it turns this into a terminating error; a plain `k` call just reports it.
    Write-Error -ErrorRecord $record
}
