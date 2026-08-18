using System.Threading;
using KiWin.Core;

namespace KiWin.Debloat;

public static class DebloatExecuteWinUtil
{
    public static void Main(string? configPath = null, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        DebloatExecuteExternalScripts.RunWinUtil(configPath, cancel, outputLine);
    }
}
