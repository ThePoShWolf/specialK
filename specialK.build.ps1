param (
    [version]$Version = '0.0.1',
    [string]$NugetApiKey,
    [string]$PreRelease,
    # Where the built module goes. Defaults to ./build/<module>.
    [string]$BuildPath = (Join-Path $PSScriptRoot 'build'),
    # Pester tags to leave out of the Test task, e.g. -ExcludeTag KnownBug
    [string[]]$ExcludeTag,
    # Where the Test task writes its Pester result file (NUnit 2.5 XML). Nothing is written when omitted.
    [string]$TestResultPath
)
$srcPath = Join-Path $PSScriptRoot 'src'
$testPath = Join-Path $PSScriptRoot 'tests'
$moduleName = ($MyInvocation.MyCommand.Name.Split('.') | Select-Object -SkipLast 2) -join '.'
$modulePath = Join-Path $BuildPath $moduleName

Write-Host "Version: $($version)"

# Clean out any previous builds
task Clean {
    if (Get-Module $moduleName) {
        Remove-Module $moduleName
    }
    if (Test-Path $modulePath) {
        Remove-Item $modulePath -Recurse -ErrorAction Ignore | Out-Null
    }
}

# Build the module
task ModuleBuild Clean, {
    $moduleScriptFiles = & {
        Get-ChildItem (Join-Path $srcPath private) -Filter *.ps1 -File -Recurse
        Get-ChildItem (Join-Path $srcPath public) -Filter *.ps1 -File -Recurse
        Get-ChildItem $srcPath -Filter *.ps1 -File
    }
    if (-not(Test-Path $modulePath)) {
        New-Item $modulePath -ItemType Directory | Out-Null
    }
    $psm1 = Join-Path $modulePath "$moduleName.psm1"

    # Add using.ps1 to the .psm1 first
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -eq 'using.ps1' }) {
        if ($file.fullname) {
            Write-Host "Adding using file: '$($file.Fullname)'"
            Get-Content $file.fullname | Out-File $psm1 -Append -Encoding utf8
        }
    }

    # Add all .ps1 files to the .psm1, skipping onload.ps1, using.ps1, and any tests
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -ne 'onload.ps1' -and $_.Name -ne 'using.ps1' -and $_.FullName -notmatch '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$' }) {
        if ($file.fullname) {
            Write-Host "Adding function file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File $psm1 -Append -Encoding utf8
        }
    }
    
    # Add the onload.ps1 files last
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -eq 'onload.ps1' }) {
        if ($file.fullname) {
            Write-Host "Adding onload file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File $psm1 -Append -Encoding utf8
        }
    }

    # Copy any .dlls
    Copy-Item (Join-Path $PSScriptRoot lib) -Destination $modulePath -Recurse -Force -ErrorAction SilentlyContinue

    # Copy the manifest
    Copy-Item (Join-Path $srcPath "$moduleName.psd1") -Destination $modulePath

    # Copy the tests
    foreach ($test in ($moduleScriptFiles | Where-Object { $_.FullName -match '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$' })) {
        Write-Host "Copying test file: '$($test.FullName)'"
        Copy-Item $test.FullName -Destination $modulePath
    }

    # Copy the formats.json
    Copy-Item (Join-Path $srcPath formats.json) -Destination $modulePath

    # Generate the formats from the fixtures. This never touches a cluster; see repoScripts/New-FormatFile.ps1.
    & (Join-Path $PSScriptRoot repoScripts New-FormatFile.ps1) -OutPath (Join-Path $modulePath 'k.format.ps1xml')

    # Get existing manifest data
    $manifestPath = Join-Path $modulePath "$moduleName.psd1"
    $moduleManifestData = Invoke-Command -ScriptBlock ([scriptblock]::create((Get-Content $manifestPath -Raw))) -NoNewScope
    foreach ($key in $moduleManifestData['PrivateData']['PSData'].Keys) {
        $moduleManifestData[$key] = $moduleManifestData['PrivateData']['PSData'][$key]
    }

    # update
    $moduleManifestData['Path'] = $manifestPath
    $moduleManifestData['FunctionsToExport'] = ($moduleScriptFiles | Where-Object { $_.FullName -match "(\\|\/)public(\\|\/)[^\.]+\.ps1$" }).basename
    $ModuleManifestData['ModuleVersion'] = $version
    if ($PreRelease) {
        $moduleManifestData['Prerelease'] = $PreRelease
    }
    Update-ModuleManifest @moduleManifestData
}

# Run the offline Pester suite (tests/). It needs no cluster, no network and no build; it loads src/ itself.
# The Smoke tag (tests/smoke, real kubectl and cluster) is always excluded; see SmokeTest.
#   Invoke-Build Test                      everything offline; the KnownBug tests currently fail on purpose
#   Invoke-Build Test -ExcludeTag KnownBug only what is expected to pass today
#   Invoke-Build Test -TestResultPath ./testResults/unit.xml   also write NUnit XML
task Test {
    $config = New-PesterConfiguration
    $config.Run.Path = $testPath
    $config.Run.Throw = $true
    $config.Output.Verbosity = 'Normal'
    $config.Filter.ExcludeTag = @($ExcludeTag) + 'Smoke' | Where-Object { $_ } | Select-Object -Unique
    if ($TestResultPath) {
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = $TestResultPath
    }
    Invoke-Pester -Configuration $config
}

# Smoke test against a real cluster: runs only tests/smoke, importing the BUILT module (run ModuleBuild first, or use
# Invoke-Build ModuleBuild, SmokeTest). Needs kubectl and a reachable cluster with metrics-server; the CI smoke job
# sets that up with kind. The suite creates and removes its own namespace.
#   Invoke-Build ModuleBuild, SmokeTest -TestResultPath ./testResults/smoke.xml
task SmokeTest {
    if (-not (Test-Path (Join-Path $modulePath "$moduleName.psd1"))) {
        throw "No built module at '$modulePath'. Run 'Invoke-Build ModuleBuild' first."
    }
    $env:SPECIALK_SMOKE_MODULE = $modulePath
    try {
        $config = New-PesterConfiguration
        $config.Run.Path = Join-Path $testPath 'smoke'
        $config.Run.Throw = $true
        $config.Output.Verbosity = 'Detailed'
        $config.Filter.Tag = 'Smoke'
        if ($ExcludeTag) {
            $config.Filter.ExcludeTag = $ExcludeTag
        }
        if ($TestResultPath) {
            $config.TestResult.Enabled = $true
            $config.TestResult.OutputFormat = 'NUnitXml'
            $config.TestResult.OutputPath = $TestResultPath
        }
        Invoke-Pester -Configuration $config
    }
    finally {
        Remove-Item Env:\SPECIALK_SMOKE_MODULE -ErrorAction Ignore
    }
}

# Publishes the built module. Does nothing unless -NugetApiKey is given. (Release flow is reworked in a later phase.)
task Publish Test, ModuleBuild, {
    if (-not $NugetApiKey) {
        Write-Host 'No -NugetApiKey given, not publishing.'
        return
    }
    Publish-Module -Path $modulePath -NuGetApiKey $NugetApiKey -Repository PSGallery
}

# Build, then test. Does not publish.
task All ModuleBuild, Test
