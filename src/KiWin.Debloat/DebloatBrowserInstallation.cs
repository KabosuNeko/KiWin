using System.Diagnostics;
using System.Net;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatBrowserInstallation
{
    private const string VcRedistId = "Microsoft.VCRedist.2015+.x64";
    private const string VcRedistDisplayName = "Microsoft Visual C++ 2015-2022 Redistributable";
    private const string VcRedistInstallerUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe";

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
            RunWingetInstall(packageId, displayName);
        }
        catch (Exception e)
        {
            var exitCode = e is InvalidOperationException ioe && int.TryParse(ioe.Message, out var rc) ? rc : 0;
            if (!ErrorDialog.Show(
                    Localization.T("errors.winget_browser_failed", new()
                    {
                        ["display_name"] = displayName,
                        ["exit_code"] = exitCode,
                    }),
                    allowContinue: true))
                throw;
        }
    }

    public static void InstallVcRedist()
    {
        try
        {
            RunWingetInstall(VcRedistId, VcRedistDisplayName);
            return;
        }
        catch (Exception e)
        {
            Logger.Warning($"winget failed for {VcRedistDisplayName} ({e.Message}); falling back to direct download.");
        }
        try
        {
            InstallVcRedistDirect();
        }
        catch (Exception e)
        {
            Logger.Error($"Direct install of {VcRedistDisplayName} failed: {e.Message}");
            if (!ErrorDialog.Show(
                    Localization.T("errors.winget_browser_error", new()
                    {
                        ["display_name"] = VcRedistDisplayName,
                        ["error"] = e.Message,
                    }),
                    allowContinue: true))
                throw;
        }
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

    private static void RunWingetInstall(string packageId, string displayName)
    {
        Logger.Info($"Installing via winget: {displayName} ({packageId})");
        var args = $"install -e --silent --source winget --id {packageId} --force " +
                   "--accept-package-agreements --accept-source-agreements";
        var (rc, stdout, stderr) = RunWinget(args);
        if (rc == 0)
        {
            Logger.Info($"Successfully installed {displayName}.");
            return;
        }
        Logger.Error($"winget exited with code {rc} for {packageId}\n{stdout}\n{stderr}");
        throw new InvalidOperationException(rc.ToString());
    }

    private static void InstallVcRedistDirect()
    {
        Logger.Info("Downloading VC++ Redistributable directly from aka.ms...");
        var installer = Path.Combine(Path.GetTempPath(), $"vc_redist_x64_{Guid.NewGuid():N}.exe");
        try
        {
            using (var client = new WebClient())
            {
                client.Headers.Add(HttpRequestHeader.UserAgent, "KiWin");
                client.DownloadFile(VcRedistInstallerUrl, installer);
            }
            Logger.Info($"Running {VcRedistDisplayName} installer silently...");
            var psi = new ProcessStartInfo(installer)
            {
                Arguments = "/install /quiet /norestart",
                UseShellExecute = true,
                CreateNoWindow = true,
            };
            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start installer");
            proc.WaitForExit();
            var rc = proc.ExitCode;
            if (rc is 0 or 3010 or 1638)
            {
                Logger.Info($"Successfully installed {VcRedistDisplayName} (exit {rc}).");
                return;
            }
            throw new InvalidOperationException($"vc_redist installer exited with code {rc}");
        }
        finally
        {
            try { if (File.Exists(installer)) File.Delete(installer); } catch { }
        }
    }

    private static (int ExitCode, string Stdout, string Stderr) RunWinget(string args)
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
        return (proc.ExitCode, stdout, stderr);
    }
}