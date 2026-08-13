using Microsoft.Win32;

namespace KiWin.Utilities;

public static class WindowsCheck
{
    private static string ReadRegistryValue(string name)
    {
        const string keyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        using var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
            .OpenSubKey(keyPath) ?? throw new InvalidOperationException($"Unable to open registry key {keyPath}");
        var val = key.GetValue(name);
        if (val is null) throw new InvalidOperationException($"Unable to read registry value {name}");
        return val.ToString() ?? "";
    }

    public static string CheckWindows11HomeOrPro()
    {
        string productName, buildStr;
        int buildNum;
        try
        {
            productName = ReadRegistryValue("ProductName");
            buildStr = ReadRegistryValue("CurrentBuildNumber");
            buildNum = int.Parse(buildStr);
        }
        catch (Exception e)
        {
            Logger.Exception("Unable to read Windows version", e);
            ErrorDialog.Show(KiWin.Core.Localization.T("errors.windows_version_failed"), false);
            throw;
        }
        var isWin11 = productName.StartsWith("Windows 11", StringComparison.OrdinalIgnoreCase)
            || (productName.StartsWith("Windows 10", StringComparison.OrdinalIgnoreCase) && buildNum >= 22000);
        if (!isWin11)
        {
            var message = KiWin.Core.Localization.T("errors.incompatible_windows_version",
                new() { ["product_name"] = productName, ["build_num"] = buildNum });
            ErrorDialog.Show(message, false);
            throw new InvalidOperationException(message);
        }
        Logger.Info($"Detected OS: {productName} (build {buildNum})");
        return productName;
    }
}
