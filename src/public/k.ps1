function k {
    # Behaves like kubectl for everything except the commands listed in formats.json, and only when
    # the output is the default table or -o wide. Those are captured and turned into objects; anything
    # else (watching, -o yaml, exec, edit, unknown verbs) goes straight to kubectl with nothing captured,
    # so it streams and keeps the terminal.
    $info = Get-KubectlArgumentInfo -Arguments $args
    $resource = $null
    if ($info.Verb) {
        $resource = ConvertTo-KubectlResourceName -Name ($info.Positionals | Select-Object -First 1)
    }
    $convert = $resource -and
        ($objectCommands[$info.Verb] -contains $resource) -and
        -not $info.Watch -and
        -not $info.NoHeaders -and
        ($null -eq $info.Output -or $info.Output -ceq 'wide')

    if (-not $convert) {
        & kubectl @args
        Write-KubectlExitError -ExitCode $LASTEXITCODE -Arguments $args
        return
    }

    $out = & kubectl @args
    $exitCode = $LASTEXITCODE
    # kubectl's default tables start with one of these headers
    if ($exitCode -eq 0 -and $out -and ($out[0] -match '^(NAME( |$)|NAMESPACE |CURRENT |LAST SEEN )')) {
        $typeName = "$($info.Verb)-$resource"
        if ($out[0] -match '^NAMESPACE ') { $typeName += '-ns' }
        if ($info.Output -ceq 'wide') { $typeName += '-wide' }
        ConvertFrom-KubectlTable -Lines @($out) -TypeName $typeName
    } else {
        $out
    }
    Write-KubectlExitError -ExitCode $exitCode -Arguments $args
}
