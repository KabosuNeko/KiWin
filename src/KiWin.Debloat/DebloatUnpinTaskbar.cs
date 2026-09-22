using System.Threading;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatUnpinTaskbar
{
    public static void Main(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        DebloatExecuteKiWinScripts.RunScript("unpin_taskbar_start.ps1", cancel, outputLine);
        Logger.Info("Taskbar and Start pinned items removed.");
    }
}
