using System.Text.Json.Nodes;

namespace KiWin.Core;

public class Localization
{
    public const string DefaultLanguage = "en";

    private static JsonObject? _catalog;

    public static string? LocalesDir()
    {
        foreach (var path in CandidateDirs("locales"))
        {
            if (Directory.Exists(path)) return path;
        }
        return CandidateDirs("locales").First();
    }

    public static List<string> CandidateDirs(string sub)
    {
        var list = new List<string>();
        if (AppPaths.BundleAvailable)
            list.Add(Path.Combine(AppPaths.AppDataDir(), sub));
        var baseDir = AppContext.BaseDirectory;
        list.Add(Path.Combine(baseDir, sub));
        list.Add(Path.Combine(baseDir, "..", sub));
        return list.Select(Path.GetFullPath).ToList();
    }

    private static JsonNode? DeepGet(JsonNode? data, string dottedKey)
    {
        JsonNode? value = data;
        foreach (var part in dottedKey.Split('.'))
        {
            if (value is not JsonObject obj || !obj.ContainsKey(part)) return null;
            value = obj[part];
        }
        return value;
    }

    private static JsonObject LoadCatalog()
    {
        if (_catalog is not null) return _catalog;
        var path = Path.Combine(LocalesDir() ?? ".", $"{DefaultLanguage}.json");
        try
        {
            var text = File.ReadAllText(path, System.Text.Encoding.UTF8);
            _catalog = JsonNode.Parse(text) as JsonObject ?? new JsonObject();
        }
        catch
        {
            _catalog = new JsonObject();
        }
        return _catalog;
    }

    public static string T(string key, Dictionary<string, object?>? parameters = null)
    {
        key ??= "";
        parameters ??= new();
        var value = DeepGet(LoadCatalog(), key);
        if (value is null) return key;
        var text = value is JsonValue jv && jv.TryGetValue<string>(out var str) ? str : null;
        if (text is null) return value.ToString() ?? key;
        return ReplacePlaceholders(text, parameters);
    }

    public static string TOrKey(string key, Dictionary<string, object?>? parameters = null)
    {
        try { return T(key, parameters); } catch { return key; }
    }

    private static string ReplacePlaceholders(string text, Dictionary<string, object?> parameters)
    {
        var regex = new System.Text.RegularExpressions.Regex(@"\{([A-Za-z_][A-Za-z0-9_]*)\}");
        var replaced = regex.Replace(text, match =>
            parameters.TryGetValue(match.Groups[1].Value, out var p)
                ? p?.ToString() ?? ""
                : match.Value);
        return replaced;
    }
}
