function k {
    $objectCommands = @('top', 'get')
    if ($objectCommands -contains $args[0] -and $args[1] -ne '--help') {
        $typeName = "$($args[0])-$($args[1])"
        (& kubectl $args) -replace '  +', ',' | ForEach-Object { $_.trim(',') } | ConvertFrom-Csv | ForEach-Object { $_.PSObject.TypeNames.Insert(0, $typeName); $_ }
    } else {
        & kubectl $args
    }
}