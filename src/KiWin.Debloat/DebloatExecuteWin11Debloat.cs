using System.Threading;

namespace KiWin.Debloat;

public static class DebloatExecuteWin11Debloat
{
    public static void Main(string? configPath = null, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        DebloatExecuteExternalScripts.RunWin11Debloat(configPath, cancel, outputLine);
    }
}
