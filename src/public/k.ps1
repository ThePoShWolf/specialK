function k {
    if ($objectCommands.Keys -contains $args[0] -and $args[1] -ne '--help' -and $args.Count -eq 2) {
        if ($objectCommands[$args[0]] -contains $args[1]) {
            # select the format type name
            $typeName = "$($args[0])-$($args[1])"

            # get the output
            $out = (& kubectl $args)

            # locate all positions to place commas
            # we are using the headers since some values may be null in the data
            if ($null -ne $out) {
                $m = $out[0] | Select-String -Pattern '  \S' -AllMatches
            }

            # place semicolons
            $out = foreach ($line in $out) {
                foreach ($index in ($m.Matches.Index | Sort-Object -Descending)) {
                    $line = $line.Insert($index + 2, ';')
                }
                $line
            }

            # convert from csv (since we added commas)
            $out -replace ' +;', ';' | ForEach-Object { $_.Trim() } | ConvertFrom-Csv -Delimiter ';' | ForEach-Object { $_.PSObject.TypeNames.Insert(0, $typeName); $_ }
            return
        }
    }
    & kubectl $args
}