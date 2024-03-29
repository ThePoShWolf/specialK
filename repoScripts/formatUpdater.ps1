param (
    [string]$OutPath
)

$commands = Get-Content $PSScriptRoot\..\src\formats.json | ConvertFrom-Json -AsHashtable

# Creating the views
$addViews = foreach ($command in $commands.Keys) {
    Write-Host $command
    # Foreach command in the formats.json
    foreach ($sub in $commands[$command]) {
        Write-Host "- $sub"
        # get the output of the command and subcommand
        $out = (k $command $sub)
        if ($null -ne $out) {
            $props = $out[0].psobject.properties.name
        } else {
            Write-Warning "Unable to generate format for 'kubectl $command $sub'. No objects were returned to examine."
            break
        }

        # create the view
        '        <View>'
        '            <Name>{0}</Name>' -f "$command-$sub"
        '            <ViewSelectedBy>'
        '                <TypeName>{0}</TypeName>' -f "$command-$sub"
        '            </ViewSelectedBy>'
        '            <TableControl>'
        '                <TableHeaders>'
        # create the headers
        foreach ($header in $props) {
            '                    <TableColumnHeader><Label>{0}</Label></TableColumnHeader>' -f $header
        }
        '                </TableHeaders>'
        '                <TableRowEntries>'
        '                    <TableRowEntry>'
        '                        <TableColumnItems>'
        # create the column items
        foreach ($tci in $props) {
            '                            <TableColumnItem><PropertyName>{0}</PropertyName></TableColumnItem>' -f $tci
        }
        '                        </TableColumnItems>'
        '                    </TableRowEntry>'
        '                </TableRowEntries>'
        '            </TableControl>'
        '        </View>'
    }
}

@(
    '<Configuration>'
    '    <ViewDefinitions>'
    $addViews
    '    </ViewDefinitions>'
    '</Configuration>'
) | Out-File $OutPath -Force