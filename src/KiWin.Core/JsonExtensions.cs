using System.Text.Json;
using System.Text.Json.Nodes;

namespace KiWin.Core;

public static class JsonExtensions
{
    public static JsonObject? AsObj(this JsonNode? node) => node as JsonObject;

    public static JsonNode? GetNode(this JsonNode? node, string key) => node?.AsObj()?[key];

    public static string GetString(this JsonNode? node, string key, string fallback = "")
    {
        var v = node?.GetNode(key);
        if (v is JsonValue jv && jv.TryGetValue<string>(out var s)) return s;
        if (v is JsonValue jv2 && jv2.TryGetValue<int>(out var i)) return i.ToString();
        return fallback;
    }

    public static bool GetBool(this JsonNode? node, string key, bool fallback = false)
    {
        var v = node?.GetNode(key);
        if (v is not JsonValue jv) return fallback;
        if (jv.TryGetValue<bool>(out var b)) return b;
        if (jv.TryGetValue<int>(out var i)) return i != 0;
        if (jv.TryGetValue<string>(out var s))
        {
            switch (s.Trim().ToLowerInvariant())
            {
                case "1":
                case "true":
                case "yes":
                case "on":
                    return true;
                case "0":
                case "false":
                case "no":
                case "off":
                    return false;
            }
        }
        return fallback;
    }

    public static JsonNode? DeepClone(this JsonNode node) =>
        JsonNode.Parse(node.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
}
