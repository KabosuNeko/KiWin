using System.Text.Json.Nodes;
using KiWin.Core;

namespace KiWin.Core;

public static class StepCatalog
{
    public static readonly BrowserOption[] BrowserOptions =
    {
        new("Waterfox", "../../media/browser_waterfox.png", "Waterfox.Waterfox", "browsers.waterfox.tooltip"),
        new("Helium", "../../media/browser_helium.png", "ImputNet.Helium", "browsers.helium.tooltip"),
        new("Firefox", "../../media/browser_firefox.png", "Mozilla.Firefox", "browsers.firefox.tooltip"),
        new("Brave", "../../media/browser_brave.png", "Brave.Brave", "browsers.brave.tooltip"),
        new("LibreWolf", "../../media/browser_librewolf.png", "LibreWolf.LibreWolf", "browsers.librewolf.tooltip"),
    };

    public static readonly Dictionary<string, string> BrowserTooltipKeys =
        BrowserOptions.ToDictionary(b => b.PackageId, b => b.TooltipKey);

    public static readonly string[] StepSlugs =
    {
        "remove-edge-permanently",
        "browser-installation",
        "debloat-windows-phase-one",
        "debloat-windows-phase-two",
        "configure-updates",
        "unpin-taskbar-start",
    };

    public static readonly string[] BoolOptionSlugs =
        { "developer-mode", "prevent-device-companion-apps", "wpbt", "remove-onedrive", "remove-apps", "remove-gaming-apps" };

    public const string StandardPresetKey = "standard";

    public static bool DefaultBoolOptionEnabled(string slug) =>
        slug is "prevent-device-companion-apps" or "wpbt" or "remove-onedrive" or "remove-apps" or "remove-gaming-apps";

    public static readonly Dictionary<string, StepPresentation> StepPresentation = new()
    {
        ["remove-edge-permanently"] = new("steps.remove_edge_permanently.text", "steps.remove_edge_permanently.tooltip"),
        ["browser-installation"] = new("steps.browser_installation.text", "steps.browser_installation.tooltip"),
        ["debloat-windows-phase-one"] = new("steps.debloat_windows_phase_one.text", "steps.debloat_windows_phase_one.tooltip"),
        ["debloat-windows-phase-two"] = new("steps.debloat_windows_phase_two.text", "steps.debloat_windows_phase_two.tooltip"),
        ["configure-updates"] = new("steps.configure_updates.text", "steps.configure_updates.tooltip"),
        ["unpin-taskbar-start"] = new("steps.unpin_taskbar_start.text", "steps.unpin_taskbar_start.tooltip"),
        ["developer-mode"] = new("steps.developer_mode.text", "steps.developer_mode.tooltip"),
        ["prevent-device-companion-apps"] = new("steps.prevent_device_companion_apps.text", "steps.prevent_device_companion_apps.tooltip"),
        ["wpbt"] = new("steps.wpbt.text", "steps.wpbt.tooltip"),
        ["remove-onedrive"] = new("steps.remove_onedrive.text", "steps.remove_onedrive.tooltip"),
        ["remove-apps"] = new("steps.remove_apps.text", "steps.remove_apps.tooltip"),
        ["remove-gaming-apps"] = new("steps.remove_gaming_apps.text", "steps.remove_gaming_apps.tooltip"),
    };

    public static readonly JsonObject DefaultWinutilConfig = new()
    {
        ["WPFTweaks"] = new JsonArray(
            "WPFTweaksActivity",
            "WPFTweaksConsumerFeatures",
            "WPFTweaksDisableBGapps",
            "WPFTweaksTelemetry",
            "WPFTweaksWPBT",
            "WPFTweaksWidget",
            "WPFTweaksServices",
            "WPFTweaksDisplay",
            "WPFTweaksRightClickMenu",
            "WPFTweaksRemoveOneDrive",
            "WPFTweaksRemoveHomeAndGallery",
            "WPFTweaksWindowsAI",
            "WPFTweaksDisableStoreSearch",
            "WPFTweaksLocation",
            "WPFTweaksReservedStorage",
            "WPFTweaksRazerBlock")
    };

