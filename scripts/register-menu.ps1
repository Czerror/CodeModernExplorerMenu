<#
.SYNOPSIS
Register (or unregister) the "Open with VSCode" Windows 11 modern context menu
directly from the official VSCode portable package. No MSI, no custom DLL.

.DESCRIPTION
The official portable package ships `appx\code_x64.appx` and
`appx\code_explorer_command_x64.dll`. The official shell extension resolves
Code.exe by walking TWO parent folders up from the DLL directory, so this
script copies the appx files into `<root>\<versioned-folder>\appx` and registers
the sparse package with that directory as the external location:

    <root>\<version>\appx\code_explorer_command_x64.dll
      -> up 1: <root>\<version>
      -> up 2: <root>
      -> <root>\Code.exe

The script then writes the Chinese title ("Use VSCode Edit") into
`HKCU/HKLM\Software\Classes\VSCodeContextMenu`, which both enables the stable
menu and sets its display name. The old custom package from this repository is
removed so the two menus do not collide.

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -DryRun
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -Uninstall
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -RestartExplorer
#>
param(
    [string]$VSCodePath = '',
    [switch]$Uninstall,
    [switch]$RestartExplorer,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$TitleText = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"  # "Use VSCode Edit" in Chinese

$OfficialPackageName = 'Microsoft.VisualStudioCode'
$AppxFileName = 'code_x64.appx'
$DllFileName = 'code_explorer_command_x64.dll'
$RegKeyName = 'VSCodeContextMenu'

# Old custom-menu leftovers from the previous MSI/DLL approach.
$LegacyPackageNames = @('Code.Modern.Explorer.Menu', 'Code.Insiders.Modern.Explorer.Menu')
$LegacyRegKeys = @('CodeModernExplorerMenu', 'CodeInsidersModernExplorerMenu')

function Find-VSCodeRoot([string]$StartDir) {
    # Walk up from the script location until Code.exe is found, so the whole
    # portable folder can be moved freely together with this script.
    $dir = $StartDir
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir 'Code.exe')) {
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Remove-RegistryKey([string]$KeyName) {
    foreach ($root in @('HKCU:', 'HKLM:')) {
        $path = "$root\Software\Classes\$KeyName"
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

if ($DryRun) {
    $autoDetected = $false
    if (-not $VSCodePath) {
        $VSCodePath = Find-VSCodeRoot $PSScriptRoot
        $autoDetected = $true
    }
    Write-Host '=== DRY RUN ==='
    Write-Host ("VSCodePath : {0} {1}" -f $VSCodePath, $(if ($autoDetected) { '(auto-detected)' } else { '(specified)' }))
    if ($Uninstall) {
        Write-Host 'Action     : uninstall (remove official package, registry keys, copied appx)'
    } else {
        Write-Host 'Action     : register official sparse package + write Chinese title'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $VSCodePath 'Code.exe'))) {
        Write-Host "ERROR      : Code.exe not found under $VSCodePath"
        exit 1
    }
    $versionDir = Get-ChildItem -LiteralPath $VSCodePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources\app\package.json') } |
        Select-Object -First 1
    if (-not $versionDir) {
        Write-Host 'ERROR      : versioned folder (resources\app\package.json) not found under VSCodePath'
        exit 1
    }
    $targetDir = Join-Path $versionDir.FullName 'appx'
    $sourceDir = Join-Path $VSCodePath 'appx'
    Write-Host "VersionDir : $($versionDir.FullName)"
    Write-Host "SourceDir  : $sourceDir"
    Write-Host "TargetDir  : $targetDir"
    Write-Host "Package    : $OfficialPackageName (signed, no Developer Mode needed)"
    Write-Host "Title key  : $RegKeyName = $TitleText (HKCU + HKLM)"
    Write-Host '=== no changes made ==='
    exit 0
}

# Self-elevate (needed for HKLM registry writes).
if (-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $elevatedShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    if ($Uninstall) { $argList += '-Uninstall' }
    if ($RestartExplorer) { $argList += '-RestartExplorer' }
    if ($VSCodePath) { $argList += '-VSCodePath', ('"' + $VSCodePath + '"') }
    Start-Process -FilePath $elevatedShell -ArgumentList $argList -Verb RunAs -Wait
    exit
}

# Auto-detect the portable VSCode root next to (or above) this script.
if (-not $VSCodePath) {
    $VSCodePath = Find-VSCodeRoot $PSScriptRoot
}
if (-not (Test-Path -LiteralPath (Join-Path $VSCodePath 'Code.exe'))) {
    throw "Code.exe not found. Put this script inside the portable VSCode folder or pass -VSCodePath to point at its root."
}

$versionDir = Get-ChildItem -LiteralPath $VSCodePath -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources\app\package.json') } |
    Select-Object -First 1
if (-not $versionDir) {
    throw "Versioned folder (resources\app\package.json) not found under '$VSCodePath'. Unsupported VSCode layout."
}

$sourceDir = Join-Path $VSCodePath 'appx'
$targetDir = Join-Path $versionDir.FullName 'appx'
$sourceAppx = Join-Path $sourceDir $AppxFileName
$sourceDll = Join-Path $sourceDir $DllFileName
if (-not (Test-Path -LiteralPath $sourceAppx) -or -not (Test-Path -LiteralPath $sourceDll)) {
    throw "Official appx files missing: expected $sourceAppx and $sourceDll"
}

function Remove-LegacyMenu {
    foreach ($pkgName in $LegacyPackageNames) {
        Get-AppxPackage -Name $pkgName -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
    }
    foreach ($keyName in $LegacyRegKeys) {
        Remove-RegistryKey $keyName
    }
}

if ($Uninstall) {
    Write-Host "Removing official package $OfficialPackageName ..."
    Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Remove-RegistryKey $RegKeyName
    Remove-LegacyMenu

    # Remove only the appx copies this script manages.
    if (Test-Path -LiteralPath (Join-Path $targetDir $AppxFileName)) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
    }

    Write-Host 'Done. Restart Explorer (or reboot) to refresh the context menu.'
    if ($RestartExplorer) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# --- Install -----------------------------------------------------------------
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
Copy-Item -LiteralPath $sourceAppx -Destination (Join-Path $targetDir $AppxFileName) -Force
Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $targetDir $DllFileName) -Force

# Re-register cleanly: remove any previous official registration first.
Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

Write-Host "Registering $OfficialPackageName from $targetDir ..."
Add-AppxPackage -Path (Join-Path $targetDir $AppxFileName) -ExternalLocation $targetDir
if (-not $?) {
    throw 'Add-AppxPackage failed. Check that the package is Microsoft-signed and this is Windows 11.'
}

# Chinese title in both hives (HKLM first is what the official DLL reads).
foreach ($root in @('HKLM:', 'HKCU:')) {
    $regPath = "$root\Software\Classes\$RegKeyName"
    New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $regPath -Name 'Title' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $regPath -Name '(default)' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

# Drop the old custom-menu registration so only the official menu remains.
Remove-LegacyMenu

Write-Host 'Registered. Restart Explorer (or reboot) to refresh the context menu.'
if ($RestartExplorer) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
