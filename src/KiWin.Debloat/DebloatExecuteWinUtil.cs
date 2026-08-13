using KiWin.Core;

namespace KiWin.Debloat;

public static class DebloatExecuteWinUtil
{
    public static void Main(string? configPath = null)
    {
        DebloatExecuteExternalScripts.RunWinUtil(configPath);
    }
}
