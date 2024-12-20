param (
    [version]$Version = '0.0.1',
    [string]$NugetApiKey,
    [string]$PreRelease,
    [switch]$ReuseFormats
)
$srcPath = "$PSScriptRoot\src"
$buildPath = "$PSScriptRoot\build"
$docPath = "$PSScriptRoot\docs"
$testPath = "$PSScriptRoot\tests"
$moduleName = ($MyInvocation.MyCommand.Name.Split('.') | Select-Object -SkipLast 2) -join '.'
$modulePath = "$buildPath\$ModuleName"

Write-Host "Version: $($version)"

# Clean out any previous builds
task Clean {
    if ($ReuseFormats.IsPresent) {
        Write-Host 'Backing up format...'
        $script:formats = Get-Content $modulePath\k.format.ps1xml
    }
    if (Get-Module $moduleName) {
        Remove-Module $moduleName
    }
    if (Test-Path $modulePath) {
        Remove-Item $modulePath -Recurse -ErrorAction Ignore | Out-Null
    }
}

# Build the docs, depends on PlatyPS
task DocBuild ModuleBuild, {
    if (-not (Test-Path $docPath)) {
        New-Item $docPath -ItemType Directory
    }
    New-ExternalHelp $docPath -OutputPath "$modulePath\EN-US"
}

# Build the module
task ModuleBuild Clean, {
    $moduleScriptFiles = & {
        Get-ChildItem $srcPath\private -Filter *.ps1 -File -Recurse
        Get-ChildItem $srcPath\public -Filter *.ps1 -File -Recurse
        Get-ChildItem $srcPath -Filter *.ps1 -File
    }
    if (-not(Test-Path $modulePath)) {
        New-Item $modulePath -ItemType Directory
    }

    # Add using.ps1 to the .psm1 first
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -eq 'using.ps1' }) {
        if ($file.fullname) {
            Write-Host "Adding using file: '$($file.Fullname)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }

    # Add all .ps1 files to the .psm1, skipping onload.ps1, using.ps1, and any tests
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -ne 'onload.ps1' -and $_.Name -ne 'using.ps1' -and $_.FullName -notmatch '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$' }) {
        if ($file.fullname) {
            Write-Host "Adding function file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }
    
    # Add the onload.ps1 files last
    foreach ($file in $moduleScriptFiles | Where-Object { $_.Name -eq 'onload.ps1' }) {
        if ($file.fullname) {
            Write-Host "Adding onload file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }

    # Copy any .dlls
    Copy-Item $PSScriptRoot\lib -Destination $modulePath -Recurse -Force -ErrorAction SilentlyContinue

    # Copy the manifest
    Copy-Item "$srcPath\$moduleName.psd1" -Destination $modulePath

    # Copy the tests
    foreach ($test in ($moduleScriptFiles | Where-Object { $_.FullName -match '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$' })) {
        Write-Host "Copying test file: '$($test.FullName)'"
        Copy-Item $test.FullName -Destination $modulePath
    }

    # Copy the formats.json
    Copy-Item $srcPath\formats.json -Destination $modulePath

    # Generate the formats
    if ($ReuseFormats.IsPresent) {
        Write-Host 'Restoring format...'
        $formats | Out-File $modulePath\k.format.ps1xml
    } else {
        Write-Host "Generating format file, this may take a few seconds..."
        . $srcPath\onload.ps1
        . $srcPath\public\k.ps1
        .\repoScripts\formatUpdater.ps1 -OutPath $modulePath\k.format.ps1xml
    }

    # Get existing manifest data
    $moduleManifestData = Invoke-Command -ScriptBlock ([scriptblock]::create((Get-Content $modulePath\$moduleName.psd1 -Raw))) -NoNewScope
    foreach ($key in $moduleManifestData['PrivateData']['PSData'].Keys) {
        $moduleManifestData[$key] = $moduleManifestData['PrivateData']['PSData'][$key]
    }

    # update
    $moduleManifestData['Path'] = "$modulePath\$moduleName.psd1"
    $moduleManifestData['FunctionsToExport'] = ($moduleScriptFiles | Where-Object { $_.FullName -match "(\\|\/)public(\\|\/)[^\.]+\.ps1$" }).basename
    $ModuleManifestData['ModuleVersion'] = $version
    if ($null -ne $PreRelease) {
        $moduleManifestData['Prerelease'] = $PreRelease
    }
    Update-ModuleManifest @moduleManifestData
}

task Test ModuleBuild, {
    Write-Host "Importing module."
    Import-Module $modulePath -RequiredVersion $version
    Write-Host "Invoking tests."
    Invoke-Pester $testPath -Verbose
}

task Publish Test, DocBuild, {
    if ($null -ne $NugetApiKey) {
        Publish-Module -Path .\build\$moduleName -NuGetApiKey $NugetApiKey -Repository PsGallery
    }
}

task All ModuleBuild, Publish