<#
    Code in this file will be added to the end of the .psm1. For example,
    you should set variables or other environment settings here.
#>
$script:objectCommands = Get-Content $PSScriptRoot\formats.json | ConvertFrom-Json -AsHashtable