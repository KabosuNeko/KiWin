# KiWin

<p><br/></p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/05152cb8-bf18-49fd-a76f-2a236ffe43e7" alt="KiWin Logo" style="width: 192px" />
</p>
<p><br/></p>

**Windows without the suck.**

KiWin is a **Windows 11 debloat tool** that gets the job done in a few clicks — written in C#/WPF. Acting as a central management shell, it combines a clean GUI, installation planner, and config generator to run trusted debloat tools alongside its own custom scripts. **Pure Debloat: Focused solely on system optimization and bloatware removal—zero visual or theme modifications to Windows.**

## Features

- **5 debloat steps** (each can be toggled on/off in Advanced):
  1. Remove Microsoft Edge permanently
  2. Install your chosen browser (via **winget**, no extra setup)
  3. Debloat Windows phase 1 — **WinUtil** (Chris Titus Tech) with a curated tweak config (telemetry, OneDrive, Outlook, widgets, Xbox...)
  4. Debloat Windows phase 2 — **Win11Debloat** (Raphire) with privacy/debloat flags
  5. Configure Windows Update to security-only policy (undo with `undo-update-policy=true`)
- **WinUtil options** (Advanced, enabled by default): block **Device Companion Apps**, block **WPBT** (OEM firmware at boot)
- **Browsers**: Waterfox · Helium · Firefox · Brave · LibreWolf (winget IDs: `Waterfox.Waterfox`, `ImputNet.Helium`, `Mozilla.Firefox`, `Brave.Brave`, `LibreWolf.LibreWolf`)
- **Languages**: English / Tiếng Việt
- **Presets**: Standard (full) / Minimal — plus install-plan JSON import/export
- **CLI**: `headless`, `dry-run`, `config`, `skip-<step>-step`

## Requirements

- Windows 11
- **Administrator** rights (UAC prompt on launch)
- Internet connection (browser install, script downloads)

## Quick install (one-liner)

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/kiwin-install.ps1 | iex
```

Downloads the latest release bundle `KiWin.zip` from GitHub Releases, extracts it to `%LOCALAPPDATA%\KiWin` and launches the app (UAC prompt on start).

## Build from source

Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

```powershell
# Build & run (Debug)
dotnet build KiWin.slnx -c Debug
dotnet run --project src/KiWin.App -c Debug

# Full release bundle (downloads WinUtil + Win11Debloat, publishes to dist\)
powershell -ExecutionPolicy Bypass -File build.ps1
```

`build.ps1` downloads the latest `winutil.ps1` and Win11Debloat (tag `2026.07.11`) into `external_scripts\`, patches WinUtil for silent operation, and publishes `dist\KiWin.exe` (self-contained single-file). If `external_scripts\` already exists, downloads are skipped.

## Run

Run `KiWin.exe` (in `dist\`) as administrator. The `media/`, `locales/`, `presets/`, `debloat_scripts/`, `external_scripts/` folders must sit next to the executable.

## CLI

```
KiWin.exe headless=true dry-run=true
KiWin.exe config=my-plan.json
KiWin.exe skip-configure-updates-step=true
KiWin.exe undo-update-policy=true
```

| Flag | Type | Description |
|---|---|---|
| `headless` | bool | Run without GUI |
| `dry-run` | bool | Preview only; makes no system changes |
| `config` | path/URL | Use an existing plan JSON (or URL) |
| `developer-mode` | bool | Hide the install overlay |
| `undo-update-policy` | bool | Remove the security-only update policy (restore full Windows updates) |
| `skip-<step>-step` | bool | Skip a step (e.g. `skip-configure-updates-step`) |


## Third-party tools credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil) — Chris Titus Tech
- [Win11Debloat](https://github.com/Raphire/Win11Debloat) — Raphire
- [FullWinUpdate-Disabler](https://github.com/DTLegit/FullWinUpdate-Disabler) - DTLegit

## Disclaimer

KiWin modifies the registry, removes apps, and installs software on your system. Run `dry-run=true` to preview first, and test on a VM if in doubt. The author is not responsible for any damage.
