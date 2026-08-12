<#
.SYNOPSIS
Register (or unregister) the "Open with VSCode" Windows 11 modern context menu
for a portable VSCode installation, without MSI.

.DESCRIPTION
Uses the custom shell-extension package built by this repository:
- copies DLL + AppxManifest into %LOCALAPPDATA%\Programs\<Product>
- registers the sparse AppX package (Developer Mode is toggled temporarily if needed)
- writes the Chinese menu title ("Use VSCode Edit") into HKCU and HKLM
- optionally removes the previous custom package registration

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -Variant insiders
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -Uninstall
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -DryRun
#>
param(
    [string]$VSCodePath = 'D:\App\VSCode',
    [string]$PackageDir = '',
    [ValidateSet('stable', 'insiders')]
    [string]$Variant = 'stable',
    [switch]$Uninstall,
    [switch]$RestartExplorer,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if ($Variant -eq 'stable') {
    $ProductName = 'Code Modern Explorer Menu'
    $PackageName = 'Code.Modern.Explorer.Menu'
    $RegSuffix = 'CodeModernExplorerMenu'
    $DllName = 'Code Modern Explorer Menu.dll'
} else {
    $ProductName = 'Code Insiders Modern Explorer Menu'
    $PackageName = 'Code.Insiders.Modern.Explorer.Menu'
    $RegSuffix = 'CodeInsidersModernExplorerMenu'
    $DllName = 'Code Insiders Modern Explorer Menu.dll'
}

$InstallDir = Join-Path $env:LOCALAPPDATA ("Programs\" + $ProductName)
$TitleText = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"  # "Use VSCode Edit" in Chinese

function Resolve-PackageDir {
    if ($PackageDir) {
        return $PackageDir
    }

    # Newest build downloaded under artifacts\*\Code Modern Explorer Menu x64
    $artifactDir = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'artifacts') -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ($ProductName + ' x64') } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($artifactDir) {
        return $artifactDir.FullName
    }

    # Local build output (out\<product>)
    $outDir = Join-Path $repoRoot 'out'
    if (Test-Path (Join-Path $outDir ($DllName))) {
        return $outDir
    }

    throw "Package files not found. Pass -PackageDir pointing to a folder with the built .dll and .appx."
}

function Remove-RegistryKeys {
    foreach ($suffix in @('CodeModernExplorerMenu', 'CodeInsidersModernExplorerMenu')) {
        foreach ($root in @('HKCU:', 'HKLM:')) {
            $path = "$root\Software\Classes\$suffix"
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
}

if ($DryRun) {
    $packageDir = Resolve-PackageDir
    Write-Host '=== DRY RUN ==='
    Write-Host "VSCodePath : $VSCodePath"
    Write-Host "Variant    : $Variant"
    Write-Host "PackageDir : $packageDir"
    Write-Host "InstallDir : $InstallDir"
    if ($Uninstall) {
        Write-Host 'Action     : uninstall (remove package, registry keys, install dir)'
    } else {
        Write-Host 'Action     : register (copy files, Add-AppxPackage -Register, write Title registry)'
    }
    Write-Host "Title      : $TitleText"
    Write-Host '=== no changes made ==='
    exit 0
}

# Self-elevate (needed for HKLM writes and Developer Mode toggle).
if (-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    if ($Uninstall) { $argList += '-Uninstall' }
    if ($RestartExplorer) { $argList += '-RestartExplorer' }
    if ($Variant) { $argList += '-Variant', $Variant }
    if ($PackageDir) { $argList += '-PackageDir', ('"' + $PackageDir + '"') }
    if ($VSCodePath) { $argList += '-VSCodePath', ('"' + $VSCodePath + '"') }
    Start-Process -FilePath 'pwsh.exe' -ArgumentList $argList -Verb RunAs -Wait
    exit
}

# --- Uninstall ---------------------------------------------------------------
if ($Uninstall) {
    Write-Host "Unregistering $PackageName ..."
    Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
    Remove-RegistryKeys
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }
    Write-Host 'Done. Restart Explorer (or reboot) to refresh the context menu.'
    if ($RestartExplorer) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# --- Install -----------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $VSCodePath 'Code.exe'))) {
    throw "Code.exe not found under '$VSCodePath'. Pass -VSCodePath to point at the portable VSCode root."
}
if ($Variant -eq 'stable' -and $VSCodePath -ne 'D:\App\VSCode') {
    Write-Warning "The built DLL has the Code.exe path compiled in (D:\App\VSCode\Code.exe). If VSCode is elsewhere, only the menu title is guaranteed; the click action may fail."
}

$packageDir = Resolve-PackageDir
$appx = Get-ChildItem -LiteralPath $packageDir -Filter '*.appx' -ErrorAction SilentlyContinue | Select-Object -First 1
$dll = Get-ChildItem -LiteralPath $packageDir -Filter '*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $appx -or -not $dll) {
    throw "PackageDir '$packageDir' must contain one .appx and one .dll."
}

