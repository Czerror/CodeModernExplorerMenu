#!/usr/bin/env bash
# Applies the fork patches onto a clean upstream/main checkout.
# Usage (from repo root, after `git reset --hard upstream/main`):
#   bash patches/apply-patches.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# 1. Remove the deps/wil submodule (the fork uses vcpkg instead).
git submodule deinit -f deps/wil 2>/dev/null || true
rm -rf deps/wil
git rm -q --cached deps/wil 2>/dev/null || true

# 2. Copy feature files (pure new files, cannot conflict).
features=(
  '.gitattributes'
  '.editorconfig'
  '.github/workflows/build-win.yml'
  'AppxBlockMap.xml'
  '[Content_Types].xml'
  'build-msi.ps1'
  'msi/RunOnInstall.ps1'
  'msi/RunOnUninstall.ps1'
  'scripts/generate_pkg.py'
  'scripts/check-title.ps1'
  'template/AppxManifest.xml'
  'vcpkg.json'
)
for rel in "${features[@]}"; do
  mkdir -p "$(dirname "$rel")"
  cp "patches/features/$rel" "$rel"
done

# 3. Apply source patches in dependency order.
for patch in patches/source-patches/*.patch; do
  echo "Applying $(basename "$patch") ..."
  if ! git apply --whitespace=nowarn --ignore-whitespace "$patch"; then
    echo "  git apply failed, retrying with --3way ..."
    git apply --3way --whitespace=nowarn --ignore-whitespace "$patch"
  fi
done

echo 'Patches applied.'
