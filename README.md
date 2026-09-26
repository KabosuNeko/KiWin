# KiWin

<p align="center">
  <img src="https://github.com/user-attachments/assets/05152cb8-bf18-49fd-a76f-2a236ffe43e7" alt="KiWin Logo" style="width: 192px" />
</p>
<p align="center">
  <a href="https://github.com/KabosuNeko/KiWin/releases"><img src="https://img.shields.io/github/v/release/KabosuNeko/KiWin?color=e0a93b&label=release" alt="GitHub release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/.NET%20Framework-4.8-e0a93b.svg" alt=".NET Framework 4.8" />
</p>

A Windows 11 debloat tool written in **C#/WPF**: one GUI that drives community-reviewed debloat scripts (**WinUtil**, **Win11Debloat**) alongside KiWin's own scripts. Debloat only, no visual or theme changes to Windows.

## Features

- **6 debloat steps** (toggle each in Advanced):
  1. Remove Microsoft Edge permanently
  2. Install your chosen browser (via **winget**)
  3. Debloat phase 1: **WinUtil** (Chris Titus Tech)
  4. Debloat phase 2: **Win11Debloat** (Raphire)
  5. Set Windows Update to security-only (undo with `undo-update-policy=true`)
  6. Unpin all Taskbar and Start items
- **Options** (Advanced, on by default): apply debloat to new user accounts (a second Win11Debloat pass in sysprep mode, so the Default profile and future accounts start debloated), block Device Companion Apps, block WPBT, remove OneDrive, remove preinstalled apps, remove Xbox/gaming apps
- **Browsers**: Waterfox, Helium, Firefox, Brave, LibreWolf
- **Presets**: Standard / Minimal, plus install-plan JSON import and export
- **Safety**: creates a System Restore point before running (best effort, with the 24h creation throttle overridden and a registry export fallback if it fails); validates Win11Debloat arguments so an imported plan cannot inject commands
- **CLI**: `headless`, `dry-run`, `config`, `skip-<step>-step`, `undo-update-policy`

## Requirements

- Windows 11
- **Administrator** rights (UAC prompt on launch)
- Internet (browser install, script downloads)

Defender: leave it on. KiWin only touches what you pick in the plan.

## Install

Download the latest **KiWin.exe** from [Releases](https://github.com/KabosuNeko/KiWin/releases) and run it. If SmartScreen warns because the file is unsigned, choose *More info → Run anyway*. On first run the app extracts its bundle to `%LOCALAPPDATA%\KiWin` and exits when the debloat finishes.

## Usage

```bash
KiWin.exe headless=true dry-run=true
KiWin.exe config=my-plan.json
KiWin.exe config=https://example.com/plan.json
KiWin.exe skip-configure-updates-step=true
KiWin.exe undo-update-policy=true
```

| Flag | Type | Description |
|------|------|-------------|
| `headless` | bool | Run without the GUI |
| `dry-run` | bool | Preview only, no system changes |
| `config` | path/URL | Use an existing plan JSON from a path or URL |
| `developer-mode` | bool | Hide the install overlay |
| `undo-update-policy` | bool | Remove the security-only update policy |
| `skip-<step>-step` | bool | Skip a step (e.g. `skip-configure-updates-step`) |

## Data

| What | Where |
|------|-------|
| Extracted bundle and scripts | `%LOCALAPPDATA%\KiWin\appdata` |
| Install plan | `%LOCALAPPDATA%\KiWin\install_plan.json` |
| Log | `%LOCALAPPDATA%\KiWin\appdata\kiwin.log` |

## Build from source

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) to build (the app targets **.NET Framework 4.8**, preinstalled on Windows). The repo uses the `.slnx` solution format.

```bash
dotnet build KiWin.slnx -c Debug
dotnet run --project src/KiWin.App -c Debug
dotnet test tests/KiWin.Core.Tests/KiWin.Core.Tests.csproj
powershell -ExecutionPolicy Bypass -File build.ps1
powershell -ExecutionPolicy Bypass -File build.ps1 -Force
```

`build.ps1` downloads `winutil.ps1` and Win11Debloat (tag `2026.08.24`) into `external_scripts\`, disables WinUtil's Windows-feature installation, then embeds assets, scripts, presets and locales into a single `dist\KiWin.exe`. The patch is verified at build time: if upstream WinUtil changes so the patch target is not found exactly once, the build fails instead of shipping an unpatched script. Sources are recorded in `external_scripts\versions.json` with their SHA256; if present, downloads are skipped (`-Force` to refresh).

Signing (needs a certificate, otherwise SmartScreen still warns):
- Certificate in the Windows store: set `KIWIN_SIGN_THUMBPRINT`.
- PFX file: set `KIWIN_SIGN_PFX` (base64-encoded PFX) and `KIWIN_SIGN_PFX_PASSWORD`.
- On CI, add the same two secrets (`KIWIN_SIGN_PFX`, `KIWIN_SIGN_PFX_PASSWORD`) and releases are signed automatically.

## Credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil), Chris Titus Tech
- [Win11Debloat](https://github.com/Raphire/Win11Debloat), Raphire
- [FullWinUpdate-Disabler](https://github.com/DTLegit/FullWinUpdate-Disabler), DTLegit (idea for the security-only update policy)

## License

MIT
