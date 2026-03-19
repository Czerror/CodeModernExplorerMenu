#requires -RunAsAdministrator
# -*- coding: utf-8 -*-

# If not running as Administrator, re-launch the script with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Start-Process powershell.exe -ArgumentList "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($script:MyInvocation.MyCommand.Path)`"" -Verb RunAs -Wait -WindowStyle Minimized
    exit
}

$ScriptRoot = if ( $PSScriptRoot ) { $PSScriptRoot } else { ($(try { $script:psEditor.GetEditorContext().CurrentFile.Path } catch {}), $script:MyInvocation.MyCommand.Path, $script:PSCommandPath, $(try { $script:psISE.CurrentFile.Fullpath.ToString() } catch {}) | ForEach-Object { if ($_ ) { $_.ToLower() } } | Split-Path -EA 0 | Get-Unique ) | Get-Unique }
$ProductPath = "$Env:LOCALAPPDATA\Programs\Code Modern Explorer Menu"

if (-not (Test-Path $ProductPath)) {
    New-Item -Path $ProductPath -Force | Out-Null
}

# Use Unicode code points to construct Chinese text - immune to file encoding issues
# "使用 VSCode 编辑" = U+4F7F U+7528 U+0020 VSCode U+0020 U+7F16 U+8F91
$regKeyPath = "HKCU:\Software\Classes\CodeModernExplorerMenu"
$null = New-Item -Path $regKeyPath -Force -ErrorAction SilentlyContinue

$chineseText = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"
New-ItemProperty -Path $regKeyPath -Name "(default)" -Value $chineseText -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKeyPath -Name "Title" -Value $chineseText -PropertyType String -Force | Out-Null

# Temporary enable Developer Mode if initially disabled
$RegPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
$RegKeyName = "AllowDevelopmentWithoutDevLicense"
$DeveloperModeInitialStatus = 'Enabled'

$value = Get-ItemProperty -Path ('HKLM:\' + $RegPath) -Name $RegKeyName -ErrorAction SilentlyContinue
if ($null -eq $value -or $value.$RegKeyName -ne 1) {
    $DeveloperModeInitialStatus = 'Disabled'
    REG ADD "HKLM\$RegPath" /t REG_DWORD /v "$RegKeyName" /d "1" /reg:64 /f
    REG ADD "HKLM\$RegPath" /t REG_DWORD /v "$RegKeyName" /d "1" /reg:32 /f
}

Add-AppxPackage -Path "$ScriptRoot\AppxManifest.xml" -Register -ExternalLocation $ProductPath

# Restore Developer Mode to previous settings
if ($DeveloperModeInitialStatus -eq 'Disabled') {
    REG DELETE "HKLM\$RegPath" /v "$RegKeyName" /reg:64 /f
    REG DELETE "HKLM\$RegPath" /v "$RegKeyName" /reg:32 /f
}
