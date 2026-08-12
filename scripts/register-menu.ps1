<#
.SYNOPSIS
    VSCode 便携版右键菜单注册/删除工具 (Windows 11 现代菜单)

.DESCRIPTION
    交互式脚本：把本脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录），
    运行后显示菜单：
        [1] 注册右键菜单
        [2] 删除右键菜单
        [3] 退出
    只搜索脚本所在目录的 Code.exe，不会向上查找。

.PARAMETER VSCodePath
    手动指定 VSCode 根目录（可选，默认使用脚本所在目录）

.PARAMETER Action
    无交互执行: register / uninstall（供提权子进程使用）

.PARAMETER DryRun
    仅预览，不做任何修改

.EXAMPLE
    .\register-menu.ps1
    交互式模式

.EXAMPLE
    .\register-menu.ps1 -DryRun
    检查环境并预览操作
#>
param(
    [string]$VSCodePath = '',
    [ValidateSet('register', 'uninstall')]
    [string]$Action = '',
    [string]$LogFile = '',
    [switch]$DryRun
)

# ============== 全局配置 ==============
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = 'VSCode 便携版右键菜单' } catch {}

$TitleText = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"  # 使用 VSCode 编辑

$OfficialPackageName = 'Microsoft.VisualStudioCode'
$AppxFileName = 'code_x64.appx'
$DllFileName = 'code_explorer_command_x64.dll'
$RegKeyName = 'VSCodeContextMenu'
$LegacyPackageNames = @('Code.Modern.Explorer.Menu', 'Code.Insiders.Modern.Explorer.Menu')
$LegacyRegKeys = @('CodeModernExplorerMenu', 'CodeInsidersModernExplorerMenu')

# ============== 工具函数 ==============
function Write-Log([string]$Message) {
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $Message -Encoding utf8
    }
    Write-Host $Message
}

function Find-VSCodeRoot {
    # 只搜索脚本所在目录，不向上查找
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
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Remove-ManagedAppxCopies([string]$Root, [string]$ExceptDir = '') {
    # 只清理版本目录（含 resources\app\package.json）里由本脚本复制的 appx，不影响固定位置 .menu
    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $ExceptDir -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'resources\app\package.json')) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "appx\$AppxFileName"))
        } |
        ForEach-Object {
            Remove-Item -LiteralPath (Join-Path $_.FullName 'appx') -Recurse -Force -ErrorAction SilentlyContinue
        }
}

function Get-AppxVersion([string]$AppxPath) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($AppxPath)
        $entry = $zip.GetEntry('AppxManifest.xml')
        if (-not $entry) {
            $zip.Dispose()
            return $null
        }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        $xml = [xml]$reader.ReadToEnd()
        $reader.Dispose()
        $zip.Dispose()
        return [string]$xml.Package.Identity.Version
    } catch {
        return $null
    }
}

function Get-RegisteredVersion {
    $pkg = Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { return [string]$pkg.Version }
    return $null
}

function Invoke-Register([string]$Root) {
    $sourceDir = Join-Path $Root 'appx'
    # 固定外部位置：.menu\appx 位于根目录下两层，官方 DLL 上溯 2 级即命中根目录 Code.exe，
    # 不依赖随版本变化的哈希目录名（如 a5b5009513）。
    $targetDir = Join-Path $Root '.menu\appx'
    $sourceAppx = Join-Path $sourceDir $AppxFileName
    $sourceDll = Join-Path $sourceDir $DllFileName
    if (-not (Test-Path -LiteralPath $sourceAppx) -or -not (Test-Path -LiteralPath $sourceDll)) {
        throw "缺少官方文件：$sourceAppx / $sourceDll"
    }

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceAppx -Destination (Join-Path $targetDir $AppxFileName) -Force
    Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $targetDir $DllFileName) -Force
    Remove-ManagedAppxCopies -Root $Root -ExceptDir $targetDir

    Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Write-Log "  注册包: $OfficialPackageName"
    Add-AppxPackage -Path (Join-Path $targetDir $AppxFileName) -ExternalLocation $targetDir
    if (-not $?) {
        throw 'Add-AppxPackage 失败，请确认是 Windows 11 且包为微软签名'
    }

    foreach ($rootKey in @('HKLM:', 'HKCU:')) {
        $regPath = "$rootKey\Software\Classes\$RegKeyName"
        New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name 'Title' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regPath -Name '(default)' -Value $TitleText -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    }

    Remove-LegacyMenu
    Write-Log "  中文标题: $TitleText"
}

