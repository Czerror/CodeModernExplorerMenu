# Rebuilds dev = upstream/main + patches and commits the result.
#
# Requires: an `upstream` remote pointing at microsoft/vscode-explorer-command
# and a local `main` branch that contains the latest `patches/` directory.
#
# Usage: powershell -ExecutionPolicy Bypass -File patches\sync-upstream.ps1 [-Push]
param(
  [switch]$Push
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

git fetch upstream
if ($LASTEXITCODE -ne 0) { throw 'git fetch upstream failed' }

git switch dev
if ($LASTEXITCODE -ne 0) { throw 'branch dev not found; create it once: git switch -c dev upstream/main' }

git reset --hard upstream/main
if ($LASTEXITCODE -ne 0) { throw 'git reset failed' }

# The reset removed patches/; restore the latest copy from the release branch.
git checkout main -- patches

# Apply all fork patches.
& (Join-Path $repoRoot 'patches\apply-patches.ps1')

git add -A
$upstreamSha = git rev-parse --short upstream/main
git commit -m "sync: rebase fork patches on upstream/main ($upstreamSha)"

if ($Push) {
  git push --force origin dev
}

Write-Host "dev is now synced with upstream/main ($upstreamSha)."
