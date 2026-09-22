using System.Threading;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatConfigureUpdates
{
    public static void Main(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        DebloatExecuteKiWinScripts.RunScript("update_policy_changer.ps1", cancel, outputLine);
        Logger.Info("Windows update policy configured successfully.");
    }
}
