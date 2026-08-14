using System.Collections.Generic;

namespace KiWin.Core;

public static class DictionaryExtensions
{
    public static TValue? GetValueOrDefault<TKey, TValue>(
        this IDictionary<TKey, TValue> dictionary,
        TKey key,
        TValue? defaultValue = default)
    {
        if (dictionary != null && dictionary.TryGetValue(key, out var value))
        {
            return value;
        }
        return defaultValue;
    }
}
