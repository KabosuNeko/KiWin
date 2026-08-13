using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatExecuteKiWinScripts
{
    public static void RunScript(string script)
    {
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
    }

    public static void RunEdgeRemoval() => RunScript("edge_vanisher.ps1");

    public static void RunOutlookOneDriveRemoval() => RunScript("uninstall_oo.ps1");
}
