using System.Threading;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatConfigureUpdates
{
    public static void Main(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        const string script = "update_policy_changer.ps1";
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
        Logger.Info("Windows update policy configured successfully.");
    }
}
