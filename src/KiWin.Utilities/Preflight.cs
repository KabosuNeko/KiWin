using KiWin.Core;

namespace KiWin.Utilities;

public static class PreChecks
{
    public static bool CheckTempWritable()
    {
        var tempRoot = Path.GetTempPath();
        var kiwinDir = Path.Combine(tempRoot, "kiwin");
        try
        {
            Directory.CreateDirectory(kiwinDir);
            var testPath = Path.Combine(kiwinDir, $"kiwin_write_{Path.GetRandomFileName()}");
            File.WriteAllText(testPath, "test");
            try
            {
                File.Delete(testPath);
            }
            catch
            {
                // ignore
            }
            return true;
        }
        catch (Exception e)
        {
            Logger.Error($"Temp dir check failed: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.temp_unwritable", new() { ["kiwin_dir"] = kiwinDir }),
                allowContinue: true);
            return false;
        }
    }

    public static void Run()
    {
        WindowsCheck.CheckWindows11HomeOrPro();
        if (!CheckTempWritable())
            throw new InvalidOperationException("Temp directory is not writable.");
    }
}

public static class Preflight
{
    public static (bool InternetAvailable, bool Relaunched) RunConfigurationPreflight()
    {
        if (Environment.GetEnvironmentVariable("KIWIN_DRY_RUN") == "1")
        {
            return (InternetCheck.HasInternet(), false);
        }
        if (!AdminHelper.IsAdmin())
        {
            AdminHelper.RunAsAdmin();
            return (false, true);
        }
        PreChecks.Run();
        return (InternetCheck.HasInternet(), false);
    }
}
