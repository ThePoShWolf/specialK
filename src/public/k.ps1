function k {
    if ($objectCommands.Keys -contains $args[0] -and $args[1] -ne '--help') {
        if ($objectCommands[$args[0]] -contains $args[1]) {
            $typeName = "$($args[0])-$($args[1])"
            # Convert the output to CSV by replacing multiple spaces with a comma
            # then add a type name to use the formatter
            (& kubectl $args) -replace '  +', ',' | ForEach-Object { $_.trim(',') } | ConvertFrom-Csv | ForEach-Object { $_.PSObject.TypeNames.Insert(0, $typeName); $_ }
            return
        }
    }
    & kubectl $args
}