function Invoke-Uninstall([string]$Root) {
    Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

    Remove-RegistryKey $RegKeyName
    Remove-LegacyMenu

    $menuDir = Join-Path $Root '.menu\appx'
    if (Test-Path -LiteralPath (Join-Path $menuDir $AppxFileName)) {
        Remove-Item -LiteralPath $menuDir -Recurse -Force
    }
    Remove-ManagedAppxCopies -Root $Root
    Write-Log '  已删除右键菜单注册'
}

function Invoke-Elevated([string]$ActionName, [string]$Root, [string]$LogFile) {
    $isAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        if ($ActionName -eq 'register') { Invoke-Register $Root } else { Invoke-Uninstall $Root }
        return 0
    }

    $elevatedShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
        '-VSCodePath', ('"' + $Root + '"'), '-Action', $ActionName, '-LogFile', ('"' + $LogFile + '"'))
    $p = Start-Process -FilePath $elevatedShell -ArgumentList $argList -Verb RunAs -Wait -PassThru
    return $p.ExitCode
}

# ============== 无交互模式（提权子进程） ==============
if ($Action) {
    $root = Find-VSCodeRoot
    if (-not (Test-VSCodeRoot $root)) {
        Write-Log "ERROR: Code.exe not found in $root"
        Write-Log '请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）'
        exit 1
    }
    try {
        if ($Action -eq 'register') { Invoke-Register $root } else { Invoke-Uninstall $root }
        Write-Log 'DONE'
        exit 0
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }
}

# ============== 预览模式 ==============
if ($DryRun) {
    $root = Find-VSCodeRoot
    Write-Host '=== DRY RUN ==='
    if (-not (Test-VSCodeRoot $root)) {
        Write-Host "Code.exe not found in: $root"
        Write-Host '请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）'
        exit 1
    }
    $versionDir = Get-VersionDir $root
    Write-Host "VSCodePath : $root"
    if ($versionDir) {
        Write-Host "VersionDir : $($versionDir.FullName)  (随版本变化，脚本不依赖它)"
    } else {
        Write-Host 'VersionDir : (未检测到版本目录，不影响注册)'
    }
    Write-Host "TargetDir  : $(Join-Path $root '.menu\appx')  (固定位置)"
    Write-Host "Package    : $OfficialPackageName (微软签名，无需开发者模式)"
    Write-Host "Title key  : $RegKeyName = $TitleText (HKCU + HKLM)"
    Write-Host '=== 未做任何修改 ==='
    exit 0
}

# ============== 交互 UI（仿 build.ps1 风格） ==============
function Write-Banner {
    try { Clear-Host } catch {}
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║        VSCode 便携版右键菜单 v1.4           ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host "  ── $Title " -ForegroundColor Yellow -NoNewline
    $padding = 45 - $Title.Length
    if ($padding -gt 0) { Write-Host ('─' * $padding) -ForegroundColor Yellow } else { Write-Host '' }
}

function Show-Menu {
    param(
        [string]$Title,
        [array]$Options,
        [int]$Default = 0,
        [switch]$ShowDesc
    )
    Write-Section $Title
    Write-Host ''
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $prefix = if ($i -eq $Default) { ' >' } else { '  ' }
        $color = if ($i -eq $Default) { 'Green' } else { 'White' }
        Write-Host "$prefix [$($i + 1)] $($Options[$i].Name)" -ForegroundColor $color -NoNewline
        if ($ShowDesc -and $Options[$i].Desc) {
            Write-Host " - $($Options[$i].Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host ''
        }
    }
    Write-Host ''
    $choice = Read-Host "  请选择 [1-$($Options.Count)] (默认: $($Default + 1))"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $Default }
    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $Options.Count) { return $index }
    return $Default
}

