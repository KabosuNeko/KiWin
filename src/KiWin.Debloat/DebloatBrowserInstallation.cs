using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatBrowserInstallation
{
    private const string VcRedistId = "Microsoft.VCRedist.2015+.x64";
    private const string VcRedistDisplayName = "Microsoft Visual C++ 2015-2022 Redistributable";
    private const string VcRedistInstallerUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe";
    private static readonly TimeSpan WingetTimeout = TimeSpan.FromMinutes(10);

    public static void EnsureWinget(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        try
        {
            RunWinget("--version", cancel, outputLine: outputLine);
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

    public static void InstallWingetPackage(string packageId, string displayName,
        CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        Logger.Info($"Installing via winget: {displayName} ({packageId})");
        try
        {
            RunWingetInstall(packageId, displayName, cancel, outputLine);
        }
        catch (Exception e)
        {
            if (cancel.IsCancellationRequested) throw;
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

    public static void InstallVcRedist(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        if (IsWingetPackageInstalled(VcRedistId, cancel, outputLine))
        {
            Logger.Info($"{VcRedistDisplayName} is already installed; skipping.");
            outputLine?.Invoke($"[skip] {VcRedistDisplayName} is already installed.");
            return;
        }
        try
        {
            RunWingetInstall(VcRedistId, VcRedistDisplayName, cancel, outputLine);
            return;
        }
        catch (Exception e)
        {
            if (cancel.IsCancellationRequested) throw;
            Logger.Warning($"winget failed for {VcRedistDisplayName} ({e.Message}); falling back to direct download.");
        }
        try
        {
            InstallVcRedistDirect(cancel);
        }
        catch (Exception e)
        {
            if (cancel.IsCancellationRequested) throw;
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

    public static void InstallBrowser(string packageId, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        var displayName = "browser";
        var browser = StepCatalog.BrowserOptions.FirstOrDefault(b => b.PackageId == packageId);
        if (browser is not null)
            displayName = browser.Name;
        if (IsWingetPackageInstalled(packageId, cancel, outputLine))
        {
            Logger.Info($"{displayName} is already installed; skipping.");
            outputLine?.Invoke($"[skip] {displayName} is already installed.");
            return;
        }
        InstallWingetPackage(packageId, displayName, cancel, outputLine);
    }

    public static void Main(string? selectedBrowserPackage, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        var packageId = (selectedBrowserPackage ?? "").Trim();
        if (packageId.Length == 0)
            throw new InvalidOperationException(Localization.T("errors.browser_metadata_missing"));
        Logger.Info($"Browser selected: {packageId}");
        EnsureWinget(cancel, outputLine);
        InstallVcRedist(cancel, outputLine);
        InstallBrowser(packageId, cancel, outputLine);
    }

    private static bool IsWingetPackageInstalled(string packageId, CancellationToken cancel = default,
        Action<string>? outputLine = null)
    {
        var (rc, stdout, _) = RunWinget(
            $"list -e --id {packageId} --source winget --accept-source-agreements",
            cancel, outputLine: outputLine);
        if (rc == 0 && stdout.Contains(packageId, StringComparison.OrdinalIgnoreCase))
        {
            Logger.Info($"winget reports {packageId} as installed.");
            return true;
        }
        return false;
    }

    private static void RunWingetInstall(string packageId, string displayName,
        CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        Logger.Info($"Installing via winget: {displayName} ({packageId})");
        var args = $"install -e --silent --source winget --id {packageId} " +
                   "--accept-package-agreements --accept-source-agreements";
        var (rc, stdout, stderr) = RunWinget(args, cancel, outputLine: outputLine);
        if (rc == 0)
        {
            Logger.Info($"Successfully installed {displayName}.");
            return;
        }
        Logger.Error($"winget exited with code {rc} for {packageId}\n{stdout}\n{stderr}");
        throw new InvalidOperationException(rc.ToString());
    }

    private static void InstallVcRedistDirect(CancellationToken cancel = default)
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
            cancel.ThrowIfCancellationRequested();
            Logger.Info($"Running {VcRedistDisplayName} installer silently...");
            var psi = new ProcessStartInfo(installer)
            {
                Arguments = "/install /quiet /norestart",
                UseShellExecute = true,
                CreateNoWindow = true,
            };
            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start installer");
            while (!proc.WaitForExit(100))
            {
                if (cancel.IsCancellationRequested)
                {
                    try { proc.Kill(); } catch { }
                    throw new OperationCanceledException();
                }
            }
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

    private static (int ExitCode, string Stdout, string Stderr) RunWinget(string args,
        CancellationToken cancel = default, Action<string>? outputLine = null)
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
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stdout.AppendLine(e.Data);
            Logger.Info($"winget STDOUT: {e.Data}");
            try { outputLine?.Invoke(e.Data); } catch { }
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stderr.AppendLine(e.Data);
            Logger.Error($"winget STDERR: {e.Data}");
            try { outputLine?.Invoke(e.Data); } catch { }
        };
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        var timedOut = false;
        var sw = Stopwatch.StartNew();
        while (!proc.WaitForExit(100))
        {
            if (cancel.IsCancellationRequested)
            {
                Logger.Warning("Killing winget due to user cancellation.");
                try { KillProcessTree(proc); } catch { }
                throw new OperationCanceledException();
            }
            if (sw.Elapsed > WingetTimeout)
            {
                timedOut = true;
                Logger.Warning($"Killing winget due to timeout ({WingetTimeout}).");
                try { KillProcessTree(proc); } catch { }
            }
        }
        proc.WaitForExit();
        if (timedOut)
            throw new InvalidOperationException($"winget timed out after {WingetTimeout}");
        return (proc.ExitCode, stdout.ToString(), stderr.ToString());
    }

    private static void KillProcessTree(Process process)
    {
        try
        {
            var startInfo = new ProcessStartInfo("taskkill", $"/F /T /PID {process.Id}")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var killer = Process.Start(startInfo);
            killer?.WaitForExit(5000);
        }
        catch
        {
            try { process.Kill(); } catch { }
        }
    }
}