# KiWin

Debloat Windows 11 with one PowerShell command. No installer, no exe, no GUI.

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 | iex
```

The script self-elevates (UAC), asks for a browser, shows the plan, and waits for `YES` before changing anything. Debloat only: no visual or theme changes.

## What it does

1. Creates a System Restore point (best effort; falls back to exporting HKLM/HKCU)
2. Removes Microsoft Edge permanently (keeps WebView2)
3. Installs the browser you pick via **winget**
4. Applies **WinUtil** (Chris Titus Tech) tweaks
5. Runs **Win11Debloat** (Raphire), plus a second pass so new user accounts start debloated
6. Sets Windows Update to security-only (undo below)
7. Unpins all Taskbar and Start items

Browsers: Waterfox, Helium, Firefox, Brave, LibreWolf.

## Options

Pass flags by running the file, or a scriptblock from the URL:

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 -OutFile KiWin.ps1
powershell -ExecutionPolicy Bypass -File .\KiWin.ps1 -DryRun -Browser Firefox

& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1'))) -Skip edge,updates
```

| Flag | Description |
|------|-------------|
| `-Browser <name>` | Browser to install; default `None` |
| `-Skip <list>` | Skip steps: `restore-point, edge, browser, winutil, win11debloat, updates, unpin, new-users` |
| `-DryRun` | Download and print the plan, change nothing |
| `-Refresh` | Re-download WinUtil, Win11Debloat, and the helper scripts instead of using the cache |
| `-Yes` | Skip the `YES` confirmation |

## Undo the update policy

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/Assets/debloat_scripts/undo_update_policy.ps1 | iex
```

## Requirements

- Windows 11
- Administrator rights (the script prompts)
- Internet (winget, WinUtil, Win11Debloat, helper scripts when run through `iex`)

## Data

| What | Where |
|------|-------|
| Downloaded scripts | `%LOCALAPPDATA%\KiWinScript` |
| Registry fallback export | `%LOCALAPPDATA%\KiWin\RegBackup-*` |
| Update policy state | `C:\ProgramData\KiWin\UpdatePolicy` |

## Files

- `KiWin.ps1`: the entry point
- `Assets\debloat_scripts\`: Edge removal, update policy, taskbar unpin, restore point, registry undo

The script uses the raw URL of this repo to fetch the helper scripts when it is not on disk. If you fork it, update `$RawBase` at the top of `KiWin.ps1`.

## Credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil), Chris Titus Tech
- [Win11Debloat](https://github.com/Raphire/Win11Debloat), Raphire
- [FullWinUpdate-Disabler](https://github.com/DTLegit/FullWinUpdate-Disabler), DTLegit (idea for the security-only update policy)

## License

MIT
