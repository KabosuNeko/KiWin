using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatConfigureUpdates
{
    public static string GetProductName()
    {
        const string keyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        using var key = Microsoft.Win32.RegistryKey.OpenBaseKey(Microsoft.Win32.RegistryHive.LocalMachine, Microsoft.Win32.RegistryView.Registry64)
            .OpenSubKey(keyPath) ?? throw new InvalidOperationException($"Unable to open registry key {keyPath}");
        return key.GetValue("ProductName")?.ToString() ?? "";
    }

    public static void Main()
    {
        string productName;
        try
        {
            productName = GetProductName();
            Logger.Info($"Detected product name: {productName}");
        }
        catch (Exception e)
        {
            Logger.Error($"Failed to read Windows edition: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.windows_edition_failed", new() { ["error"] = e.Message }),
                false);
            throw;
        }
        var script = productName.Contains("Professional", StringComparison.OrdinalIgnoreCase)
            || productName.Contains("Pro", StringComparison.OrdinalIgnoreCase)
            || productName.Contains("Enterprise", StringComparison.OrdinalIgnoreCase)
            ? "update_policy_changer_pro.ps1"
            : "update_policy_changer.ps1";
        Logger.Info($"Executing PowerShell script: {script}");
        try
        {
            PowerShellHandler.RunScript(script);
            Logger.Info($"Successfully executed {script}");
        }
        catch (Exception e)
        {
            Logger.Error($"Failed to execute {script}: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.powershell_named_script_failed", new()
                {
                    ["script_name"] = script,
                    ["error"] = e.Message,
                }),
                false);
            throw;
        }
        Logger.Info("Windows update policy configured successfully.");
    }
}
