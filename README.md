# KiWin

<p align="center">
  <img src="https://github.com/user-attachments/assets/05152cb8-bf18-49fd-a76f-2a236ffe43e7" alt="KiWin Logo" style="width: 192px" />
</p>
<p align="center">
  <a href="https://github.com/KabosuNeko/KiWin/releases"><img src="https://img.shields.io/github/v/release/KabosuNeko/KiWin?color=e0a93b&label=release" alt="GitHub release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/.NET%20Framework-4.8-e0a93b.svg" alt=".NET Framework 4.8" />
</p>

**Windows without the suck.**

Công cụ debloat Windows 11 viết bằng **C#/WPF**: một GUI duy nhất điều phối các script debloat đã được cộng đồng kiểm chứng (**WinUtil**, **Win11Debloat**) cùng script riêng của KiWin. Chỉ debloat, không đổi giao diện hay theme của Windows.

## Tính năng

- **6 bước debloat** (bật/tắt từng bước trong Advanced):
  1. Gỡ Microsoft Edge vĩnh viễn
  2. Cài trình duyệt bạn chọn (qua **winget**)
  3. Debloat giai đoạn 1: **WinUtil** (Chris Titus Tech)
  4. Debloat giai đoạn 2: **Win11Debloat** (Raphire)
  5. Đặt Windows Update về chỉ cập nhật bảo mật (hoàn tác bằng `undo-update-policy=true`)
  6. Gỡ ghim toàn bộ Taskbar và Start
- **Tuỳ chọn** (Advanced, mặc định bật): chặn Device Companion Apps, chặn WPBT, gỡ OneDrive, gỡ ứng dụng cài sẵn, gỡ ứng dụng Xbox/game
- **Trình duyệt**: Waterfox, Helium, Firefox, Brave, LibreWolf
- **Preset**: Standard / Minimal, kèm nhập và xuất install plan JSON
- **An toàn**: tạo System Restore point trước khi chạy (best effort); validate tham số Win11Debloat, nên plan JSON nhập từ ngoài không chèn được lệnh
- **CLI**: `headless`, `dry-run`, `config`, `skip-<step>-step`, `undo-update-policy`

## Yêu cầu

- Windows 11
- Quyền **Administrator** (UAC khi chạy)
- Internet (cài trình duyệt, tải script)

Defender: để nguyên. KiWin chỉ đụng đúng những gì bạn chọn trong plan.

## Cài đặt

Tải **KiWin.exe** mới nhất từ [Releases](https://github.com/KabosuNeko/KiWin/releases) rồi chạy. Nếu SmartScreen cảnh báo do file chưa ký, chọn *More info → Run anyway*. Lần chạy đầu, app tự giải nén bundle vào `%LOCALAPPDATA%\KiWin` và tự thoát khi debloat xong.

## Cách dùng

```bash
KiWin.exe headless=true dry-run=true
KiWin.exe config=my-plan.json
KiWin.exe config=https://example.com/plan.json
KiWin.exe skip-configure-updates-step=true
KiWin.exe undo-update-policy=true
```

| Flag | Kiểu | Mô tả |
|------|------|-------|
| `headless` | bool | Chạy không GUI |
| `dry-run` | bool | Chỉ xem trước, không đổi hệ thống |
| `config` | path/URL | Dùng plan JSON có sẵn (đường dẫn hoặc URL) |
| `developer-mode` | bool | Ẩn overlay cài đặt |
| `undo-update-policy` | bool | Gỡ chính sách chỉ cập nhật bảo mật |
| `skip-<step>-step` | bool | Bỏ qua một bước (vd `skip-configure-updates-step`) |

## Data

| Gì | Ở đâu |
|----|-------|
| Bundle đã giải nén + script | `%LOCALAPPDATA%\KiWin\appdata` |
| Install plan | `%LOCALAPPDATA%\KiWin\install_plan.json` |
| Log | `%LOCALAPPDATA%\KiWin\appdata\kiwin.log` |

## Build từ source

Cần [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) để build (app target **.NET Framework 4.8**, có sẵn trên Windows). Repo dùng định dạng `.slnx`.

```bash
dotnet build KiWin.slnx -c Debug
dotnet run --project src/KiWin.App -c Debug
dotnet test tests/KiWin.Core.Tests/KiWin.Core.Tests.csproj
powershell -ExecutionPolicy Bypass -File build.ps1
powershell -ExecutionPolicy Bypass -File build.ps1 -Force
```

`build.ps1` tải `winutil.ps1` và Win11Debloat (tag `2026.08.24`) vào `external_scripts\`, tắt bước cài Windows feature của WinUtil, rồi nhúng assets, scripts, presets và locales vào một file `dist\KiWin.exe` duy nhất. Patch được kiểm chứng lúc build: nếu upstream WinUtil đổi khiến target không còn khớp đúng một lần, build **fail** thay vì ship script chưa patch. Nguồn tải được ghi vào `external_scripts\versions.json` kèm SHA256; nếu đã có thì bỏ qua tải (`-Force` để làm mới). Muốn ký số, đặt `KIWIN_SIGN_THUMBPRINT` trước khi build.

## Credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil), Chris Titus Tech
- [Win11Debloat](https://github.com/Raphire/Win11Debloat), Raphire
- [FullWinUpdate-Disabler](https://github.com/DTLegit/FullWinUpdate-Disabler), DTLegit (ý tưởng cho chính sách chỉ cập nhật bảo mật)

## License

MIT
