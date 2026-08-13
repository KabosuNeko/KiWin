using System.Diagnostics;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatBrowserInstallation
{
    public static void EnsureWinget()
    {
        try
        {
            RunWinget("--version");
            Logger.Info("winget is available.");
        }
        catch (Exception e)
        {
            Logger.Error($"winget not found or failed: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.winget_install_failed", new() { ["error"] = e.Message }),
                false);
            throw;
        }
    }

    public static void InstallWingetPackage(string packageId, string displayName)
    {
        Logger.Info($"Installing via winget: {displayName} ({packageId})");
        try
        {
            var psi = new ProcessStartInfo("winget")
            {
                Arguments = $"install -e --silent --id {packageId} --accept-package-agreements --accept-source-agreements",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start winget");
            var stdout = proc.StandardOutput.ReadToEnd();
            var stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit();
            var rc = proc.ExitCode;
            if (rc == 0)
            {
                Logger.Info($"Successfully installed {displayName}.");
                return;
            }
            Logger.Error($"winget exited with code {rc} for {packageId}\n{stdout}\n{stderr}");
            if (!ErrorDialog.Show(
                    Localization.T("errors.winget_browser_failed", new()
                    {
                        ["display_name"] = displayName,
                        ["exit_code"] = rc,
                    }),
                    allowContinue: true))
                throw new InvalidOperationException("winget install aborted.");
        }
        catch (Exception e) when (e is not InvalidOperationException)
        {
            Logger.Error($"Unexpected error installing {packageId}: {e.Message}");
            if (!ErrorDialog.Show(
                    Localization.T("errors.winget_browser_error", new()
                    {
                        ["display_name"] = displayName,
                        ["error"] = e.Message,
                    }),
                    allowContinue: true))
                throw;
        }
    }

    public static void InstallVcRedist()
    {
        InstallWingetPackage("Microsoft.VCRedist.2015+.x64", "Microsoft Visual C++ 2015-2022 Redistributable");
    }

    public static void InstallBrowser(string packageId)
    {
        var displayName = "browser";
        var browser = StepCatalog.BrowserOptions.FirstOrDefault(b => b.PackageId == packageId);
        if (browser is not null)
            displayName = browser.Name;
        InstallWingetPackage(packageId, displayName);
    }

    public static void Main(string? selectedBrowserPackage)
    {
        var packageId = (selectedBrowserPackage ?? "").Trim();
        if (packageId.Length == 0)
            throw new InvalidOperationException(Localization.T("errors.browser_metadata_missing"));
        Logger.Info($"Browser selected: {packageId}");
        EnsureWinget();
        InstallVcRedist();
        InstallBrowser(packageId);
    }

    private static void RunWinget(string args)
    {
        var psi = new ProcessStartInfo("winget")
        {
            Arguments = args,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start winget");
        var stdout = proc.StandardOutput.ReadToEnd();
        var stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit();
        if (proc.ExitCode != 0)
        {
            Logger.Error($"winget {args} exited with code {proc.ExitCode}\n{stdout}\n{stderr}");
            throw new InvalidOperationException($"winget exited with code {proc.ExitCode}");
        }
    }
}