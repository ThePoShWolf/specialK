function k {
    $skipArgs = @(
        'exec', 'cp', 'scale', 'rollout', 'delete', 'logs'
    )
    if ($skipArgs -contains $args[0]) {
        & kubectl $args
    } else {
        $out = (& kubectl $args)
        # if the output starts with the typical headers
        if ($out -and ($out[0] -match '^(NAME |NAMESPACE |CURRENT |LAST SEEN )') ) {
            # check for namespace
            $namespace = $out[0] -match '^NAMESPACE'

            # check for output
            $checkArgs = $args[2..$args.count]
            foreach ($arg in $checkArgs) {
                if ($arg -match '^--output=?(?<type>.*)?') {
                    $outputType = if ($Matches.type.length -gt 0) {
                        $Matches.type
                    } else {
                        $checkArgs[$checkArgs.IndexOf($arg) + 1]
                    }
                } elseif ($arg -match '^-o=?(?<type>.*)?') {
                    $outputType = if ($Matches.type.length -gt 0) {
                        $Matches.type
                    } else {
                        $checkArgs[$checkArgs.IndexOf($arg) + 1]
                    }
                }
            }

            # locate all positions to place semicolons
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
            $pluralCheck = $args[1]
            if ( $args[0] -eq 'get' ) { $pluralCheck = $pluralCheck -replace '(.*)s$', '$1' }
            if ($objectCommands[$args[0]] -contains $pluralCheck) {
                # select the format type name
                if ($namespace) {
                    $typeName = "$($args[0])-$($pluralCheck)-ns"
                } else {
                    $typeName = "$($args[0])-$($pluralCheck)"
                }
                if ($outputType -eq 'wide') {
                    $typeName = "$typeName-wide"
                }
                $out -replace ' +;', ';' | ForEach-Object { $_.Trim() } | ConvertFrom-Csv -Delimiter ';' | ForEach-Object { $_.PSObject.TypeNames.Insert(0, $typeName); $_ }
            } else {
                $out -replace ' +;', ';' | ForEach-Object { $_.Trim() } | ConvertFrom-Csv -Delimiter ';'
            }
        } else {
            $out
        }
    }
}