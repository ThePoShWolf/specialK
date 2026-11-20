# Unit tests for the private helpers behind `k`: argument parsing, resource names and table conversion.
# Offline; the helpers are called inside the test module (see TestHelpers.ps1).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:module = Import-SpecialKSource

    function Get-Info {
        param([string[]]$Arguments)
        & $script:module { param($a) Get-KubectlArgumentInfo -Arguments $a } $Arguments
    }
    function Get-Resource {
        param([string]$Name)
        & $script:module { param($n) ConvertTo-KubectlResourceName -Name $n } $Name
    }
}

AfterAll {
    Remove-SpecialKSource
}

Describe 'Get-KubectlArgumentInfo' {
    It 'finds the verb and positionals for <Command>' -ForEach @(
        @{ Command = 'get pods'; Kargs = @('get', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get pod web db'; Kargs = @('get', 'pod', 'web', 'db'); Verb = 'get'; Positionals = @('pod', 'web', 'db') }
        @{ Command = '-n kube-system get pods'; Kargs = @('-n', 'kube-system', 'get', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = '--context foo get pods'; Kargs = @('--context', 'foo', 'get', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = '--namespace=demo get pods'; Kargs = @('--namespace=demo', 'get', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get -n demo pods'; Kargs = @('get', '-n', 'demo', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get pods -n demo'; Kargs = @('get', 'pods', '-n', 'demo'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get pods -ndemo'; Kargs = @('get', 'pods', '-ndemo'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get pods -n=demo'; Kargs = @('get', 'pods', '-n=demo'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = '-A get pods'; Kargs = @('-A', 'get', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'get pods --show-labels -l app=web'; Kargs = @('get', 'pods', '--show-labels', '-l', 'app=web'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = '--kubeconfig f --context c -n n get svc'; Kargs = @('--kubeconfig', 'f', '--context', 'c', '-n', 'n', 'get', 'svc'); Verb = 'get'; Positionals = @('svc') }
        @{ Command = 'get --sort-by .metadata.name pods'; Kargs = @('get', '--sort-by', '.metadata.name', 'pods'); Verb = 'get'; Positionals = @('pods') }
        @{ Command = 'config get-contexts'; Kargs = @('config', 'get-contexts'); Verb = 'config'; Positionals = @('get-contexts') }
        @{ Command = 'frobnicate'; Kargs = @('frobnicate'); Verb = 'frobnicate'; Positionals = @() }
    ) {
        $info = Get-Info $Kargs
        $info.Verb | Should -Be $Verb
        @($info.Positionals) | Should -Be $Positionals
    }

    It 'has no verb when there are only flags or nothing' -ForEach @(
        @{ Kargs = @() }
        @{ Kargs = @('--help') }
        @{ Kargs = @('-n', 'demo') }
    ) {
        (Get-Info $Kargs).Verb | Should -BeNullOrEmpty
    }

    It 'reads the output format from <Form>' -ForEach @(
        @{ Form = '-o wide'; Kargs = @('get', 'pods', '-o', 'wide'); Output = 'wide' }
        @{ Form = '-owide'; Kargs = @('get', 'pods', '-owide'); Output = 'wide' }
        @{ Form = '-oyaml'; Kargs = @('get', 'pods', '-oyaml'); Output = 'yaml' }
        @{ Form = '-o=json'; Kargs = @('get', 'pods', '-o=json'); Output = 'json' }
        @{ Form = '--output wide'; Kargs = @('get', 'pods', '--output', 'wide'); Output = 'wide' }
        @{ Form = '--output=name'; Kargs = @('get', 'pods', '--output=name'); Output = 'name' }
        @{ Form = '-o before the verb'; Kargs = @('-o', 'yaml', 'get', 'pods'); Output = 'yaml' }
        @{ Form = 'a bundle (-Ao wide)'; Kargs = @('get', 'pods', '-Ao', 'wide'); Output = 'wide' }
        @{ Form = 'jsonpath'; Kargs = @('get', 'pods', '-o', 'jsonpath={.items[*].metadata.name}'); Output = 'jsonpath={.items[*].metadata.name}' }
        @{ Form = 'nothing'; Kargs = @('get', 'pods'); Output = $null }
    ) {
        (Get-Info $Kargs).Output | Should -Be $Output
    }

    It 'does not mistake a flag value for a resource: <Command>' -ForEach @(
        @{ Command = 'get -o wide pods'; Kargs = @('get', '-o', 'wide', 'pods') }
        @{ Command = 'get -l app=web pods'; Kargs = @('get', '-l', 'app=web', 'pods') }
        @{ Command = 'get --field-selector status.phase=Running pods'; Kargs = @('get', '--field-selector', 'status.phase=Running', 'pods') }
        @{ Command = 'get -L app pods'; Kargs = @('get', '-L', 'app', 'pods') }
    ) {
        @((Get-Info $Kargs).Positionals) | Should -Be @('pods')
    }

    It 'treats unknown flags as booleans: <Command>' -ForEach @(
        @{ Command = 'get pods --show-kind'; Kargs = @('get', 'pods', '--show-kind') }
        @{ Command = 'get --ignore-not-found pods'; Kargs = @('get', '--ignore-not-found', 'pods') }
        @{ Command = 'get -A pods'; Kargs = @('get', '-A', 'pods') }
    ) {
        @((Get-Info $Kargs).Positionals) | Should -Be @('pods')
    }

    It 'detects watching from <Form>' -ForEach @(
        @{ Form = '-w'; Kargs = @('get', 'pods', '-w') }
        @{ Form = '--watch'; Kargs = @('get', 'pods', '--watch') }
        @{ Form = '--watch=true'; Kargs = @('get', 'pods', '--watch=true') }
        @{ Form = '--watch-only'; Kargs = @('get', 'pods', '--watch-only') }
        @{ Form = '-wA (a bundle)'; Kargs = @('get', 'pods', '-wA') }
    ) {
        (Get-Info $Kargs).Watch | Should -BeTrue
    }

    It 'does not call it watching when <Form>' -ForEach @(
        @{ Form = '--watch=false'; Kargs = @('get', 'pods', '--watch=false') }
        @{ Form = 'not given'; Kargs = @('get', 'pods') }
        @{ Form = 'W is not w'; Kargs = @('get', 'pods', '-W') }
    ) {
        (Get-Info $Kargs).Watch | Should -BeFalse
    }

    It 'detects --no-headers and all namespaces' {
        (Get-Info @('get', 'pods', '--no-headers')).NoHeaders | Should -BeTrue
        (Get-Info @('get', 'pods')).NoHeaders | Should -BeFalse
        (Get-Info @('get', 'pods', '-A')).AllNamespaces | Should -BeTrue
        (Get-Info @('get', 'pods', '--all-namespaces')).AllNamespaces | Should -BeTrue
        (Get-Info @('get', 'pods')).AllNamespaces | Should -BeFalse
    }

    It 'keeps a comma-separated resource list as one positional' {
        @((Get-Info @('get', 'pods,svc')).Positionals) | Should -Be @('pods,svc')
    }

    It 'treats everything after -- as positional' {
        $info = Get-Info @('exec', 'web', '--', 'ls', '-l', '-w')
        $info.Verb | Should -Be 'exec'
        @($info.Positionals) | Should -Be @('web', 'ls', '-l', '-w')
        $info.Watch | Should -BeFalse
    }

    It 'copes with empty and null arguments' {
        (Get-Info @()).Verb | Should -BeNullOrEmpty
        (& $script:module { Get-KubectlArgumentInfo -Arguments $null }).Verb | Should -BeNullOrEmpty
    }
}
