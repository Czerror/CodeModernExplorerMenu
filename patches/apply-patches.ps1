# Applies the fork patches onto a clean upstream/main checkout.
#
# Usage (from repo root, after `git reset --hard upstream/main`):
#   powershell -ExecutionPolicy Bypass -File patches\apply-patches.ps1 [-Commit]
param(
  [switch]$Commit
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$patchesRoot = Join-Path $repoRoot 'patches'
Set-Location $repoRoot

# 1. Remove the deps/wil submodule (the fork uses vcpkg instead).
git submodule deinit -f deps/wil 2>$null
if (Test-Path -LiteralPath (Join-Path $repoRoot 'deps\wil')) {
  Remove-Item -LiteralPath (Join-Path $repoRoot 'deps\wil') -Recurse -Force
}
git rm -q --cached deps/wil 2>$null

# 2. Copy feature files (pure new files, cannot conflict).
$features = @(
  '.gitattributes',
  '.editorconfig',
  '.github/workflows/build-win.yml',
  'AppxBlockMap.xml',
  '[Content_Types].xml',
  'build-msi.ps1',
  'msi/RunOnInstall.ps1',
  'msi/RunOnUninstall.ps1',
  'scripts/generate_pkg.py',
  'scripts/check-title.ps1',
  'template/AppxManifest.xml',
  'vcpkg.json'
)
foreach ($rel in $features) {
  $src = Join-Path $patchesRoot ('features/' + $rel)
  $dst = Join-Path $repoRoot $rel
  New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

# 3. Apply source patches in dependency order (01 = deletions, then build, source, docs).
$patchDir = Join-Path $patchesRoot 'source-patches'
$patches = Get-ChildItem -LiteralPath $patchDir -Filter '*.patch' | Sort-Object Name
foreach ($patch in $patches) {
  Write-Host "Applying $($patch.Name) ..."
  git apply --whitespace=nowarn $patch.FullName
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  git apply failed, retrying with --3way ..."
    git apply --3way --whitespace=nowarn $patch.FullName
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to apply $($patch.Name)"
    }
  }
}

if ($Commit) {
  git add -A
  git commit -m "build: apply fork patches on top of upstream/main"
}

Write-Host 'Patches applied.'
