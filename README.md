# specialK

This is **NOT** a verb-noun wrapper for `kubectl`. This is a simple, opinionated extension to `kubectl`.

specialK is designed to add PowerShell object functionality to `kubectl` while maintaining original syntax and output. For any command combinations that are supported, it calls `kubectl` directly and converts the output to PowerShell objects. For any command combinations not supported, it calls `kubectl` directly. This means that if you are familiar with `kubectl`, then you'll be familiar with specialK. If you learn specialK, then you'll be familiar with `kubectl` (and miss the objectification if you switch back to bash).

This is so true-to-source that it even works with `kubectl`'s PowerShell auto-completion (you just need to install it with `Add-specialKAutoCompletion`).

## Usage example

A simple listing of the pods

```powershell
k get pod
```

Output:

```plaintext
NAME                                     READY STATUS  RESTARTS AGE
----                                     ----- ------  -------- ---
blah-db-deployment-584189c448-6cszs      1/1   Running 0        3d13h
blah-monitor-deployment-7f4d5524cf-wj7nr 1/1   Running 0        21h
blah-monitor-deployment-85f748721d-7qxbq 1/1   Running 0        21h
blah-web-deployment-74bbf734b-4sdps      1/1   Running 0        21h
blah-web-deployment-74bbf734b-gs4mt      1/1   Running 0        21h
blah-web-deployment-74bbf734b-nc8kd      1/1   Running 0        21h
blah-web-deployment-74bbf734b-qddmr      1/1   Running 0        21h
```

Notice the PowerShell table headers? That means you can do:

```powershell
k get pods | ?{$_.Name -like 'blah-web*'} | %{kubectl exec $_.Name -- date}
```

This commands also demonstrates a current limitation of specialK. Since PowerShell doesn't pass `--` as a parameter, running `k exec pod-name -- command` will skip the `--`. In the future, this will be fully supported and there is no issue switching back to calling plain `kubectl` for this use case.

You can also:

```powershell
k config get-contexts | ?{$_.name -like '*staging*'} | %{k config use-context $_.name}
```

## Current objectized outputs

These `kubectl` command combinations are currently supported:

- get: pod, deployment, node, service
- top: pod, node
- config: get-contexts, get-clusters, get-users

Do be aware that adding support for additional command combinations is incredibly easy. The formats are all generated at build time using a script, which you can review: [formatUpdater.ps1](repoScripts/formatUpdater.ps1).