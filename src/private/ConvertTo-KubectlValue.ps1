# Which table columns carry a typed value, and how to read them. Keyed by the column header exactly as kubectl
# prints it; the same column means the same thing in every view (get/top, namespaced or not, wide or not).
# An explicit map on purpose: a column is typed because it is listed here, never because a value looks numeric.
#   restarts  '3' or '3 (5m ago)'            -> [long] 3
#   duration  '45s' '5m12s' '3d13h' '2y45d'  -> [TimeSpan]
#   ready     '1/2'                          -> [double] 0.5 (ready divided by total; 0/0 counts as 1)
#   count     '12'                           -> [long]
#   cpu       '250m' or '2' (cores)          -> [long] millicores
#   memory    '128Mi' '1Gi' '1000'           -> [long] bytes
#   percent   '26%'                          -> [long] 26
$script:KubectlColumnKinds = @{
    'RESTARTS'      = 'restarts'
    'AGE'           = 'duration'
    'LAST SEEN'     = 'duration'
    'DURATION'      = 'duration'
    'READY'         = 'ready'
    'COMPLETIONS'   = 'ready'
    'UP-TO-DATE'    = 'count'
    'AVAILABLE'     = 'count'
    'DATA'          = 'count'
    'CPU(cores)'    = 'cpu'
    'MEMORY(bytes)' = 'memory'
    'CPU(%)'        = 'percent'
    'MEMORY(%)'     = 'percent'
    'CAPACITY'      = 'memory'
}

# Cells kubectl prints when it has no value. They keep their text and have no Value.
$script:KubectlEmptyCells = @('<unknown>', '<invalid>', '<none>', '<nil>')

$script:KubectlMemoryUnits = @{
    'Ki' = [math]::Pow(1024, 1); 'Mi' = [math]::Pow(1024, 2); 'Gi' = [math]::Pow(1024, 3)
    'Ti' = [math]::Pow(1024, 4); 'Pi' = [math]::Pow(1024, 5); 'Ei' = [math]::Pow(1024, 6)
    'k'  = 1e3; 'M' = 1e6; 'G' = 1e9; 'T' = 1e12; 'P' = 1e15; 'E' = 1e18
}

function ConvertTo-KubectlValue {
    <#
        Turns one table cell into a [KubectlValue] when its column is typed (see $script:KubectlColumnKinds)
        and the text parses; otherwise returns the text unchanged. Never throws: a cell it does not
        understand (a future kubectl format, an empty cell) stays the plain string kubectl printed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Text,
        [Parameter(Mandatory)][string]$Column
    )
    $kind = $script:KubectlColumnKinds[$Column]
    if (-not $kind -or [string]::IsNullOrEmpty($Text)) { return $Text }
    if ($script:KubectlEmptyCells -contains $Text) { return [KubectlValue]::new($null, $Text) }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    switch ($kind) {
        'restarts' {
            if ($Text -match '^(\d+)( \(.+ ago\))?$') { return [KubectlValue]::new([long]$Matches[1], $Text) }
        }
        'count' {
            if ($Text -match '^\d+$') { return [KubectlValue]::new([long]$Text, $Text) }
        }
        'percent' {
            if ($Text -match '^(\d+)%$') { return [KubectlValue]::new([long]$Matches[1], $Text) }
        }
        'ready' {
            if ($Text -match '^(\d+)/(\d+)$') {
                $total = [long]$Matches[2]
                $ratio = if ($total -eq 0) { 1.0 } else { [long]$Matches[1] / $total }
                return [KubectlValue]::new([double]$ratio, $Text)
            }
        }
        'duration' {
            # kubectl's duration: up to two adjacent units from y d h m s (a year is 365 days), as in 2y45d, 3d13h, 5m12s
            if ($Text -match '^(?:(\d+)y)?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$') {
                $part = { param($i) if ($Matches[$i]) { [double]$Matches[$i] } else { 0.0 } }
                $span = [timespan]::FromSeconds(
                    (& $part 1) * 365 * 86400 + (& $part 2) * 86400 + (& $part 3) * 3600 + (& $part 4) * 60 + (& $part 5))
                return [KubectlValue]::new($span, $Text)
            }
        }
        'cpu' {
            if ($Text -match '^(\d+)m$') { return [KubectlValue]::new([long]$Matches[1], $Text) }
            if ($Text -match '^(\d+(\.\d+)?)$') { return [KubectlValue]::new([long]([double]::Parse($Matches[1], $inv) * 1000), $Text) }
        }
        'memory' {
            if ($Text -match '^(\d+(?:\.\d+)?)(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?$') {
                $multiplier = if ($Matches[2]) { $script:KubectlMemoryUnits[$Matches[2]] } else { 1 }
                return [KubectlValue]::new([long]([double]::Parse($Matches[1], $inv) * $multiplier), $Text)
            }
        }
    }
    $Text
}
