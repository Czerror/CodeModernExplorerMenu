# 复现 DLL GetTitle 的读取逻辑：HKCU -> HKLM，先读 Title 再读默认值，缺失时回退中文。
# 用于诊断"菜单标题显示英文"的问题。
$ErrorActionPreference = 'SilentlyContinue'

$fallback = "$([char]0x4F7F)$([char]0x7528) VSCode $([char]0x7F16)$([char]0x8F91)"

foreach ($variant in @('stable', 'insiders')) {
  $keyName = if ($variant -eq 'insiders') { 'CodeInsidersModernExplorerMenu' } else { 'CodeModernExplorerMenu' }
  $title = $null

  foreach ($root in @('HKCU:', 'HKLM:')) {
    $path = "$root\Software\Classes\$keyName"
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($item) {
      foreach ($valueName in @('Title', '(default)')) {
        $value = $item.GetValue($valueName)
        if ($value) {
          $title = [string]$value
          break
        }
      }
    }
    if ($title) { break }
  }

  if (-not $title) { $title = $fallback }
  Write-Output ("{0,-8}: {1}" -f $variant, $title)
}
