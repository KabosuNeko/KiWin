using System.Text.Json.Nodes;

namespace KiWin.Core;

public class Localization
{
    public const string DefaultLanguage = "en";

    private static string _currentLanguage = DefaultLanguage;
    private static readonly Dictionary<string, JsonObject> Cache = new();

    public static string CurrentLanguage => _currentLanguage;

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
        var baseDir = AppContext.BaseDirectory;
        list.Add(Path.Combine(baseDir, sub));
        list.Add(Path.Combine(baseDir, "..", sub));
        return list.Select(Path.GetFullPath).ToList();
    }

    private static JsonNode? _deepGet(JsonNode? data, string dottedKey)
    {
        JsonNode? value = data;
        foreach (var part in dottedKey.Split('.'))
        {
            if (value is not JsonObject obj || !obj.ContainsKey(part)) return null;
            value = obj[part];
        }
        return value;
    }

    private static JsonObject _loadCatalog(string language)
    {
        language = string.IsNullOrEmpty(language) ? DefaultLanguage : language;
        if (Cache.TryGetValue(language, out var cached)) return cached;
        var path = Path.Combine(LocalesDir() ?? ".", $"{language}.json");
        JsonObject catalog;
        try
        {
            var text = File.ReadAllText(path, System.Text.Encoding.UTF8);
            catalog = JsonNode.Parse(text) as JsonObject ?? new JsonObject();
        }
        catch
        {
            catalog = new JsonObject();
        }
        Cache[language] = catalog;
        return catalog;
    }

    public static List<LanguageInfo> AvailableLanguages()
    {
        var outList = new List<LanguageInfo>();
        var root = LocalesDir();
        if (root == null || !Directory.Exists(root)) return outList;
        var names = Directory.GetFiles(root, "*.json")
            .Select(Path.GetFileNameWithoutExtension)
            .OrderBy(name => name != $"{DefaultLanguage}.json")
            .ThenBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        foreach (var code in names)
        {
            var catalog = _loadCatalog(code!);
            var meta = catalog["meta"] as JsonObject;
            outList.Add(new LanguageInfo(
                Code: code!,
                NativeName: meta?.GetString("native_name", code!) ?? code!,
                EnglishName: meta?.GetString("english_name", code!) ?? code!,
                Direction: meta?.GetString("direction", "ltr") ?? "ltr"));
        }
        return outList;
    }

    public static bool SetLanguage(string language)
    {
        language = string.IsNullOrEmpty(language) ? DefaultLanguage : language;
        var path = Path.Combine(LocalesDir() ?? ".", $"{language}.json");
        if (!File.Exists(path)) return false;
        _currentLanguage = language;
        _loadCatalog(language);
        return true;
    }

    public static string T(string key, Dictionary<string, object?>? parameters = null)
    {
        key ??= "";
        parameters ??= new();
        var value = _deepGet(_loadCatalog(_currentLanguage), key);
        if (value is null && _currentLanguage != DefaultLanguage)
            value = _deepGet(_loadCatalog(DefaultLanguage), key);
        if (value is null) return key;
        string? text = value is JsonValue jv && jv.TryGetValue<string>(out var str) ? str : null;
        if (text is null) return value.ToString() ?? key;
        var result = ReplacePlaceholders(text, parameters);
        return result;
    }

    private static string ReplacePlaceholders(string text, Dictionary<string, object?> parameters)
    {
        var regex = new System.Text.RegularExpressions.Regex(@"\{([A-Za-z_][A-Za-z0-9_]*)\}");
        var replaced = regex.Replace(text, match =>
            parameters.TryGetValue(match.Groups[1].Value, out var p)
                ? p?.ToString() ?? ""
                : match.Value);
        return regex.IsMatch(replaced) ? text : replaced;
    }
}

public record LanguageInfo(string Code, string NativeName, string EnglishName, string Direction);
