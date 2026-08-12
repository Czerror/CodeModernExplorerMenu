# Code Modern Explorer Menu
An MSI package that adds the Windows 11 Modern Explorer menu for Microsoft Visual Studio Code.
  
> [!NOTE]
> Please restart Windows Explorer after installation.
> 
> Installation requires admin rights and accepting UAC prompt to temporarily enable Developer Mode if required and restore its initial status after installation.

> [!CAUTION]
> AV may flag this as a virus due to the lack of a signature and self-elevation.

## Requirements:
- Windows 11+
- VSCode installed
- Admin rights

## Features:
- does not interfere with the classic menu
- does not interfere with the original VSCode Insiders menu
- should not interfere when VSCode stable introduces the menu
- works with both system and user installation locations
- support the case when VSCode runs as Administrator, thanks to  [ArcticLampyrid](https://github.com/microsoft/vscode-explorer-command/pull/17)
- Also works for Devices and drives, thanks to [AndromedaMelody](https://github.com/microsoft/vscode-explorer-command/pull/16)
- Future VSCode updates won’t break the menu, thanks to [huutaiii](https://github.com/huutaiii/vscode-explorer-command)

## Project changes:
- replace Azure DevOps with GitHub Actions
- removed C++ dependencies from the repository
- added vcpkg package manager

## Development (patch system)

This fork is maintained as a patch system on top of
[microsoft/vscode-explorer-command](https://github.com/microsoft/vscode-explorer-command):

- `dev` branch = upstream `main` + `patches/` (reapplied by `patches/apply-patches.ps1`)
- `main` branch = the applied release state (also contains `patches/` for reproducibility)
- To sync upstream changes: run `patches/sync-upstream.ps1`

Notes:
- The menu title is read from `Software\Classes\CodeModernExplorerMenu` (stable) /
  `CodeInsidersModernExplorerMenu` (insiders) in both `HKCU` and `HKLM`; if missing,
  the DLL falls back to `使用 VSCode 编辑` instead of English.
- The custom menu uses its own verb ids (`OpenWithCodeModernExplorerMenu` /
  `OpenWithCodeInsidersModernExplorerMenu`) so VSCode's official `OpenWithCode` menu
  does not override it after VSCode updates.

## Quick register (no MSI)

For a portable VSCode (e.g. `D:\App\VSCode`), register the context menu directly
from the official files already inside the portable package (`appx\code_x64.appx`
and `appx\code_explorer_command_x64.dll`):

Copy `scripts\register-menu.ps1` and `scripts\register-menu.cmd` into the portable
VSCode root (the folder that contains `Code.exe`), then double-click
`register-menu.cmd`. A small GUI opens with two buttons: **Register menu** and
**Delete menu**. Only the script's own directory is searched for `Code.exe`; if it
is missing, the GUI asks you to place the script in the VSCode portable root.
Use `-VSCodePath` to override the root.

It copies the official appx files into `<root>\<versioned-folder>\appx`
(the layout the official shell extension expects), registers the Microsoft-signed
sparse package (no Developer Mode needed), writes the Chinese title into
`HKCU`/`HKLM`, and removes the old custom registration from this repository so the
menus do not collide. Use `-DryRun` to preview and `-RestartExplorer` to refresh the
menu immediately.
