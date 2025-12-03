# If not running as Administrator, re-launch the script with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Start-Process powershell.exe -ArgumentList "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($script:MyInvocation.MyCommand.Path)`"" -Verb RunAs -Wait -WindowStyle Minimized
    exit
}

$ScriptRoot = if ( $PSScriptRoot ) { $PSScriptRoot } else { ($(try { $script:psEditor.GetEditorContext().CurrentFile.Path } catch {}), $script:MyInvocation.MyCommand.Path, $script:PSCommandPath, $(try { $script:psISE.CurrentFile.Fullpath.ToString() } catch {}) | % { if ($_ ) { $_.ToLower() } } | Split-Path -EA 0 | Get-Unique ) | Get-Unique }

$ProductName = 'Code Modern Explorer Menu'
$ProductPath = "$Env:LOCALAPPDATA\Programs\$ProductName"
$PackageName = $ProductName -replace '\s+', '.'

if ($ScriptRoot -match 'Insiders') {
    $ProductName = 'Code Insiders Modern Explorer Menu'
    $ProductPath = "$Env:LOCALAPPDATA\Programs\$ProductName"
    $PackageName = $ProductName -replace '\s+', '.'
}

# 删除注册表键 - 使用 cmd 确保中文字符正确处理
cmd /c "REG DELETE `"HKEY_CURRENT_USER\Software\Classes\CodeModernExplorerMenu`" /F >NUL 2>&1"

# 卸载 AppX 包
$appxPackage = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
if ($appxPackage) {
    Remove-AppxPackage -Package $appxPackage.PackageFullName -ErrorAction SilentlyContinue
}

# 删除程序目录
if (Test-Path $ProductPath) {
    Remove-Item -Path $ProductPath -Recurse -Force -ErrorAction SilentlyContinue
}
