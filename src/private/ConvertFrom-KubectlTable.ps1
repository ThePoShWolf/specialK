function ConvertFrom-KubectlTable {
    <#
        Turns the text lines of a kubectl table into objects stamped with a format type name.
        Column starts come from the header: a column begins at a word that follows two or more spaces,
        because values can be empty in the data lines. Data lines shorter than the header are padded,
        never dropped, so a missing trailing value is an empty property.
        Columns listed in ConvertTo-KubectlValue become typed values that still print as kubectl printed them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$TypeName
    )
    $header = $Lines[0]
    $positions = @([regex]::Matches($header, '  \S') | ForEach-Object { $_.Index + 2 } | Sort-Object -Descending)
    $rows = foreach ($line in $Lines) {
        $line = $line.PadRight($header.Length)
        foreach ($position in $positions) {
            $line = $line.Insert($position, ';')
        }
        $line
    }
    $rows -replace ' +;', ';' | ForEach-Object { $_.Trim() } | ConvertFrom-Csv -Delimiter ';' | ForEach-Object {
        $_.PSObject.TypeNames.Insert(0, $TypeName)
        foreach ($property in $_.PSObject.Properties) {
            $property.Value = ConvertTo-KubectlValue -Text $property.Value -Column $property.Name
        }
        $_
    }
}
