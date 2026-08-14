using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatUnpinTaskbar
{
    public static void Main()
    {
        const string script = "unpin_taskbar_start.ps1";
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
        Logger.Info("Taskbar and Start pinned items removed.");
    }
}