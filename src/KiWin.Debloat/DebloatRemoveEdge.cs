using System.Threading;
using KiWin.Core;

namespace KiWin.Debloat;

public static class DebloatRemoveEdge
{
    public static void Main(CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        DebloatExecuteKiWinScripts.RunEdgeRemoval(cancel, outputLine);
    }
}