    public static readonly string[] DefaultWin11DebloatArgs =
    {
        "-Silent", "-RemoveApps", "-RemoveGamingApps", "-DisableTelemetry", "-DisableBing",
        "-DisableSuggestions", "-DisableLockscreenTips", "-RevertContextMenu",
        "-DisableWidgets", "-DisableCopilot", "-ClearStartAllUsers", "-DisableDVR",
        "-DisableStartRecommended", "-ExplorerToThisPC",
        "-DisableDesktopSpotlight", "-DisableSettings365Ads", "-DisableSettingsHome", "-DisablePaintAI",
        "-DisableNotepadAI", "-DisableEdgeAI", "-DisableStickyKeys", "-DisableEdgeAds",
        "-DisableBraveBloat", "-DisableRecall", "-DisableAISvcAutoStart", "-DisableClickToDo",
        "-DisableSnapLayouts", "-DisableSearchHistory", "-DisableDeliveryOptimization",
        "-DisableDeviceAutoAppDownload", "-DisableSearchHighlights", "-DisableStoreSearchSuggestions",
        "-DisableLocationServices", "-DisableFindMyDevice", "-PreventUpdateAutoReboot",
        "-DisableStartPhoneLink", "-DisableModernStandbyNetworking",
    };

    private static JsonObject BuildStandardPresetFallback()
    {
        var items = new JsonArray();
        foreach (var slug in BoolOptionSlugs.Concat(StepSlugs))
        {
            items.Add(new JsonObject
            {
                ["key"] = slug,
                ["enabled"] = DefaultBoolOptionEnabled(slug),
            });
        }
        var tweaks = new JsonArray();
        foreach (var tweak in DefaultWinutilConfig["WPFTweaks"]!.AsArray())
            tweaks.Add(tweak!.DeepClone());
        return new JsonObject
        {
            ["preset_key"] = StandardPresetKey,
            ["preset_name"] = "Standard",
            ["version"] = 1,
            ["selected_preset_key"] = StandardPresetKey,
            ["selected_browser_name"] = "None",
            ["selected_browser_package"] = "",
            ["include_browser_install"] = false,
            ["items"] = items,
            ["winutil_config"] = new JsonObject { ["WPFTweaks"] = tweaks },
            ["win11debloat_args"] = string.Join(" ", DefaultWin11DebloatArgs),
            ["registry_changes"] = null,
            ["applied_background_path"] = "",
        };
    }

    public static string? PresetsDir()
    {
        foreach (var path in Localization.CandidateDirs("presets"))
        {
            if (Directory.Exists(path)) return path;
        }
        return Localization.CandidateDirs("presets").First();
    }

    public static string ToTitleLabel(string key)
    {
        var parts = key.Replace("-", " ").Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", parts.Select(p => p.Length > 0 ? char.ToUpper(p[0]) + p[1..] : p));
    }

    private static (string Key, string Name, JsonObject Plan)? NormalizePreset(JsonNode? raw, string fallbackKey)
    {
        if (raw is not JsonObject obj) return null;
        var key = obj.GetString("preset_key", obj.GetString("selected_preset_key", fallbackKey));
        key = string.IsNullOrEmpty(key) ? fallbackKey : key;
        var name = obj.GetString("preset_name", obj.GetString("name", ToTitleLabel(key)));
        name = string.IsNullOrEmpty(name) ? ToTitleLabel(key) : name;
        var plan = obj.DeepClone() as JsonObject;
        if (plan is null) return null;
        plan["selected_preset_key"] = key;
        plan.Remove("preset_key");
        plan.Remove("preset_name");
        plan.Remove("name");
        if (plan.GetNode("version") is not JsonValue || plan.GetNode("items") is not JsonArray) return null;
        return (key, name, plan);
    }

    private static (string Key, string Name, JsonObject Plan)? LoadPresetFile(string path)
    {
        try
        {
            var text = File.ReadAllText(path, System.Text.Encoding.UTF8);
            return NormalizePreset(JsonNode.Parse(text), Path.GetFileNameWithoutExtension(path));
        }
        catch
        {
            return null;
        }
    }

