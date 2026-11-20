# Typed table cells: how a cell is parsed (ConvertTo-KubectlValue), and what the typed objects do in the
# pipeline (sort, filter, measure) and on screen. Offline; see TestHelpers.ps1.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:module = Import-SpecialKSource

    function ConvertTo-Cell {
        param([string]$Text, [string]$Column)
        & $script:module { param($t, $c) ConvertTo-KubectlValue -Text $t -Column $c } $Text $Column
    }
}

AfterAll {
    Remove-SpecialKSource
}

Describe 'ConvertTo-KubectlValue' {
    It '<Column> "<Text>" has value <Expected> and still prints as "<Text>"' -ForEach @(
        @{ Column = 'RESTARTS'; Text = '0'; Expected = 0 }
        @{ Column = 'RESTARTS'; Text = '3'; Expected = 3 }
        @{ Column = 'RESTARTS'; Text = '2 (3h15m ago)'; Expected = 2 }
        @{ Column = 'RESTARTS'; Text = '13 (5m ago)'; Expected = 13 }
        @{ Column = 'UP-TO-DATE'; Text = '2'; Expected = 2 }
        @{ Column = 'AVAILABLE'; Text = '0'; Expected = 0 }
        @{ Column = 'DATA'; Text = '3'; Expected = 3 }
        @{ Column = 'CPU(cores)'; Text = '250m'; Expected = 250 }
        @{ Column = 'CPU(cores)'; Text = '1m'; Expected = 1 }
        @{ Column = 'CPU(cores)'; Text = '2'; Expected = 2000 }
        @{ Column = 'MEMORY(bytes)'; Text = '128Mi'; Expected = 134217728 }
        @{ Column = 'MEMORY(bytes)'; Text = '13Mi'; Expected = 13631488 }
        @{ Column = 'MEMORY(bytes)'; Text = '1024Mi'; Expected = 1073741824 }
        @{ Column = 'MEMORY(bytes)'; Text = '2Gi'; Expected = 2147483648 }
        @{ Column = 'MEMORY(bytes)'; Text = '512Ki'; Expected = 524288 }
        @{ Column = 'MEMORY(bytes)'; Text = '1000'; Expected = 1000 }
        @{ Column = 'MEMORY(bytes)'; Text = '5M'; Expected = 5000000 }
        @{ Column = 'CAPACITY'; Text = '1Gi'; Expected = 1073741824 }
        @{ Column = 'CPU(%)'; Text = '5%'; Expected = 5 }
        @{ Column = 'MEMORY(%)'; Text = '26%'; Expected = 26 }
    ) {
        $cell = ConvertTo-Cell $Text $Column
        $cell.GetType().Name | Should -Be 'KubectlValue'
        $cell.Value | Should -Be $Expected
        $cell.ToString() | Should -BeExactly $Text
        "$cell" | Should -BeExactly $Text
    }

    It 'READY "<Text>" is the ready fraction <Expected>' -ForEach @(
        @{ Text = '1/1'; Expected = 1.0 }
        @{ Text = '0/1'; Expected = 0.0 }
        @{ Text = '0/2'; Expected = 0.0 }
        @{ Text = '1/2'; Expected = 0.5 }
        @{ Text = '3/3'; Expected = 1.0 }
        @{ Text = '0/0'; Expected = 1.0 }
    ) {
        $cell = ConvertTo-Cell $Text 'READY'
        $cell.Value | Should -Be $Expected
        $cell.ToString() | Should -BeExactly $Text
    }

    It '<Column> "<Text>" is a duration of <Seconds> seconds' -ForEach @(
        @{ Column = 'AGE'; Text = '0s'; Seconds = 0 }
        @{ Column = 'AGE'; Text = '45s'; Seconds = 45 }
        @{ Column = 'AGE'; Text = '5m12s'; Seconds = 312 }
        @{ Column = 'AGE'; Text = '90m'; Seconds = 5400 }
        @{ Column = 'AGE'; Text = '3h15m'; Seconds = 11700 }
        @{ Column = 'AGE'; Text = '3d13h'; Seconds = 306000 }
        @{ Column = 'AGE'; Text = '120d'; Seconds = 10368000 }
        @{ Column = 'AGE'; Text = '2y45d'; Seconds = 66960000 }
        @{ Column = 'LAST SEEN'; Text = '112s'; Seconds = 112 }
        @{ Column = 'LAST SEEN'; Text = '6m52s'; Seconds = 412 }
        @{ Column = 'DURATION'; Text = '5s'; Seconds = 5 }
    ) {
        $cell = ConvertTo-Cell $Text $Column
        $cell.Value | Should -BeOfType [timespan]
        $cell.Value.TotalSeconds | Should -Be $Seconds
        $cell.ToString() | Should -BeExactly $Text
    }

    It '<Column> "<Text>" has no value but keeps its text' -ForEach @(
        @{ Column = 'AGE'; Text = '<unknown>' }
        @{ Column = 'AGE'; Text = '<invalid>' }
        @{ Column = 'LAST SEEN'; Text = '<unknown>' }
        @{ Column = 'CPU(%)'; Text = '<unknown>' }
        @{ Column = 'MEMORY(%)'; Text = '<unknown>' }
        @{ Column = 'DURATION'; Text = '<none>' }
    ) {
        $cell = ConvertTo-Cell $Text $Column
        $cell.GetType().Name | Should -Be 'KubectlValue'
        $cell.Value | Should -BeNullOrEmpty
        $cell.ToString() | Should -BeExactly $Text
    }

    It 'leaves <Column> "<Text>" a plain string' -ForEach @(
        @{ Column = 'RESTARTS'; Text = 'many' }
        @{ Column = 'RESTARTS'; Text = '3 restarts' }
        @{ Column = 'AGE'; Text = '5 weeks' }
        @{ Column = 'AGE'; Text = '12' }
        @{ Column = 'AGE'; Text = '5x' }
        @{ Column = 'READY'; Text = '1' }
        @{ Column = 'READY'; Text = '1/x' }
        @{ Column = 'CPU(cores)'; Text = '1.5.2' }
        @{ Column = 'MEMORY(bytes)'; Text = '12Zi' }
        @{ Column = 'CPU(%)'; Text = '5' }
        @{ Column = 'AGE'; Text = '' }
    ) {
        $cell = ConvertTo-Cell $Text $Column
        $cell | Should -BeOfType [string]
        $cell | Should -BeExactly $Text
    }

    It 'never types a column that is not in the map, however numeric it looks' -ForEach @(
        @{ Column = 'NAME'; Text = '12' }
        @{ Column = 'STATUS'; Text = '1/1' }
        @{ Column = 'PORT(S)'; Text = '80' }
        @{ Column = 'CLUSTER-IP'; Text = '10.43.0.1' }
    ) {
        $cell = ConvertTo-Cell $Text $Column
        $cell | Should -BeOfType [string]
    }
}

