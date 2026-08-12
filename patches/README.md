# Patch system

This fork is maintained as `upstream/main + patches`:

- `dev` branch = a clean upstream `main` with `patches/` applied.
- `main` branch = the applied release state; it also carries `patches/` so the
  patch set is versioned and can be restored after a reset.

## Layout

```
patches/
  features/              pure new files, copied verbatim (cannot conflict)
  source-patches/        git diffs against upstream/main, applied with `git apply`
  .gitattributes         keeps .patch files LF / byte-identical and *.sh at LF
    01-remove-upstream-only.patch   docs / Azure Pipelines / CodeQL / baselines
    02-build-and-deps.patch         main.gyp, gyp_library.py, config.gypi, .gitignore, .gitmodules
    03-explorer-command.patch       src/explorer_command.cc
    04-docs-and-notice.patch        README.md, NOTICE
  apply-patches.ps1 / .sh
  sync-upstream.ps1 / .sh
```

## Sync upstream (Windows)

```powershell
git remote add upstream https://github.com/microsoft/vscode-explorer-command.git  # once
git switch -c dev upstream/main                                                   # once
powershell -ExecutionPolicy Bypass -File patches\sync-upstream.ps1
```

The sync script: fetches upstream, resets `dev` to `upstream/main`, restores
`patches/` from `main`, applies everything, and commits. Add `-Push` to force-push
`origin/dev`.

## Apply manually

```powershell
git reset --hard upstream/main
git checkout main -- patches
powershell -ExecutionPolicy Bypass -File patches\apply-patches.ps1
```

## Regenerate a source patch

```powershell
git diff upstream/main main -- <file> > patches\source-patches\NN-name.patch
```

Keep the LF line endings and no BOM (PowerShell 7 `>` does this by default).

## Troubleshooting

- `git apply` context shifts: the scripts fall back to `git apply --3way`, which
  uses the blob SHAs in the patch and usually succeeds.
- `deps/wil` submodule: the apply scripts remove it because the fork uses vcpkg;
  if a checkout refuses to switch branches due to the submodule, run
  `git submodule deinit -f deps/wil` first.
- Verify a clean reproduction: after applying on a fresh upstream checkout,
  `git diff main --stat` should be empty (both branches have identical trees).
