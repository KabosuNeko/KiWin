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
- Windows Defender: **leave it on.**

Most "debloat" tools make you switch off your antivirus (and sometimes half of Windows, and a rubber chicken, and your better judgment) before they'll run. It's a weird ritual — you're about to let a script modify your whole system, and the advice is to first remove the one thing still watching it. KiWin doesn't do that. It only touches what you actually pick in the plan, uses widely-reviewed community scripts (Chris Titus Tech WinUtil, Raphire Win11Debloat), and is perfectly happy with Defender fully armed. If your AV still gets jumpy about the PowerShell scripts, add a file exclusion instead of pulling the shield. Your machine, your call — but the shield staying up costs you nothing here.

## Quick start

1. Download **KiWin.exe** from the [Releases](https://github.com/KabosuNeko/KiWin/releases/latest) page.
2. Run it and accept the UAC prompt. If SmartScreen warns about an unsigned app, click *More info → Run anyway*.
3. Pick a preset, click **Start**. On first run the app extracts its embedded bundle to `%LOCALAPPDATA%\KiWin` automatically and shuts down when the debloat finishes.

## Build from source

Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

```powershell
# Build & run (Debug)
dotnet build KiWin.slnx -c Debug
dotnet run --project src/KiWin.App -c Debug

# Full release bundle
powershell -ExecutionPolicy Bypass -File build.ps1
```

`build.ps1` downloads the latest `winutil.ps1` and Win11Debloat (tag `2026.07.11`) into `external_scripts\`, patches WinUtil for silent operation, then embeds assets, scripts, presets and locales into the executable. The result is a **single self-contained `dist\KiWin.exe`** (~1.5 MB, .NET Framework 4.8); on first run it extracts its embedded bundle to `%LOCALAPPDATA%\KiWin`. If `external_scripts\` already exists, downloads are skipped.

## Run

Run `KiWin.exe` (in `dist\`) as administrator. Everything needed is embedded in the file — no other files or folders required. The app shows a fullscreen overlay while the debloat runs and exits automatically when done.

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