    public static List<PresetInfo> AvailablePresets()
    {
        var presets = new List<PresetInfo>();
        var root = PresetsDir();
        if (root != null && Directory.Exists(root))
        {
            var names = Directory.GetFiles(root, "*.json")
                .Select(Path.GetFileName)
                .OrderBy(n => n != $"{StandardPresetKey}.json")
                .ThenBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();
            foreach (var name in names)
            {
                var preset = LoadPresetFile(Path.Combine(root, name!));
                if (preset is not null)
                    presets.Add(new PresetInfo(preset.Value.Key, preset.Value.Name, preset.Value.Plan));
            }
        }
        if (!presets.Any(p => p.Key == StandardPresetKey))
        {
            var fallback = NormalizePreset(BuildStandardPresetFallback(), StandardPresetKey);
            if (fallback is not null)
                presets.Insert(0, new PresetInfo(fallback.Value.Key, fallback.Value.Name, fallback.Value.Plan));
        }
        return presets;
    }

    public static List<PresetOption> PresetOptions() =>
        AvailablePresets().Select(p => new PresetOption(p.Key, p.Name)).ToList();

    public static PresetInfo PresetByKey(string key)
    {
        var wanted = string.IsNullOrEmpty(key) ? StandardPresetKey : key;
        foreach (var preset in AvailablePresets())
        {
            if (preset.Key == wanted)
                return new PresetInfo(preset.Key, preset.Name, preset.Plan.DeepClone() as JsonObject ?? new JsonObject());
        }
        var fallback = NormalizePreset(BuildStandardPresetFallback(), StandardPresetKey);
        return fallback is null
            ? new PresetInfo(StandardPresetKey, "Standard", new JsonObject())
            : new PresetInfo(fallback.Value.Key, fallback.Value.Name, fallback.Value.Plan);
    }

    public static JsonObject DefaultWinutilConfigCopy() => DefaultWinutilConfig.DeepClone() as JsonObject ?? new JsonObject();

    public static List<string> DefaultWinutilTweaks() =>
        DefaultWinutilConfig["WPFTweaks"]!.AsArray().Select(n => n!.GetValue<string>()).ToList();

    public static List<string> DefaultWin11DebloatArgsList() => DefaultWin11DebloatArgs.ToList();

    public static string DefaultWin11DebloatArgsText() => string.Join(" ", DefaultWin11DebloatArgs);

    public static string BrowserTooltip(string packageId) =>
        Localization.T(BrowserTooltipKeys.GetValueOrDefault(packageId, "steps.browser_installation.tooltip"));

    public static string BrowserStepText(string browserName) =>
        Localization.T("steps.browser_installation.text_with_browser", new() { ["browser_name"] = browserName });

    public static List<BrowserOptionData> BrowserOptionsLocalized()
    {
        var outList = new List<BrowserOptionData>();
        foreach (var browser in BrowserOptions)
        {
            outList.Add(new BrowserOptionData(
                browser.Name,
                browser.Icon,
                browser.PackageId,
                Localization.T(browser.TooltipKey)));
        }
        return outList;
    }

    public static string StepText(string slug)
    {
        var present = StepPresentation.GetValueOrDefault(slug);
        var key = present?.TextKey ?? $"steps.{slug.Replace("-", "_")}.text";
        var value = Localization.T(key);
        return value == key ? ToTitleLabel(slug) : value;
    }

    public static string StepTooltip(string slug)
    {
        var present = StepPresentation.GetValueOrDefault(slug);
        var key = present?.TooltipKey ?? $"steps.{slug.Replace("-", "_")}.tooltip";
        var value = Localization.T(key);
        return value == key ? "" : value;
    }
}

public record BrowserOption(string Name, string Icon, string PackageId, string TooltipKey);
public record BrowserOptionData(string Name, string Icon, string PackageId, string Tooltip);
public record PresetInfo(string Key, string Name, JsonObject Plan);
public record PresetOption(string Key, string Name);
public record StepPresentation(string TextKey, string TooltipKey);
