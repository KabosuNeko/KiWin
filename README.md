# KiWin

Debloat Windows 11 with one PowerShell command. No installer, no exe, no GUI.

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 | iex
```

The script self-elevates (UAC), asks for a browser, shows the plan, and waits for `YES` before changing anything. It does not touch themes or colors; the few interface changes it makes are listed below.

## What it does

1. Creates a System Restore point. If that fails, it asks before going on (`-Yes` continues with a warning)
2. Installs the browser you pick via **winget**
3. Removes Microsoft Edge and blocks its reinstall (keeps WebView2 and Edge profile data). Runs only when step 2 installs a browser, so you are never left without one
4. Applies **WinUtil** (Chris Titus Tech) tweaks that Win11Debloat does not cover: activity history, consumer features, background apps, telemetry, WPBT, services set to manual, OneDrive removal (skipped while an account is signed in), Home and Gallery, Windows AI, reserved storage
5. Runs **Win11Debloat** (Raphire), plus a second pass so new user accounts start debloated. Win11Debloat backs up the registry keys it changes
6. Keeps Windows on its current feature release and delays cumulative updates by 4 days (undo below). Cumulative updates still install, with both security and non-security fixes. A weekly task drops the pin 60 days before the release's end of servicing, so Windows can move to a supported release
7. Unpins all Taskbar items (and Start items, if Win11Debloat was skipped)

Interface changes: the classic right-click menu, File Explorer opens to This PC, Start's Recommended section and Widgets are turned off, and the Sticky Keys shortcut prompt is disabled.

Browsers: Waterfox, Helium, Firefox, Brave, LibreWolf.

Each step has a time limit, so a hung step is stopped instead of blocking the run.

## Options

Pass flags by running the file, or a scriptblock from the URL:

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 -OutFile KiWin.ps1
powershell -ExecutionPolicy Bypass -File .\KiWin.ps1 -DryRun -Browser Firefox

& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1'))) -Skip edge,updates
```

| Flag | Description |
|------|-------------|
| `-Browser <name>` | Browser to install; default `None` (Edge is then kept) |
| `-Skip <list>` | Skip steps: `restore-point, edge, browser, winutil, win11debloat, updates, unpin, new-users` |
| `-DryRun` | Download and print the plan, change nothing |
| `-Latest` | Use the newest WinUtil and Win11Debloat releases instead of the tested ones |
| `-Yes` | Skip the `YES` confirmations |

## Upstream versions

By default KiWin downloads the WinUtil and Win11Debloat releases it was tested with and checks their SHA-256. With `-Latest` it takes the newest releases: Win11Debloat is checked against its published `SHA256SUMS`, WinUtil is not checked.

## Undo

Update policy (restores the values you had before KiWin):

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/Assets/debloat_scripts/undo_update_policy.ps1 | iex
```

Driver downloads, if you ran a KiWin version from before this change (it applied WinUtil's Razer block, which turned off automatic drivers for every device; KiWin warns when it finds it):

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/Assets/debloat_scripts/undo_razer_block.ps1 | iex
```

Edge: the steps to unlock its folder are at the top of `Assets\debloat_scripts\edge_vanisher.ps1`; then install Edge from Microsoft's site.

## Requirements

- Windows 11
- Administrator rights (the script prompts)
- Internet (winget, WinUtil, Win11Debloat, helper scripts when run through `iex`)

## Data

| What | Where |
|------|-------|
| Logs | `%LOCALAPPDATA%\KiWin\Logs` |
| Downloaded scripts | `%LOCALAPPDATA%\KiWinScript` |
| Start layout backup | `start2.bin.kiwin.bak` next to each replaced `start2.bin` |
| Update policy state and original values | `C:\ProgramData\KiWin\UpdatePolicy` |

## Files

- `KiWin.ps1`: the entry point
- `Assets\debloat_scripts\`: Edge removal, update policy and its undo, taskbar unpin, restore point, Razer block undo

The script uses the raw URL of this repo to fetch the helper scripts when it is not on disk. If you fork it, update `$RawBase` at the top of `KiWin.ps1`.

## Credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil), Chris Titus Tech
- [Win11Debloat](https://github.com/Raphire/Win11Debloat), Raphire
- [FullWinUpdate-Disabler](https://github.com/DTLegit/FullWinUpdate-Disabler), DTLegit (idea for the update deferral policy)

## License

MIT
