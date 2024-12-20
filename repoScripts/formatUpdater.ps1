param (
    [string]$OutPath
)

Write-Host $OutPath

Function New-FormatView {
    param(
        [string]$name,
        [string[]]$props
    )
    # create the view
    '        <View>'
    '            <Name>{0}</Name>' -f "$name"
    '            <ViewSelectedBy>'
    '                <TypeName>{0}</TypeName>' -f "$name"
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

        $name = "$command-$sub"

        # generate plain format:
        New-FormatView -name $name -props $props

        # generate format with namespace:
        New-FormatView -name "$name-ns" -props ($props + 'NAMESPACE')

        Write-Host "  - wide"
        # get the output of the command and subcommand
        $out = (k $command $sub '-o' 'wide')
        if ($null -ne $out) {
            $props = $out[0].psobject.properties.name
        } else {
            Write-Warning "Unable to generate format for 'kubectl $command $sub -o wide'. No objects were returned to examine."
            break
        }

        # generate plain format with wide:
        New-FormatView -name "$name-wide" -props ($props)

        # generate formate with namespace and wide:
        New-FormatView -name "$name-ns-wide" -props ($props + 'NAMESPACE')
    }
}

@(
    '<Configuration>'
    '    <ViewDefinitions>'
    $addViews
    '    </ViewDefinitions>'
    '</Configuration>'
) | Out-File $OutPath -Force -Encoding utf8