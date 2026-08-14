using System.Diagnostics;
using System.Net.Http;

namespace KiWin.Utilities;

public static class InternetCheck
{
    private static readonly HttpClient Client = new()
    {
        Timeout = TimeSpan.FromSeconds(20),
    };

    static InternetCheck()
    {
        Client.DefaultRequestHeaders.UserAgent.ParseAdd(KiWin.Core.KiWinInfo.UserAgent);
    }

    public static bool HasInternet(int maxAttempts = 3, string url = "https://raventechnologiesgroup.com", int timeoutSeconds = 5)
    {
        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                Logger.Info($"Checking internet connectivity (attempt {attempt}/{maxAttempts})...");
                var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
                var resp = Client.GetAsync(url, cts.Token).GetAwaiter().GetResult();
                var status = (int)resp.StatusCode;
                Logger.Debug($"Internet check HTTP status: {status}");
                if (status is >= 200 and < 500)
                {
                    Logger.Info("Internet connectivity confirmed.");
                    resp.Dispose();
                    return true;
                }
                resp.Dispose();
            }
            catch (Exception e)
            {
                Logger.Warning($"Internet check failed: {e.Message}");
                if (attempt < maxAttempts)
                    Thread.Sleep(1000);
            }
        }
        return false;
    }
}
