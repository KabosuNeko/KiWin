using System.Text;

namespace KiWin.Utilities;

public static class Logger
{
    private static readonly object Lock = new();
    private static StreamWriter? _fileWriter;
    private static bool _initialized;

    public static void Init(string? logFile = null, string? levelName = null)
    {
        lock (Lock)
        {
            if (_initialized) return;
            _initialized = true;
            try
            {
                logFile ??= Path.Combine(BasePath(), "kiwin.log");
                _fileWriter = new StreamWriter(logFile, append: true, Encoding.UTF8)
                {
                    AutoFlush = true,
                };
            }
            catch
            {
                try
                {
                    _fileWriter = new StreamWriter(Path.Combine(Path.GetTempPath(), "kiwin.log"), append: true, Encoding.UTF8)
                    {
                        AutoFlush = true,
                    };
                }
                catch
                {
                    _fileWriter = null;
                }
            }
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            {
                Error($"Unhandled exception: {e.ExceptionObject}");
            };
            Debug($"Logger initialized (file={logFile}, level={levelName ?? "DEBUG"})");
        }
    }

    public static string BasePath()
    {
        try
        {
            var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? AppDomain.CurrentDomain.BaseDirectory;
            return Path.GetDirectoryName(exe) ?? AppContext.BaseDirectory;
        }
        catch
        {
            return AppContext.BaseDirectory;
        }
    }

    private static string Format(string level, string message) =>
        $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {System.Diagnostics.Process.GetCurrentProcess().Id} {message}";

    private static void Write(string level, string message)
    {
        var line = Format(level, message);
        lock (Lock)
        {
            try { Console.WriteLine(line); } catch { }
            try { _fileWriter?.WriteLine(line); } catch { }
        }
    }

    public static void Debug(string message) => Write("DEBUG", message);
    public static void Info(string message) => Write("INFO", message);
    public static void Warning(string message) => Write("WARNING", message);
    public static void Error(string message) => Write("ERROR", message);
    public static void Exception(string message, Exception ex) =>
        Write("ERROR", $"{message}: {ex.Message}\n{ex}");
}
