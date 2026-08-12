<#
.SYNOPSIS
VSCode portable context-menu tool (Windows 11 modern menu) with a small GUI.

.DESCRIPTION
Place this script (and register-menu.cmd) directly inside the VSCode portable
root, next to Code.exe. Double-click register-menu.cmd to open the GUI with two
buttons:

    [Register menu]  - register the official Microsoft-signed sparse package
                       (appx\code_x64.appx + appx\code_explorer_command_x64.dll)
                       and write the Chinese title "Use VSCode Edit".
    [Unregister]     - remove the package, registry keys and copied files.

Only the script's own directory is searched for Code.exe - no parent lookups.
If Code.exe is missing, the GUI shows a hint to place the script in the VSCode
portable root.

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1            # GUI
pwsh -ExecutionPolicy Bypass -File scripts\register-menu.ps1 -DryRun    # preview
#>
param(
    [string]$VSCodePath = '',
    [ValidateSet('register', 'uninstall')]
    [string]$Action = '',
    [string]$LogFile = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$TitleText = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"  # "Use VSCode Edit" in Chinese

$OfficialPackageName = 'Microsoft.VisualStudioCode'
$AppxFileName = 'code_x64.appx'
$DllFileName = 'code_explorer_command_x64.dll'
$RegKeyName = 'VSCodeContextMenu'
$LegacyPackageNames = @('Code.Modern.Explorer.Menu', 'Code.Insiders.Modern.Explorer.Menu')
$LegacyRegKeys = @('CodeModernExplorerMenu', 'CodeInsidersModernExplorerMenu')

function Write-Log([string]$Message) {
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $Message -Encoding utf8
    }
    Write-Host $Message
}

function Find-VSCodeRoot {
    # Only the script's own directory is used - no upward search.
    if ($VSCodePath) {
        return $VSCodePath
    }
    return $PSScriptRoot
}

function Test-VSCodeRoot([string]$Root) {
    return (Test-Path -LiteralPath (Join-Path $Root 'Code.exe'))
}

function Remove-RegistryKey([string]$KeyName) {
    foreach ($root in @('HKCU:', 'HKLM:')) {
        $path = "$root\Software\Classes\$KeyName"
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
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

function Get-VersionDir([string]$Root) {
    return Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources\app\package.json') } |
        Select-Object -First 1
}

function Invoke-Register([string]$Root) {
    $versionDir = Get-VersionDir $Root
    if (-not $versionDir) {
        throw 'Versioned folder (resources\app\package.json) not found. Unsupported VSCode layout.'
    }

    $sourceDir = Join-Path $Root 'appx'
    $targetDir = Join-Path $versionDir.FullName 'appx'
    $sourceAppx = Join-Path $sourceDir $AppxFileName
    $sourceDll = Join-Path $sourceDir $DllFileName
    if (-not (Test-Path -LiteralPath $sourceAppx) -or -not (Test-Path -LiteralPath $sourceDll)) {
        throw "Official appx files missing: expected $sourceAppx and $sourceDll"
    }

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceAppx -Destination (Join-Path $targetDir $AppxFileName) -Force
    Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $targetDir $DllFileName) -Force

    Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Write-Log "Registering $OfficialPackageName from $targetDir ..."
    Add-AppxPackage -Path (Join-Path $targetDir $AppxFileName) -ExternalLocation $targetDir
    if (-not $?) {
        throw 'Add-AppxPackage failed. Check that the package is Microsoft-signed and this is Windows 11.'
    }

    foreach ($rootKey in @('HKLM:', 'HKCU:')) {
        $regPath = "$rootKey\Software\Classes\$RegKeyName"
        New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name 'Title' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name '(default)' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    }

    Remove-LegacyMenu
    Write-Log "Registered. Title = $TitleText"
}

function Invoke-Uninstall([string]$Root) {
    Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Remove-RegistryKey $RegKeyName
    Remove-LegacyMenu

    $versionDir = Get-VersionDir $Root
    if ($versionDir) {
        $targetDir = Join-Path $versionDir.FullName 'appx'
        if (Test-Path -LiteralPath (Join-Path $targetDir $AppxFileName)) {
            Remove-Item -LiteralPath $targetDir -Recurse -Force
        }
    }
    Write-Log 'Unregistered.'
}

# --- Headless action mode (used by the GUI's elevated child) -----------------
if ($Action) {
    $root = Find-VSCodeRoot
    if (-not (Test-VSCodeRoot $root)) {
        Write-Log "ERROR: Code.exe not found in $root"
        Write-Log '请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）'
        exit 1
    }

    $isAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        $elevatedShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
            '-VSCodePath', ('"' + $root + '"'), '-Action', $Action, '-LogFile', ('"' + $LogFile + '"'))
        $p = Start-Process -FilePath $elevatedShell -ArgumentList $argList -Verb RunAs -Wait -PassThru
        exit $p.ExitCode
    }

    try {
        if ($Action -eq 'register') {
            Invoke-Register $root
        } else {
            Invoke-Uninstall $root
        }
        Write-Log 'DONE'
        exit 0
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }
}

