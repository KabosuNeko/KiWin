using System.Text.Json;
using System.Text.Json.Nodes;
using KiWin.Core;

namespace KiWin.Core;

public static class InstallPlan
{
    public const int InstallPlanVersion = 1;

    public static string KiWinDir()
    {
        var temp = Path.GetTempPath();
        return Path.Combine(temp, "kiwin");
    }

    public static string InstallPlanPath() => Path.Combine(KiWinDir(), "install_plan.json");

    public static readonly string[] MetadataKeys =
        { "winutil_config", "win11debloat_args", "registry_changes", "applied_background_path" };

    public static JsonArray DefaultRegistryChanges() => new();

    public static string NormalizeWin11DebloatArgsText(string text) =>
        string.Join(" ", (text ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    public static string FormatWin11DebloatArgsForEditor(JsonNode? value)
    {
        if (value is JsonArray arr)
        {
            var cleaned = arr.Where(n => n is JsonValue).Select(n => n!.GetValue<string>().Trim())
                .Where(s => s.Length > 0).ToList();
            return string.Join("\n", cleaned);
        }
        var compact = NormalizeWin11DebloatArgsText(value?.GetValue<string>() ?? "");
        if (compact.Length == 0) return "";
        return string.Join("\n", compact.Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    public static JsonNode? NormalizeWinutilConfig(JsonNode? value)
    {
        if (value is JsonObject obj)
        {
            if (obj["payload"] is JsonNode payload && payload is JsonObject or JsonArray)
                value = payload;
            if (value is JsonObject obj2 && obj2["WinUtil"] is JsonNode winutil && winutil is JsonObject)
                value = winutil;
        }
        if (value is JsonArray list)
        {
            var tweaks = list.Where(n => n is JsonValue).Select(n => n!.GetValue<string>().Trim())
                .Where(s => s.Length > 0).ToList();
            return new JsonObject { ["WPFTweaks"] = new JsonArray(tweaks.Select(t => (JsonNode)t).ToArray()) };
        }
        if (value is JsonObject obj3)
        {
            var normalized = new JsonObject();
            foreach (var kv in obj3)
            {
                if (kv.Key == "WPFTweaks" && kv.Value is JsonArray arr)
                {
                    var arr2 = new JsonArray();
                    foreach (var item in arr.Where(n => n is JsonValue))
                    {
                        var s = item!.GetValue<string>().Trim();
                        if (s.Length > 0) arr2.Add(s);
                    }
                    normalized[kv.Key] = arr2;
                }
                else
                {
                    normalized[kv.Key] = kv.Value?.DeepClone();
                }
            }
            return normalized;
        }
        return StepCatalog.DefaultWinutilConfigCopy();
    }

    public static JsonNode? NormalizeRegistryChanges(JsonNode? value)
    {
        if (value is null) return DefaultRegistryChanges();
        if (value is JsonValue strVal && strVal.TryGetValue<string>(out var raw))
        {
            var stripped = raw.Trim();
            if (stripped.Length == 0) return DefaultRegistryChanges();
            try
            {
                return JsonNode.Parse(stripped);
            }
            catch
            {
                return DefaultRegistryChanges();
            }
        }
        if (value is JsonObject or JsonArray) return value.DeepClone();
        return DefaultRegistryChanges();
    }

    public static void NormalizeMetadataFields(JsonObject data)
    {
        data["winutil_config"] = NormalizeWinutilConfig(data.GetNode("winutil_config"));
        var argsRaw = data.GetNode("win11debloat_args");
        if (argsRaw is JsonArray arr)
        {
            argsRaw = string.Join(" ", arr.Where(n => n is JsonValue)
                .Select(n => n!.GetValue<string>().Trim()).Where(s => s.Length > 0));
        }
        var argsText = argsRaw?.GetValue<string>()?.Trim() ?? "";
        if (argsText.Length == 0) argsText = StepCatalog.DefaultWin11DebloatArgsText();
        data["win11debloat_args"] = NormalizeWin11DebloatArgsText(argsText);
        data["registry_changes"] = NormalizeRegistryChanges(data.GetNode("registry_changes"));
        data["applied_background_path"] = (data.GetString("applied_background_path") ?? "").Trim();
    }

    public static JsonNode? CopyMetadataValue(JsonNode? value) => value?.DeepClone();

    public static JsonObject BuildInstallPlan(
        string browserName = "None",
        string browserPackage = "",
        bool includeBrowserInstall = false,
        string presetKey = StepCatalog.StandardPresetKey)
    {
        var preset = StepCatalog.PresetByKey(presetKey);
        var presetPlan = CopyMetadataValue(preset.Plan) as JsonObject ?? new JsonObject();
        var presetItems = new Dictionary<string, JsonObject>();
        if (presetPlan["items"] is JsonArray presetArr)
        {
            foreach (var raw in presetArr)
            {
                if (raw is JsonObject o && !string.IsNullOrEmpty(o.GetString("key")))
                    presetItems[o.GetString("key")] = o;
            }
        }
        var items = new JsonArray();
        foreach (var slug in StepCatalog.BoolOptionSlugs.Concat(StepCatalog.StepSlugs))
        {
            var rawItem = presetItems.GetValueOrDefault(slug);
            var enabled = rawItem?.GetBool("enabled", StepCatalog.DefaultBoolOptionEnabled(slug)) ??
                          StepCatalog.DefaultBoolOptionEnabled(slug);
            var item = new JsonObject
            {
                ["key"] = slug,
                ["text"] = rawItem?.GetString("text") ?? "",
                ["tooltip"] = rawItem?.GetString("tooltip") ?? "",
                ["enabled"] = enabled,
            };
            if (slug == "browser-installation")
                item["enabled"] = includeBrowserInstall && enabled;
            items.Add(item);
        }
        var winutilConfig = CopyMetadataValue(presetPlan.GetNode("winutil_config") ?? StepCatalog.DefaultWinutilConfigCopy());
        var win11debloatArgs = CopyMetadataValue(presetPlan.GetNode("win11debloat_args") ?? StepCatalog.DefaultWin11DebloatArgsText());
        if (win11debloatArgs is JsonArray wArr)
        {
            win11debloatArgs = string.Join(" ", wArr.Where(n => n is JsonValue)
                .Select(n => n!.GetValue<string>().Trim()).Where(s => s.Length > 0));
        }
        var registryChanges = CopyMetadataValue(presetPlan.GetNode("registry_changes")) ?? DefaultRegistryChanges();
        return new JsonObject
        {
            ["version"] = InstallPlanVersion,
            ["selected_preset_key"] = preset.Key,
            ["selected_browser_name"] = browserName,
            ["selected_browser_package"] = browserPackage,
            ["include_browser_install"] = IsItemEnabled(new JsonObject { ["items"] = items.DeepClone() }, "browser-installation"),
            ["items"] = items,
            ["winutil_config"] = winutilConfig,
            ["win11debloat_args"] = NormalizeWin11DebloatArgsText(win11debloatArgs?.GetValue<string>() ?? ""),
            ["registry_changes"] = registryChanges,
            ["applied_background_path"] = (presetPlan.GetString("applied_background_path") ?? "").Trim(),
        };
    }

    public static JsonObject NormalizeItem(JsonNode? item)
    {
        if (item is JsonObject obj)
        {
            return new JsonObject
            {
                ["key"] = obj.GetString("key"),
                ["text"] = obj.GetString("text"),
                ["tooltip"] = obj.GetString("tooltip"),
                ["enabled"] = obj.GetBool("enabled"),
            };
        }
        return new JsonObject
        {
            ["key"] = "",
            ["text"] = item?.GetValue<string>() ?? "",
            ["tooltip"] = "",
            ["enabled"] = false,
        };
    }

    public static JsonObject NormalizeImportedPlan(JsonObject payload)
    {
        var incomingVersion = payload.GetNode("version") as JsonValue;
        int version;
        try
        {
            version = incomingVersion?.GetValue<int>() ?? InstallPlanVersion;
        }
        catch
        {
            throw new ArgumentException("Install plan field 'version' must be an integer.");
        }
        if (version < 1) throw new ArgumentException("Install plan field 'version' must be >= 1.");
        if (payload["items"] is not JsonArray)
            throw new ArgumentException("Install plan is missing required field: items.");

        var normalized = BuildInstallPlan(
            browserName: payload.GetString("selected_browser_name", "None"),
            browserPackage: payload.GetString("selected_browser_package"),
            includeBrowserInstall: payload.GetBool("include_browser_install"),
            presetKey: payload.GetString("selected_preset_key", StepCatalog.StandardPresetKey));
        normalized["selected_preset_key"] = payload.GetString("selected_preset_key", normalized.GetString("selected_preset_key", StepCatalog.StandardPresetKey));
        normalized["version"] = version;

        var defaultKeys = new HashSet<string>();
        foreach (var item in normalized["items"]!.AsArray())
            defaultKeys.Add(NormalizeItem(item).GetString("key"));
        var importedByKey = new Dictionary<string, JsonObject>();
        var unknownItems = new JsonArray();
        foreach (var raw in payload["items"]!.AsArray())
        {
            var n = NormalizeItem(raw);
            if (string.IsNullOrEmpty(n.GetString("key"))) continue;
            if (defaultKeys.Contains(n.GetString("key")))
                importedByKey[n.GetString("key")] = n;
            else
                unknownItems.Add(n);
        }
        foreach (var item in normalized["items"]!.AsArray())
        {
            var key = NormalizeItem(item).GetString("key");
            if (importedByKey.TryGetValue(key, out var imported))
                item!["enabled"] = imported.GetBool("enabled");
        }
        foreach (var u in unknownItems) normalized["items"]!.AsArray().Add(u);
        if (string.IsNullOrEmpty(normalized.GetString("selected_browser_package")))
            SetItemEnabledForPreset(normalized, "browser-installation", false);
        normalized["include_browser_install"] = IsItemEnabled(normalized, "browser-installation");
        foreach (var key in MetadataKeys)
        {
            if (payload[key] is not null) normalized[key] = payload[key]?.DeepClone();
        }
        NormalizeMetadataFields(normalized);
        return normalized;
    }

    public static void EnsureInstallPlanFile()
    {
        Directory.CreateDirectory(KiWinDir());
        var path = InstallPlanPath();
        if (!File.Exists(path))
        {
            SaveInstallPlan(BuildInstallPlan());
            return;
        }
        try
        {
            var text = File.ReadAllText(path, System.Text.Encoding.UTF8);
            var data = JsonNode.Parse(text) as JsonObject;
            if (data is null) throw new InvalidDataException("plan root must be an object");
            if (data["items"] is not JsonArray)
                throw new InvalidDataException("install plan items is not a list");
            var normalized = BuildInstallPlan(
                browserName: data.GetString("selected_browser_name", "None"),
                browserPackage: data.GetString("selected_browser_package"),
                includeBrowserInstall: data.GetBool("include_browser_install"),
                presetKey: data.GetString("selected_preset_key", StepCatalog.StandardPresetKey));
            normalized["selected_preset_key"] = data.GetString("selected_preset_key", normalized.GetString("selected_preset_key", StepCatalog.StandardPresetKey));
            var existingVersion = data.GetNode("version") as JsonValue;
            int version;
            try
            {
                version = existingVersion?.GetValue<int>() ?? InstallPlanVersion;
            }
            catch
            {
                version = InstallPlanVersion;
            }
            normalized["version"] = version >= 1 ? version : InstallPlanVersion;
            var existingEnabledByKey = new Dictionary<string, bool>();
            foreach (var raw in data["items"]!.AsArray())
            {
                var n = NormalizeItem(raw);
                if (!string.IsNullOrEmpty(n.GetString("key")))
                    existingEnabledByKey[n.GetString("key")] = n.GetBool("enabled");
            }
            foreach (var item in normalized["items"]!.AsArray())
            {
                var key = NormalizeItem(item).GetString("key");
                if (existingEnabledByKey.ContainsKey(key))
                    item!["enabled"] = existingEnabledByKey[key];
            }
            if (string.IsNullOrEmpty(normalized.GetString("selected_browser_package")))
                SetItemEnabledForPreset(normalized, "browser-installation", false);
            normalized["include_browser_install"] = IsItemEnabled(normalized, "browser-installation");
            foreach (var key in MetadataKeys)
            {
                if (data[key] is not null) normalized[key] = data[key]?.DeepClone();
            }
            NormalizeMetadataFields(normalized);
            SaveInstallPlan(normalized);
        }
        catch
        {
            SaveInstallPlan(BuildInstallPlan());
        }
    }

    public static void ResetInstallPlanDefaults()
    {
        Directory.CreateDirectory(KiWinDir());
        SaveInstallPlan(BuildInstallPlan());
    }

    public static JsonObject LoadInstallPlan()
    {
        EnsureInstallPlanFile();
        try
        {
            var text = File.ReadAllText(InstallPlanPath(), System.Text.Encoding.UTF8);
            var data = JsonNode.Parse(text) as JsonObject;
            if (data is null) throw new InvalidDataException("plan root must be an object");
            if (data["items"] is not JsonArray) data["items"] = new JsonArray();
            var original = data.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            NormalizeMetadataFields(data);
            var normalizedText = data.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            if (normalizedText != original) SaveInstallPlan(data);
            return data;
        }
        catch
        {
            return BuildInstallPlan();
        }
    }

    public static void SaveInstallPlan(JsonObject data)
    {
        Directory.CreateDirectory(KiWinDir());
        var json = data.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(InstallPlanPath(), json, System.Text.Encoding.UTF8);
    }

    public static void MarkCustom(JsonObject data) => data["selected_preset_key"] = "custom";

    public static int FindItemIndex(JsonArray items, string key)
    {
        for (var i = 0; i < items.Count; i++)
        {
            if (NormalizeItem(items[i]).GetString("key") == key) return i;
        }
        return -1;
    }

    public static void SetItemEnabled(JsonObject data, string key, bool enabled)
    {
        var items = new JsonArray();
        foreach (var item in data["items"]?.AsArray() ?? new JsonArray())
        {
            var n = NormalizeItem(item);
            if (n.GetString("key") == key) n["enabled"] = enabled;
            items.Add(n);
        }
        data["items"] = items;
        if (key != "browser-installation" || !string.IsNullOrEmpty(data.GetString("selected_browser_package")))
            MarkCustom(data);
    }

    public static void SetItemEnabledForPreset(JsonObject data, string key, bool enabled)
    {
        var items = new JsonArray();
        foreach (var item in data["items"]?.AsArray() ?? new JsonArray())
        {
            var n = NormalizeItem(item);
            if (n.GetString("key") == key) n["enabled"] = enabled;
            items.Add(n);
        }
        data["items"] = items;
    }

    public static bool IsItemEnabled(JsonObject data, string key)
    {
        foreach (var item in data["items"]?.AsArray() ?? new JsonArray())
        {
            var n = NormalizeItem(item);
            if (n.GetString("key") == key) return n.GetBool("enabled");
        }
        return false;
    }

    public static List<string> EnabledPlanKeys(JsonObject data)
    {
        var keys = new List<string>();
        var selectedBrowser = data.GetString("selected_browser_package").Trim();
        foreach (var item in data["items"]?.AsArray() ?? new JsonArray())
        {
            var n = NormalizeItem(item);
            var key = n.GetString("key");
            if (string.IsNullOrEmpty(key) || !n.GetBool("enabled")) continue;
            if (key == "browser-installation" && selectedBrowser.Length == 0) continue;
            keys.Add(key);
        }
        return keys;
    }

    public static List<VisibleItem> VisibleEnabledItems(JsonObject data)
    {
        var outList = new List<VisibleItem>();
        var knownKeys = new HashSet<string>(StepCatalog.BoolOptionSlugs.Concat(StepCatalog.StepSlugs));
        foreach (var item in data["items"]?.AsArray() ?? new JsonArray())
        {
            var n = NormalizeItem(item);
            if (!n.GetBool("enabled")) continue;
            var key = n.GetString("key");
            if (key == "browser-installation" && string.IsNullOrEmpty(data.GetString("selected_browser_package"))) continue;
            string text, tooltip;
            if (knownKeys.Contains(key))
            {
                if (key == "browser-installation")
                {
                    text = StepCatalog.BrowserStepText(data.GetString("selected_browser_name", "None"));
                    tooltip = StepCatalog.BrowserTooltip(data.GetString("selected_browser_package"));
                }
                else
                {
                    text = StepCatalog.StepText(key);
                    tooltip = StepCatalog.StepTooltip(key);
                }
            }
            else
            {
                text = n.GetString("text");
                tooltip = n.GetString("tooltip");
            }
            outList.Add(new VisibleItem(key, text, tooltip));
        }
        return outList;
    }

    public static void SetBrowser(string packageId, string browserName)
    {
        var data = LoadInstallPlan();
        var items = data["items"]?.AsArray() ?? new JsonArray();
        var idx = FindItemIndex(items, "browser-installation");
        if (idx >= 0) items[idx]!["enabled"] = true;
        data["items"] = items;
        data["selected_browser_name"] = browserName;
        data["selected_browser_package"] = packageId;
        data["include_browser_install"] = true;
        SaveInstallPlan(data);
    }

    public static void SkipBrowserInstall()
    {
        var data = LoadInstallPlan();
        SetItemEnabled(data, "browser-installation", false);
        data["selected_browser_name"] = "None";
        data["selected_browser_package"] = "";
        data["include_browser_install"] = false;
        SaveInstallPlan(data);
    }

    public static void ApplyInternetAvailability(bool available)
    {
        if (available) return;
        var data = LoadInstallPlan();
        SetItemEnabledForPreset(data, "browser-installation", false);
        data["include_browser_install"] = false;
        SaveInstallPlan(data);
    }

    public static void ApplyPreset(string presetKey)
    {
        var current = LoadInstallPlan();
        var selectedBrowserName = current.GetString("selected_browser_name", "None");
        var selectedBrowserPackage = current.GetString("selected_browser_package");
        var preset = StepCatalog.PresetByKey(presetKey);
        var data = BuildInstallPlan(
            browserName: selectedBrowserName,
            browserPackage: selectedBrowserPackage,
            includeBrowserInstall: selectedBrowserPackage.Length > 0,
            presetKey: preset.Key);
        if (selectedBrowserPackage.Length == 0)
        {
            SetItemEnabledForPreset(data, "browser-installation", false);
            data["selected_preset_key"] = preset.Key;
        }
        SaveInstallPlan(data);
    }
}

public record VisibleItem(string Key, string Text, string Tooltip);
