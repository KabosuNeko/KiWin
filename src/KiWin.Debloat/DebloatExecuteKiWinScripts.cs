using System.Threading;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatExecuteKiWinScripts
{
    public static void RunScript(string script, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        Logger.Info($"Executing PowerShell script: {script}");
        try
        {
            PowerShellHandler.RunScript(script, cancel: cancel, outputLine: outputLine);
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

    public static void RunEdgeRemoval(CancellationToken cancel = default, Action<string>? outputLine = null)
        => RunScript("edge_vanisher.ps1", cancel, outputLine);

    public static void RunOutlookOneDriveRemoval(CancellationToken cancel = default, Action<string>? outputLine = null)
        => RunScript("uninstall_oo.ps1", cancel, outputLine);
}