function Show-YesNo {
    param(
        [string]$Question,
        [bool]$Default = $true
    )
    $defaultText = if ($Default) { 'Y/n' } else { 'y/N' }
    $choice = Read-Host "  $Question [$defaultText]"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $Default }
    $c = $choice.ToLower()
    return ($c -eq 'y' -or $c -eq 'yes' -or $choice -eq '是')
}

function Show-Result([int]$ExitCode, [string]$Log) {
    if ($ExitCode -eq 0) {
        Write-Host ''
        Write-Host '  [成功] 操作完成' -ForegroundColor Green
        if ($Log) { Write-Host $Log -ForegroundColor DarkGray }
        Write-Host ''
        if (Show-YesNo -Question '是否立即重启资源管理器?' -Default $true) {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Write-Host '  已重启资源管理器' -ForegroundColor Gray
        }
    } else {
        Write-Host ''
        Write-Host '  [失败] 操作未完成' -ForegroundColor Red
        if ($Log) { Write-Host $Log -ForegroundColor DarkGray }
    }
}

function Run-Action([string]$ActionName, [string]$ConfirmText) {
    if (-not (Show-YesNo -Question $ConfirmText -Default $true)) {
        Write-Host '  已取消' -ForegroundColor Yellow
        return
    }

    $logFile = Join-Path $env:TEMP 'cmem-register-menu.log'
    Remove-Item -LiteralPath $logFile -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host "  正在执行（可能需要 UAC 确认）..." -ForegroundColor Gray
    $exitCode = Invoke-Elevated -ActionName $ActionName -Root $root -LogFile $logFile
    $log = if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile -Raw } else { '' }
    Show-Result -ExitCode $exitCode -Log $log
}

trap {
    Write-Host ''
    Write-Host "  [错误] $_" -ForegroundColor Red
    Write-Host ''
    Read-Host '  按 Enter 退出'
    exit 1
}

$root = Find-VSCodeRoot

if (-not (Test-VSCodeRoot $root)) {
    Write-Banner
    Write-Host '  [错误] 未找到 Code.exe' -ForegroundColor Red
    Write-Host ''
    Write-Host '  请把脚本放到 VSCode 便携版根目录（与 Code.exe 同一目录）' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '  按 Enter 退出'
    exit 1
}

$menuOptions = @(
    @{ Name = '注册右键菜单'; Desc = '注册官方稀疏包，标题为“使用 VSCode 编辑”' },
    @{ Name = '删除右键菜单'; Desc = '移除包、注册表和复制的文件' },
    @{ Name = '退出'; Desc = '' }
)

while ($true) {
    Write-Banner
    Write-Host "  VSCode 目录: $root" -ForegroundColor DarkGray
    $appxVersion = Get-AppxVersion (Join-Path $root "appx\$AppxFileName")
    $registeredVersion = Get-RegisteredVersion
    if ($appxVersion -and $registeredVersion -and $appxVersion -ne $registeredVersion) {
        Write-Host "  [提示] 检测到 VSCode 已更新（已注册: $registeredVersion / 当前: $appxVersion）" -ForegroundColor Yellow
        Write-Host '         请选择 [1] 重新注册，否则菜单可能失效' -ForegroundColor Yellow
    } elseif (-not $registeredVersion) {
        Write-Host '  [提示] 当前未注册右键菜单' -ForegroundColor DarkGray
    }
    $choice = Show-Menu -Title '主菜单' -Options $menuOptions -Default 0 -ShowDesc
    switch ($choice) {
        0 { Run-Action -ActionName 'register' -ConfirmText '确认注册右键菜单?' }
        1 { Run-Action -ActionName 'uninstall' -ConfirmText '确认删除右键菜单?' }
        2 {
            Write-Host ''
            Read-Host '  按 Enter 退出'
            exit 0
        }
    }
}
