using KiWin.Core;

namespace KiWin.App;

public static class UiText
{
    public static string T(string key, string fallback, Dictionary<string, object?>? parameters = null)
    {
        var value = Localization.T(key, parameters);
        return value == key ? fallback : value;
    }
}
