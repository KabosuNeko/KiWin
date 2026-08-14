using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace KiWin.Utilities;

public static class AdminHelper
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr ShellExecuteW(
        IntPtr hwnd,
        string lpOperation,
        string lpFile,
        string? lpParameters,
        string? lpDirectory,
        int nShowCmd);

    public static bool IsAdmin()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch (Exception e)
        {
            Logger.Error($"Admin check failed: {e.Message}");
            return false;
        }
    }

    public static void RunAsAdmin(IReadOnlyList<string>? extraArgs = null)
    {
        var executable = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? AppDomain.CurrentDomain.BaseDirectory;
        var args = new List<string>();
        if (extraArgs is not null)
            args.AddRange(extraArgs);
        var parameters = string.Join(" ", args.Select(a => $"\"{a}\""));
        var cwd = Environment.CurrentDirectory;
        Logger.Info($"Elevating: {executable} {parameters}");
        var result = ShellExecuteW(IntPtr.Zero, "runas", executable, string.IsNullOrEmpty(parameters) ? null : parameters, cwd, 1);
        if (result.ToInt64() <= 32)
        {
            var err = Marshal.GetLastWin32Error();
            Logger.Exception("Failed to relaunch with admin privileges", new System.ComponentModel.Win32Exception(err));
            ErrorDialog.Show(Localization_T("errors.admin_elevation_failed", new() { ["error"] = $"Win32 error {err}" }), false);
            Environment.Exit(1);
        }
    }

    public static bool EnsureAdmin()
    {
        if (!IsAdmin())
        {
            Logger.Warning("Administrator privileges required; relaunching with UAC prompt...");
            RunAsAdmin();
            return false;
        }
        Logger.Debug("Running with Administrator privileges.");
        return true;
    }

    private static string Localization_T(string key, Dictionary<string, object?>? parameters = null)
    {
        try
        {
            return KiWin.Core.Localization.T(key, parameters);
        }
        catch
        {
            return key;
        }
    }
}