# Extract AppxManifest.xml from the built sparse package when not already loose.
$manifestSource = Join-Path $packageDir 'AppxManifest.xml'
$tmpExtract = Join-Path $packageDir '_appx_tmp'
if (-not (Test-Path -LiteralPath $manifestSource)) {
    if (Test-Path -LiteralPath $tmpExtract) {
        Remove-Item -LiteralPath $tmpExtract -Recurse -Force
    }
    Expand-Archive -LiteralPath $appx.FullName -DestinationPath $tmpExtract -Force
    $manifestSource = Join-Path $tmpExtract 'AppxManifest.xml'
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $InstallDir $DllName) -Force
Copy-Item -LiteralPath $manifestSource -Destination (Join-Path $InstallDir 'AppxManifest.xml') -Force
foreach ($name in @('[Content_Types].xml', 'AppxBlockMap.xml')) {
    $src = Join-Path $repoRoot $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $name) -Force
    }
}

# Temporarily enable Developer Mode when it is off (required for unsigned sparse packages).
$devRegPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devRegName = 'AllowDevelopmentWithoutDevLicense'
$devWasDisabled = $false
$devValue = Get-ItemProperty -Path ('HKLM:\' + $devRegPath) -Name $devRegName -ErrorAction SilentlyContinue
if ($null -eq $devValue -or $devValue.$devRegName -ne 1) {
    $devWasDisabled = $true
    reg add "HKLM\$devRegPath" /t REG_DWORD /v $devRegName /d 1 /reg:64 /f | Out-Null
    reg add "HKLM\$devRegPath" /t REG_DWORD /v $devRegName /d 1 /reg:32 /f | Out-Null
}

try {
    # Remove any previous registration of the same package so re-registration is clean.
    Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Write-Host "Registering $PackageName from $InstallDir ..."
    Add-AppxPackage -Path (Join-Path $InstallDir 'AppxManifest.xml') -Register -ExternalLocation $InstallDir
    if (-not $?) { throw 'Add-AppxPackage failed' }

    # Write the Chinese title into both hives (the DLL reads HKLM first, then HKCU).
    foreach ($root in @('HKCU:', 'HKLM:')) {
        $regPath = "$root\Software\Classes\$RegSuffix"
        New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name 'Title' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name '(default)' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host 'Registered. Restart Explorer (or reboot) to refresh the context menu.'
    if ($RestartExplorer) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
} finally {
    if ($devWasDisabled) {
        reg delete "HKLM\$devRegPath" /v $devRegName /reg:64 /f 2>&1 | Out-Null
        reg delete "HKLM\$devRegPath" /v $devRegName /reg:32 /f 2>&1 | Out-Null
    }
    if (Test-Path -LiteralPath $tmpExtract) {
        Remove-Item -LiteralPath $tmpExtract -Recurse -Force
    }
}
