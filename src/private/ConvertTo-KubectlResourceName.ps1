# Every spelling kubectl accepts for a resource (plural, singular, short name) mapped to one canonical
# name. The canonical names are the ones in formats.json, so they double as format view names.
# `events` is canonical in the plural because that is how formats.json and the views spell it.
# An explicit table on purpose: guessing at plurals by trimming a trailing "s" turns `ingress` into `ingres`.
$script:KubectlResourceAliases = @{
    'pod'                    = 'pod'
    'pods'                   = 'pod'
    'po'                     = 'pod'
    'deployment'             = 'deployment'
    'deployments'            = 'deployment'
    'deploy'                 = 'deployment'
    'service'                = 'service'
    'services'               = 'service'
    'svc'                    = 'service'
    'namespace'              = 'namespace'
    'namespaces'             = 'namespace'
    'ns'                     = 'namespace'
    'node'                   = 'node'
    'nodes'                  = 'node'
    'no'                     = 'node'
    'event'                  = 'events'
    'events'                 = 'events'
    'ev'                     = 'events'
    'configmap'              = 'configmap'
    'configmaps'             = 'configmap'
    'cm'                     = 'configmap'
    'secret'                 = 'secret'
    'secrets'                = 'secret'
    'ingress'                = 'ingress'
    'ingresses'              = 'ingress'
    'ing'                    = 'ingress'
    'persistentvolumeclaim'  = 'persistentvolumeclaim'
    'persistentvolumeclaims' = 'persistentvolumeclaim'
    'pvc'                    = 'persistentvolumeclaim'
    'persistentvolume'       = 'persistentvolume'
    'persistentvolumes'      = 'persistentvolume'
    'pv'                     = 'persistentvolume'
    'statefulset'            = 'statefulset'
    'statefulsets'           = 'statefulset'
    'sts'                    = 'statefulset'
    'daemonset'              = 'daemonset'
    'daemonsets'             = 'daemonset'
    'ds'                     = 'daemonset'
    'replicaset'             = 'replicaset'
    'replicasets'            = 'replicaset'
    'rs'                     = 'replicaset'
    'job'                    = 'job'
    'jobs'                   = 'job'
    'cronjob'                = 'cronjob'
    'cronjobs'               = 'cronjob'
    'cj'                     = 'cronjob'
    'serviceaccount'         = 'serviceaccount'
    'serviceaccounts'        = 'serviceaccount'
    'sa'                     = 'serviceaccount'
    'endpoints'              = 'endpoints'
    'ep'                     = 'endpoints'
}

function ConvertTo-KubectlResourceName {
    <#
        Turns what the user typed after the verb into a canonical resource name.
        Handles short and plural names (po, deploy, svc), `type/name` (pod/web) and
        `type.group` (deployments.apps). Names it does not know come back lowercased and otherwise
        untouched, which keeps config sub-commands such as get-contexts working.
        Returns $null for nothing, and for a comma-separated list (pods,svc), which is several resources.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Contains(',')) { return $null }
    $resource = $Name.ToLowerInvariant()
    $slash = $resource.IndexOf('/')
    if ($slash -ge 0) { $resource = $resource.Substring(0, $slash) }
    if ($script:KubectlResourceAliases.ContainsKey($resource)) { return $script:KubectlResourceAliases[$resource] }
    # type.group, e.g. deployments.apps or deployments.v1.apps
    $dot = $resource.IndexOf('.')
    if ($dot -gt 0) {
        $kind = $resource.Substring(0, $dot)
        if ($script:KubectlResourceAliases.ContainsKey($kind)) { return $script:KubectlResourceAliases[$kind] }
    }
    $resource
}