# --- Dry run (CLI preview) ---------------------------------------------------
if ($DryRun) {
    $root = Find-VSCodeRoot
    Write-Host '=== DRY RUN ==='
    if (-not (Test-VSCodeRoot $root)) {
        Write-Host "Code.exe not found in: $root"
        Write-Host '请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）'
        exit 1
    }
    $versionDir = Get-VersionDir $root
    if (-not $versionDir) {
        Write-Host 'ERROR: versioned folder (resources\app\package.json) not found'
        exit 1
    }
    Write-Host "VSCodePath : $root"
    Write-Host "VersionDir : $($versionDir.FullName)"
    Write-Host "TargetDir  : $(Join-Path $versionDir.FullName 'appx')"
    Write-Host "Package    : $OfficialPackageName (signed, no Developer Mode needed)"
    Write-Host "Title key  : $RegKeyName = $TitleText (HKCU + HKLM)"
    Write-Host '=== no changes made ==='
    exit 0
}

# --- GUI mode (default) ------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Find-VSCodeRoot
$found = Test-VSCodeRoot $root

function Invoke-ActionElevated([string]$ActionName) {
    $logFile = Join-Path $env:TEMP 'cmem-register-menu.log'
    Remove-Item -LiteralPath $logFile -ErrorAction SilentlyContinue

    $isAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $exitCode = 1
    if ($isAdmin) {
        try {
            if ($ActionName -eq 'register') {
                Invoke-Register $root
            } else {
                Invoke-Uninstall $root
            }
            Add-Content -LiteralPath $logFile -Value 'DONE' -Encoding utf8
            $exitCode = 0
        } catch {
            Add-Content -LiteralPath $logFile -Value ("ERROR: " + $_.Exception.Message) -Encoding utf8
        }
    } else {
        $elevatedShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
            '-VSCodePath', ('"' + $root + '"'), '-Action', $ActionName, '-LogFile', ('"' + $logFile + '"'))
        try {
            $p = Start-Process -FilePath $elevatedShell -ArgumentList $argList -Verb RunAs -Wait -PassThru
            $exitCode = $p.ExitCode
        } catch {
            [void][System.Windows.Forms.MessageBox]::Show(
                "操作未执行（UAC 被取消？）：`r`n$($_.Exception.Message)",
                '提示', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
    }

    $log = if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile -Raw } else { '' }
    if ($exitCode -eq 0) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            '操作完成。' + "`r`n" + $log + "`r`n是否立即重启资源管理器？",
            '完成', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        }
    } else {
        [void][System.Windows.Forms.MessageBox]::Show(
            "操作失败：`r`n$log",
            '错误', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VSCode 便携版右键菜单'
$form.ClientSize = New-Object System.Drawing.Size(470, 160)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 15)
$statusLabel.Size = New-Object System.Drawing.Size(430, 55)
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
if ($found) {
    $statusLabel.Text = "已找到 VSCode：`r`n$root"
} else {
    $statusLabel.Text = "未找到 Code.exe`r`n请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）"
}

$btnRegister = New-Object System.Windows.Forms.Button
$btnRegister.Text = '注册右键菜单'
$btnRegister.Size = New-Object System.Drawing.Size(190, 45)
$btnRegister.Location = New-Object System.Drawing.Point(35, 90)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = '删除右键菜单'
$btnUninstall.Size = New-Object System.Drawing.Size(190, 45)
$btnUninstall.Location = New-Object System.Drawing.Point(245, 90)

if (-not $found) {
    $btnRegister.Enabled = $false
    $btnUninstall.Enabled = $false
}

$btnRegister.add_Click({ Invoke-ActionElevated 'register' })
$btnUninstall.add_Click({ Invoke-ActionElevated 'uninstall' })

$form.Controls.AddRange(@($statusLabel, $btnRegister, $btnUninstall))
[void]$form.ShowDialog()
