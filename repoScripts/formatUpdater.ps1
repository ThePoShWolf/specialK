param (
    [string]$OutPath
)

$baseTemplate = @"
<Configuration>
	<ViewDefinitions>
		<view></view>
	</ViewDefinitions>
</Configuration>
"@

$view = @"
        <View>
            <Name>{NAME}</Name>
            <ViewSelectedBy>
                <TypeName>{NAME}</TypeName>
            </ViewSelectedBy>
            <TableControl>
                <TableHeaders>
{HEADER}
                </TableHeaders>
                <TableRowEntries>
                    <TableRowEntry>
                        <TableColumnItems>
{COLUMNITEM}
                        </TableColumnItems>
                    </TableRowEntry>
                </TableRowEntries>
            </TableControl>
        </View>
"@

$tcHeader = @"
<TableColumnHeader><Label>{HEADER}</Label></TableColumnHeader>
"@

$tcItem = @"
<TableColumnItem><PropertyName>{COLUMNITEM}</PropertyName></TableColumnItem>
"@

$commands = @{
    get    = @(
        'pod', 'deployment', 'node'
    )
    top    = @(
        'pod', 'node'
    )
    config = @(
        'get-contexts'
    )
}
$addViews = foreach ($command in $commands.Keys) {
    foreach ($sub in $commands[$command]) {
        $newView = $view -replace '\{NAME\}', "$command-$sub"
        $props = (k $command $sub)[0].psobject.properties.name
        $headers = foreach ($header in $props) {
            $tcHeader -replace '\{HEADER\}', $header
        }
        $tcItems = foreach ($tci in $props) {
            $tcItem -replace '\{COLUMNITEM\}', $tci
        }
        $newView -replace '\{HEADER\}', ($headers -join "`n") -replace '\{COLUMNITEM\}', ($tcItems -join "`n")
    }
}

$baseTemplate -replace [regex]::Escape('<view></view>'), ($addViews -join "`n") | Out-File $OutPath -Force