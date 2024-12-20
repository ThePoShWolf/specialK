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
            $namespace = if ($out[0] -match '^NAME ') {
                'name'
            } elseif ($out[0] -match '^NAMESPACE') {
                'namespace'
            } else {
                'none'
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
                if ($namespace -eq 'name') {
                    $typeName = "$($args[0])-$($pluralCheck)-name"
                } elseif ($namespace -eq 'namespace') {
                    $typeName = "$($args[0])-$($pluralCheck)-ns"
                } else {
                    $typeName = "$($args[0])-$($pluralCheck)"
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