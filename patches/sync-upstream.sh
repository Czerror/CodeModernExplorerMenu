#!/usr/bin/env bash
# Rebuilds dev = upstream/main + patches and commits the result.
# Usage: bash patches/sync-upstream.sh [--push]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

git fetch upstream
git switch dev
git reset --hard upstream/main
git checkout main -- patches
bash patches/apply-patches.sh
git add -A
upstream_sha="$(git rev-parse --short upstream/main)"
git commit -m "sync: rebase fork patches on upstream/main ($upstream_sha)"

if [ "${1:-}" = "--push" ]; then
  git push --force origin dev
fi

echo "dev is now synced with upstream/main ($upstream_sha)."
