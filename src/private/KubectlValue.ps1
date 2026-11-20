# One cell of a kubectl table that has a typed value but must keep printing exactly as kubectl printed it.
#
#   Text   the cell as kubectl printed it ('2 (3h15m ago)', '3d13h', '250m'). ToString() returns it, so the
#          default table, Format-List, Export-Csv, string interpolation and -match see the original text.
#   Value  what the cell means: [long] (counts, millicores, bytes, percent), [double] (ready ratio) or
#          [TimeSpan] (ages). $null for a cell kubectl could not fill in ('<unknown>', '<none>').
#
# It compares by Value (IComparable), so Sort-Object, Group-Object and -lt/-gt/-eq work. PowerShell converts the
# right-hand operand to the type of the left-hand one before comparing, which is why there is one constructor
# per type a user would compare against (number, [TimeSpan], string). A cell with no Value sorts after everything,
# which keeps -lt filters from matching it. IConvertible is there so Measure-Object -Sum/-Average works on
# numeric cells (CPU, MEMORY, RESTARTS). Any other class member is deliberately absent: keep it small.
class KubectlValue : System.IComparable, System.IConvertible {
    [object]$Value
    [string]$Text

    KubectlValue([object]$value, [string]$text) {
        $this.Value = $value
        $this.Text = $text
    }
    KubectlValue([long]$value) {
        $this.Value = $value
        $this.Text = "$value"
    }
    KubectlValue([double]$value) {
        $this.Value = $value
        $this.Text = "$value"
    }
    KubectlValue([timespan]$value) {
        $this.Value = $value
        $this.Text = "$value"
    }
    # A plain string on the right of a comparison ('-gt "3"'): numbers and durations are read, anything else has no Value.
    KubectlValue([string]$text) {
        $this.Text = $text
        $number = 0.0
        $span = [timespan]::Zero
        if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            $this.Value = $number
        } elseif ($text -match '^(?=\d)(?:(\d+)y)?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$') {
            # a kubectl-style duration, so AGE -lt '1h' reads the way kubectl prints ages
            $seconds = 0.0
            $unit = @((365 * 86400), 86400, 3600, 60, 1)
            for ($i = 1; $i -le 5; $i++) { if ($Matches[$i]) { $seconds += [double]$Matches[$i] * $unit[$i - 1] } }
            $this.Value = [timespan]::FromSeconds($seconds)
        } elseif ([timespan]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$span)) {
            $this.Value = $span
        }
    }

    [string] ToString() {
        return $this.Text
    }

    # Numbers compare as numbers, durations as durations. Anything else (a number against a duration) is
    # ordered after, never an error: a bad comparison must not break a pipeline. The text only decides when a
    # side has no Value to compare: two cells without one are equal when they print the same, and ordered by
    # their text otherwise. A cell with a Value sorts before one without.
    [int] CompareTo([object]$other) {
        # a plain string is read the same way as on the right of -lt/-gt ('1h', '3')
        if ($other -is [string]) { $other = [KubectlValue]::new([string]$other) }
        $theirs = if ($other -is [KubectlValue]) { $other.Value } else { $other }
        $theirText = if ($other -is [KubectlValue]) { $other.Text } else { "$other" }
        $mine = $this.Value
        if ($null -eq $mine -or $null -eq $theirs) {
            $byText = [string]::Compare($this.Text, $theirText, [System.StringComparison]::OrdinalIgnoreCase)
            if ($byText -eq 0) { return 0 }
            if ($null -eq $mine -and $null -eq $theirs) { return [Math]::Sign($byText) }
            if ($null -eq $mine) { return 1 }
            return -1
        }
        if ($mine -is [timespan] -and $theirs -is [timespan]) { return $mine.CompareTo($theirs) }
        # a number against a duration can't be ordered, but the same text is still the same cell: CPU -eq '250m'
        # reads '250m' as 250 minutes, and must still match the cell kubectl printed as 250m
        if ($mine -is [timespan] -or $theirs -is [timespan]) {
            if ([string]::Equals($this.Text, $theirText, [System.StringComparison]::OrdinalIgnoreCase)) { return 0 }
            return 1
        }
        $a = 0.0
        $b = 0.0
        if ([double]::TryParse("$mine", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$a) -and
            [double]::TryParse("$theirs", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$b)) {
            return $a.CompareTo($b)
        }
        return 1
    }

    [bool] Equals([object]$other) {
        if ($null -eq $other) { return $false }
        return $this.CompareTo($other) -eq 0
    }

    # Must agree with Equals: numbers hash as doubles (1000 and 1000.0 are equal), cells without a Value by their
    # text, ignoring case.
    [int] GetHashCode() {
        if ($null -eq $this.Value) { return $this.Text.ToUpperInvariant().GetHashCode() }
        if ($this.Value -is [timespan]) { return $this.Value.GetHashCode() }
        $number = 0.0
        if ([double]::TryParse("$($this.Value)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number.GetHashCode() }
        return $this.Value.GetHashCode()
    }

    # IConvertible: only the numeric conversions mean something.
    [double] AsDouble() {
        if ($this.Value -is [timespan]) { return $this.Value.TotalSeconds }
        if ($null -eq $this.Value) { throw [System.InvalidCastException]::new("'$($this.Text)' has no numeric value") }
        return [double]$this.Value
    }
    [System.TypeCode] GetTypeCode() { return [System.TypeCode]::Object }
    [double] ToDouble([System.IFormatProvider]$provider) { return $this.AsDouble() }
    [decimal] ToDecimal([System.IFormatProvider]$provider) { return [decimal]$this.AsDouble() }
    [long] ToInt64([System.IFormatProvider]$provider) { return [long]$this.AsDouble() }
    [int] ToInt32([System.IFormatProvider]$provider) { return [int]$this.AsDouble() }
    [int16] ToInt16([System.IFormatProvider]$provider) { return [int16]$this.AsDouble() }
    [float] ToSingle([System.IFormatProvider]$provider) { return [float]$this.AsDouble() }
    [string] ToString([System.IFormatProvider]$provider) { return $this.Text }
    [bool] ToBoolean([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [byte] ToByte([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [char] ToChar([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [datetime] ToDateTime([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [sbyte] ToSByte([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [uint16] ToUInt16([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [uint32] ToUInt32([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [uint64] ToUInt64([System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
    [object] ToType([type]$conversionType, [System.IFormatProvider]$provider) { throw [System.InvalidCastException]::new() }
}
