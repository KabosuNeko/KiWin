using System.Text.Json;
using System.Text.Json.Nodes;

namespace KiWin.Core;

public static class JsonExtensions
{
    public static JsonObject? AsObj(this JsonNode? node) => node as JsonObject;

    public static JsonArray? AsArr(this JsonNode? node) => node as JsonArray;

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

    public static int GetInt(this JsonNode? node, string key, int fallback = 0)
    {
        var v = node?.GetNode(key);
        if (v is JsonValue jv)
        {
            if (jv.TryGetValue<int>(out var i)) return i;
            if (jv.TryGetValue<long>(out var l)) return (int)l;
            if (jv.TryGetValue<string>(out var s) && int.TryParse(s, out var p)) return p;
        }
        return fallback;
    }

    public static JsonNode? DeepClone(this JsonNode node) =>
        JsonNode.Parse(node.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

    public static bool DeepEquals(JsonNode? a, JsonNode? b) => JsonNode.DeepEquals(a, b);

    public static JsonObject ToObject(string json) =>
        (JsonNode.Parse(json) as JsonObject) ?? new JsonObject();
}