Describe 'KubectlValue in a pipeline' {
    BeforeAll {
        # rows built straight from text, so no fake kubectl is involved
        function New-Rows {
            param([string]$Column, [string[]]$Texts)
            $i = 0
            foreach ($text in $Texts) {
                $row = [ordered]@{ NAME = "r$i" }
                $row[$Column] = ConvertTo-Cell $text $Column
                $i++
                [pscustomobject]$row
            }
        }
    }

    It 'sorts restarts by number, 10 after 9' {
        $rows = New-Rows RESTARTS @('10 (5m ago)', '9', '100', '0', '2 (3h15m ago)')
        ($rows | Sort-Object RESTARTS | ForEach-Object { "$($_.RESTARTS)" }) | Should -Be @('0', '2 (3h15m ago)', '9', '10 (5m ago)', '100')
        ($rows | Sort-Object RESTARTS -Descending | Select-Object -First 1).RESTARTS.ToString() | Should -Be '100'
    }

    It 'filters restarts with -gt, -ge, -lt, -eq against numbers' {
        $rows = New-Rows RESTARTS @('10 (5m ago)', '9', '100', '0', '3')
        @($rows | Where-Object RESTARTS -gt 3).Count | Should -Be 3
        @($rows | Where-Object RESTARTS -ge 3).Count | Should -Be 4
        @($rows | Where-Object RESTARTS -lt 3).Count | Should -Be 1
        @($rows | Where-Object RESTARTS -eq 3).Count | Should -Be 1
        @($rows | Where-Object RESTARTS -eq 10).Count | Should -Be 1
        @($rows | Where-Object { $_.RESTARTS -gt 3.5 }).Count | Should -Be 3
        @($rows | Where-Object { 9 -lt $_.RESTARTS }).Count | Should -Be 2
    }

    It 'sorts and filters ages as durations, not text' {
        $rows = New-Rows AGE @('3d13h', '45s', '5m12s', '120d', '3h15m', '2y45d')
        ($rows | Sort-Object AGE | ForEach-Object { "$($_.AGE)" }) | Should -Be @('45s', '5m12s', '3h15m', '3d13h', '120d', '2y45d')
        @($rows | Where-Object AGE -lt (New-TimeSpan -Hours 1)).Count | Should -Be 2
        @($rows | Where-Object AGE -gt (New-TimeSpan -Days 4)).Count | Should -Be 2
        @($rows | Where-Object { $_.AGE -ge [timespan]::FromDays(120) }).Count | Should -Be 2
    }

    It 'orders cells without a value after every real value, so -lt filters leave them out' {
        $rows = New-Rows AGE @('<unknown>', '5m', '1d')
        ($rows | Sort-Object AGE | ForEach-Object { "$($_.AGE)" }) | Should -Be @('5m', '1d', '<unknown>')
        @($rows | Where-Object AGE -lt (New-TimeSpan -Hours 1)).Count | Should -Be 1
    }

    It 'does not throw when a typed cell is mixed with a plain string' {
        $rows = @(New-Rows AGE @('5m', '1d')) + [pscustomobject]@{ NAME = 'odd'; AGE = '5 weeks' }
        { $rows | Sort-Object AGE } | Should -Not -Throw
        ($rows | Sort-Object AGE | Select-Object -First 1).NAME | Should -Be 'r0'
    }

    It 'sorts cpu and memory by quantity, not by text' {
        ((New-Rows 'CPU(cores)' @('250m', '1m', '1', '12m')) | Sort-Object 'CPU(cores)' | ForEach-Object { "$($_.'CPU(cores)')" }) |
            Should -Be @('1m', '12m', '250m', '1')
        ((New-Rows 'MEMORY(bytes)' @('1Gi', '128Mi', '900Ki', '1000')) | Sort-Object 'MEMORY(bytes)' | ForEach-Object { "$($_.'MEMORY(bytes)')" }) |
            Should -Be @('1000', '900Ki', '128Mi', '1Gi')
    }

    It 'sorts ready counts by fraction, so unready sorts first' {
        $rows = New-Rows READY @('1/1', '0/2', '1/2', '3/3')
        ($rows | Sort-Object READY | Select-Object -First 1).READY.ToString() | Should -Be '0/2'
        @($rows | Where-Object READY -lt 1).Count | Should -Be 2
    }

    It 'sums and averages numeric columns with Measure-Object' {
        $cpu = New-Rows 'CPU(cores)' @('250m', '1m', '12m')
        ($cpu | Measure-Object 'CPU(cores)' -Sum).Sum | Should -Be 263
        $memory = New-Rows 'MEMORY(bytes)' @('1Mi', '2Mi')
        ($memory | Measure-Object 'MEMORY(bytes)' -Sum -Average).Average | Should -Be 1572864
    }

    It 'keeps -eq against a typed value and groups equal values' {
        $rows = New-Rows RESTARTS @('3', '3', '4')
        @($rows | Group-Object RESTARTS).Count | Should -Be 2
        ($rows[0].RESTARTS -eq $rows[1].RESTARTS) | Should -BeTrue
    }

    It 'exports and formats the original text' {
        $rows = New-Rows RESTARTS @('2 (3h15m ago)', '9')
        ($rows | ConvertTo-Csv -NoTypeInformation) | Should -Contain '"r0","2 (3h15m ago)"'
        ($rows | Format-List | Out-String) | Should -Match 'RESTARTS : 2 \(3h15m ago\)'
        "$($rows[0].RESTARTS)" | Should -BeExactly '2 (3h15m ago)'
        $rows[0].RESTARTS -match '3h15m' | Should -BeTrue
    }
}
