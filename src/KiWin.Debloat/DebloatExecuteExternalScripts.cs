using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.Debloat;

public static class DebloatExecuteExternalScripts
{
    public static string BasePath() => Logger.BasePath();

    private static bool IsUrl(string value)
    {
        try
        {
            var uri = new Uri(value);
            return uri.Scheme is "http" or "https" && !string.IsNullOrEmpty(uri.Host);
        }
        catch
        {
            return false;
        }
    }

    private static string DownloadConfig(string url)
    {
        Logger.Info($"Downloading config from: {url}");
        using var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd(KiWinInfo.UserAgent);
        var data = client.GetByteArrayAsync(url).GetAwaiter().GetResult();
        try
        {
            JsonNode.Parse(data);
        }
        catch (Exception e)
        {
            throw new InvalidOperationException(Localization.T("errors.downloaded_config_invalid", new() { ["error"] = e.Message }));
        }
        var tmpPath = Path.Combine(Path.GetTempPath(), $"kiwin_config_{Guid.NewGuid():N}.json");
        File.WriteAllBytes(tmpPath, data);
        Logger.Info($"Saved downloaded config to: {tmpPath}");
        return tmpPath;
    }

    private static JsonNode? LoadJsonConfig(string path, string label)
    {
        try
        {
            var text = File.ReadAllText(path, System.Text.Encoding.UTF8);
            var stripped = text.TrimStart('\uFEFF');
            return JsonNode.Parse(stripped);
        }
        catch (Exception e)
        {
            Logger.Error($"Failed to load {label} config: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.config_load_failed", new() { ["label"] = label, ["error"] = e.Message }),
                false);
            throw;
        }
    }

    private static string WriteTempConfig(JsonNode data, string prefix)
    {
        var tmpPath = Path.Combine(Path.GetTempPath(), $"{prefix}{Guid.NewGuid():N}.json");
        File.WriteAllText(tmpPath, data.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), System.Text.Encoding.UTF8);
        Logger.Info($"Saved generated config to: {tmpPath}");
        return tmpPath;
    }

    private static List<string>? NormalizeWinutilTweaks(JsonNode? value)
    {
        if (value is JsonArray arr)
        {
            var cleaned = new List<string>();
            var seen = new HashSet<string>();
            foreach (var item in arr)
            {
                if (item is not JsonValue) continue;
                var name = item.GetValue<string>().Trim();
                if (name.Length == 0 || seen.Contains(name)) continue;
                seen.Add(name);
                cleaned.Add(name);
            }
            return cleaned.Count > 0 ? cleaned : null;
        }
        if (value is JsonObject obj)
        {
            if (obj["WinUtil"] is not null)
                return NormalizeWinutilTweaks(obj["WinUtil"]);
            if (obj["WPFTweaks"] is JsonArray list)
                return NormalizeWinutilTweaks(list);
        }
        return null;
    }

    private static List<string>? ExtractWinutilConfig(JsonNode? data)
    {
        if (data is JsonArray) return NormalizeWinutilTweaks(data);
        if (data is not JsonObject obj) return null;
        if (obj["winutil_config"] is JsonNode cfg)
        {
            var value = cfg is JsonObject cfgObj && cfgObj["payload"] is not null ? cfgObj["payload"] : cfg;
            var normalized = NormalizeWinutilTweaks(value);
            if (normalized is null)
                Logger.Warning("install_plan winutil_config is not in a supported format; ignoring.");
            return normalized;
        }
        if (obj["WinUtil"] is JsonNode winutil)
        {
            var normalized = NormalizeWinutilTweaks(winutil);
            if (normalized is null)
                Logger.Warning("WinUtil config is not in a supported format; ignoring.");
            return normalized;
        }
        if (obj["Win11Debloat"] is not null)
        {
            var winutilData = new JsonObject();
            foreach (var kv in obj)
            {
                if (kv.Key != "Win11Debloat") winutilData[kv.Key] = kv.Value?.DeepClone();
            }
            return NormalizeWinutilTweaks(winutilData);
        }
        return NormalizeWinutilTweaks(obj);
    }

    private static List<string>? ExtractWin11DebloatArgs(JsonNode? data)
    {
        if (data is not JsonObject obj) return null;
        if (obj["win11debloat_args"] is JsonNode value)
        {
            if (value is JsonValue strVal && strVal.TryGetValue<string>(out var str))
                return str.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).ToList();
            if (value is JsonArray arr)
            {
                var cleaned = arr.Where(n => n is JsonValue).Select(n => n!.GetValue<string>()).ToList();
                if (cleaned.Count != arr.Count)
                    Logger.Warning("install_plan win11debloat_args contain non-string entries; ignoring invalid entries.");
                return cleaned;
            }
            Logger.Warning("install_plan win11debloat_args are not a string or list; ignoring.");
            return null;
        }
        if (obj["Win11Debloat"] is not JsonNode win11) return null;
        var args = win11 is JsonObject wObj
            ? wObj["Args"] ?? wObj["args"]
            : win11;
        if (args is null) return null;
        if (args is JsonArray argsArr)
        {
            if (argsArr.Count == 0) return new List<string>();
            var cleaned = argsArr.Where(n => n is JsonValue).Select(n => n!.GetValue<string>()).ToList();
            if (cleaned.Count != argsArr.Count)
                Logger.Warning("Win11Debloat args contain non-string entries; ignoring invalid entries.");
            return cleaned.Count > 0 ? cleaned : null;
        }
        if (args is JsonValue sv && sv.TryGetValue<string>(out var argStr))
            return new List<string> { argStr };
        Logger.Warning("Win11Debloat args are not a list or string; ignoring.");
        return null;
    }

    private static (string BasePath, JsonNode? UserConfig) PrepareContext(string? configPath)
    {
        var basePath = BasePath();
        if (configPath is not null && IsUrl(configPath))
        {
            try
            {
                configPath = DownloadConfig(configPath);
            }
            catch (Exception e)
            {
                Logger.Error($"Failed to download config: {e.Message}");
                ErrorDialog.Show(
                    Localization.T("errors.config_download_failed", new() { ["error"] = e.Message }),
                    false);
                throw;
            }
        }
        JsonNode? userConfig = null;
        if (!string.IsNullOrEmpty(configPath))
        {
            if (!File.Exists(configPath))
            {
                Logger.Error($"Config not found: {configPath}");
                ErrorDialog.Show(
                    Localization.T("errors.config_missing", new() { ["path"] = configPath }),
                    false);
                throw new FileNotFoundException("Config not found", configPath);
            }
            userConfig = LoadJsonConfig(configPath, "custom");
            Logger.Info($"Using custom config: {configPath}");
        }
        else
        {
            Logger.Info("Using embedded defaults from install_plan/runtime.");
        }
        return (basePath, userConfig);
    }

    public static void RunWinUtil(string? configPath = null, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        var (basePath, userConfig) = PrepareContext(configPath);
        List<string>? winutilConfig = null;
        if (userConfig is not null)
        {
            winutilConfig = ExtractWinutilConfig(userConfig);
            if (winutilConfig is null)
                Logger.Info("Custom config has no WinUtil config; using embedded default WinUtil config.");
        }
        winutilConfig ??= StepCatalog.DefaultWinutilTweaks();
        var configArray = new JsonArray(winutilConfig.Select(t => (JsonNode)t).ToArray());
        var winutilConfigPath = WriteTempConfig(configArray, "kiwin_winutil_");
        Logger.Info($"Using WinUtil config: {winutilConfigPath}");
        var winutilPath = Path.Combine(basePath, "external_scripts", "winutil.ps1");
        if (!File.Exists(winutilPath))
        {
            Logger.Error($"Bundled WinUtil script not found: {winutilPath}");
            ErrorDialog.Show(
                Localization.T("errors.bundled_winutil_missing", new() { ["path"] = winutilPath }),
                false);
            throw new FileNotFoundException("Bundled WinUtil script not found", winutilPath);
        }
        var cmd = $"& '{winutilPath}' -Config '{winutilConfigPath}' -Run -NoUI";
        Logger.Info("Executing ChrisTitusTech WinUtil");
        try
        {
            PowerShellHandler.RunCommand(cmd, monitorOutput: true, terminationStr: "Tweaks are Finished",
                timeout: TimeSpan.FromMinutes(25), cancel: cancel, outputLine: outputLine);
            Logger.Info("Successfully executed ChrisTitusTech WinUtil");
        }
        catch (Exception e)
        {
            Logger.Error($"Failed to execute ChrisTitusTech WinUtil: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.winutil_failed", new() { ["error"] = e.Message }),
                false);
            throw;
        }
    }

    public static void RunWin11Debloat(string? configPath = null, CancellationToken cancel = default, Action<string>? outputLine = null)
    {
        var (basePath, userConfig) = PrepareContext(configPath);
        List<string>? win11debloatArgs = null;
        if (userConfig is not null)
        {
            win11debloatArgs = ExtractWin11DebloatArgs(userConfig);
            if (win11debloatArgs is null)
                Logger.Info("Custom config has no Win11Debloat args; using embedded default Win11Debloat args.");
        }
        win11debloatArgs ??= StepCatalog.DefaultWin11DebloatArgsList();

        var candidates = Directory.Exists(Path.Combine(basePath, "external_scripts"))
            ? Directory.GetDirectories(Path.Combine(basePath, "external_scripts"), "Raphire-Win11Debloat-*")
                .OrderBy(d => d)
                .Select(d => Path.Combine(d, "Win11Debloat.ps1"))
                .Where(File.Exists)
                .ToList()
            : new List<string>();
        var win11debloatPath = candidates.Count > 0 ? candidates[^1] : "";
        if (!File.Exists(win11debloatPath))
        {
            Logger.Error($"Bundled Win11Debloat script not found: {win11debloatPath}");
            ErrorDialog.Show(
                Localization.T("errors.bundled_win11debloat_missing", new() { ["path"] = win11debloatPath }),
                false);
            throw new FileNotFoundException("Bundled Win11Debloat script not found", win11debloatPath);
        }
        var cmd = $"& '{win11debloatPath}'";
        if (win11debloatArgs.Count > 0)
            cmd += " " + string.Join(" ", win11debloatArgs);
        Logger.Info("Executing Raphire Win11Debloat");
        try
        {
            PowerShellHandler.RunCommand(cmd, timeout: TimeSpan.FromMinutes(15), cancel: cancel, outputLine: outputLine);
            Logger.Info("Successfully executed Raphire Win11Debloat");
        }
        catch (Exception e)
        {
            Logger.Error($"Failed to execute Raphire Win11Debloat: {e.Message}");
            ErrorDialog.Show(
                Localization.T("errors.win11debloat_failed", new() { ["error"] = e.Message }),
                false);
            throw;
        }
    }

    public static void Main(string? configPath = null)
    {
        RunWinUtil(configPath);
        RunWin11Debloat(configPath);
        Logger.Info("All external debloat scripts executed successfully.");
    }
}
