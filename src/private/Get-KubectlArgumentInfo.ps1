# Flags that take a value as the NEXT argument (`-n demo`, `--context foo`). The `--flag=value` and
# `-oVALUE` forms carry their value inside one argument and never need this list. Any other flag that
# starts with a dash is treated as a boolean. A value flag missing from here only matters when it
# appears before the verb or resource, where its value would be mistaken for one.
$script:KubectlValueFlags = @(
    '--namespace', '--context', '--cluster', '--user', '--kubeconfig', '--server', '--token',
    '--as', '--as-group', '--as-uid', '--request-timeout', '--selector', '--field-selector',
    '--output', '--sort-by', '--label-columns', '--filename', '--kustomize', '--chunk-size',
    '--template', '--cache-dir', '--certificate-authority', '--client-certificate', '--client-key',
    '--tls-server-name', '--username', '--password', '--container', '--profile', '--profile-output',
    '--v', '--vmodule', '--log-flush-frequency', '--subresource', '--field-manager'
)
# Single-letter equivalents of the above. `-n demo`, `-ndemo` and `-n=demo` are all valid.
$script:KubectlValueShortFlags = @('n', 's', 'l', 'o', 'L', 'f', 'k', 'c', 'v')

function Get-KubectlArgumentInfo {
    <#
        Finds out what a kubectl command line means without running it.
        Returns Verb (first positional), Positionals (the positionals after the verb, flags and their
        values removed), Output (the -o/--output value or $null), Watch, NoHeaders and AllNamespaces.
        Everything after a literal `--` is positional, as for kubectl.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][AllowNull()][string[]]$Arguments = @()
    )
    $positionals = [System.Collections.Generic.List[string]]::new()
    $info = [ordered]@{
        Verb          = $null
        Positionals   = @()
        Output        = $null
        Watch         = $false
        NoHeaders     = $false
        AllNamespaces = $false
    }

    $list = @($Arguments | Where-Object { $null -ne $_ })
    $i = 0
    while ($i -lt $list.Count) {
        $arg = $list[$i]
        $i++
        if ($arg -ceq '--') {
            while ($i -lt $list.Count) { $positionals.Add($list[$i]); $i++ }
            break
        }

        if ($arg -match '^--(?<name>[^=]+)(=(?<value>.*))?$') {
            $name = $Matches.name
            $hasValue = $Matches.ContainsKey('value')
            $value = if ($hasValue) { $Matches.value } else { $null }
            if (-not $hasValue -and ($script:KubectlValueFlags -contains "--$name")) {
                if ($i -lt $list.Count) { $value = $list[$i]; $i++ }
                $hasValue = $true
            }
            # boolean flags may carry an explicit value: --watch=false
            $isOn = -not ($hasValue -and $value -eq 'false')
            switch ($name) {
                'output' { $info.Output = $value }
                'watch' { if ($isOn) { $info.Watch = $true } }
                'watch-only' { if ($isOn) { $info.Watch = $true } }
                'no-headers' { if ($isOn) { $info.NoHeaders = $true } }
                'all-namespaces' { if ($isOn) { $info.AllNamespaces = $true } }
            }
            continue
        }

        if ($arg -match '^-(?<letters>[^-].*)$') {
            # a bundle of short flags (-Aw); the first value-taking letter ends it
            # and the rest of the argument is its value (-oyaml, -n=demo, -ndemo)
            $letters = $Matches.letters
            for ($c = 0; $c -lt $letters.Length; $c++) {
                $letter = [string]$letters[$c]
                if ($script:KubectlValueShortFlags -ccontains $letter) {
                    $value = $letters.Substring($c + 1)
                    if ($value.StartsWith('=')) { $value = $value.Substring(1) }
                    if ($value.Length -eq 0 -and $c -eq $letters.Length - 1) {
                        if ($i -lt $list.Count) { $value = $list[$i]; $i++ } else { $value = $null }
                    }
                    if ($letter -ceq 'o') { $info.Output = $value }
                    break
                }
                switch -CaseSensitive ($letter) {
                    'w' { $info.Watch = $true }
                    'A' { $info.AllNamespaces = $true }
                }
            }
            continue
        }

        $positionals.Add($arg)
    }

    if ($positionals.Count -gt 0) {
        $info.Verb = $positionals[0]
        $info.Positionals = @($positionals | Select-Object -Skip 1)
    }
    [pscustomobject]$info
}
