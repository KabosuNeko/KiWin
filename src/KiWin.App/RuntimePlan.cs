using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.App;

internal static class RuntimePlan
{
    public static List<(DebloatStepInfo Step, bool Enabled)> BuildExecutionSteps(JsonObject plan)
    {
        var lookup = StepCatalog.DebloatSteps.ToDictionary(s => s.Slug);
        var selectedBrowser = plan.GetString("selected_browser_package").Trim();
        var ordered = new List<(DebloatStepInfo, bool)>();
        foreach (var raw in plan["items"]?.AsArray() ?? new JsonArray())
        {
            if (raw is not JsonObject obj) continue;
            var key = obj.GetString("key").Trim();
            var enabled = obj.GetBool("enabled");
            if (!lookup.ContainsKey(key)) continue;
            if (key == "browser-installation" && selectedBrowser.Length == 0) enabled = false;
            ordered.Add((lookup[key], enabled));
        }
        return ordered;
    }

    public static (string? Path, bool IsTemp) ExecutionConfigPath(CliArgs args, JsonObject plan)
    {
        if (args.Config is not null) return (args.Config, false);
        var winutilCfg = plan.GetNode("winutil_config");
        if (winutilCfg is not JsonObject and not JsonArray) return (null, false);
        var winutil = winutilCfg.DeepClone();
        ApplyWinUtilToggles(plan, winutil);
        AddOutlookRemoval(winutil, plan);
        var rawArgs = plan.GetString("win11debloat_args");
        var win11Args = rawArgs.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)
            .Where(a => !(a == "-RemoveApps" && !InstallPlan.IsItemEnabled(plan, "remove-apps")))
            .Where(a => !(a == "-RemoveGamingApps" && !InstallPlan.IsItemEnabled(plan, "remove-gaming-apps")))
            .ToList();
        if (InstallPlan.IsItemEnabled(plan, "remove-apps") && !win11Args.Contains("-RemoveApps"))
            win11Args.Add("-RemoveApps");
        if (InstallPlan.IsItemEnabled(plan, "remove-gaming-apps") && !win11Args.Contains("-RemoveGamingApps"))
            win11Args.Add("-RemoveGamingApps");
        win11Args = StepCatalog.FilterWin11DebloatArgs(win11Args, a => Logger.Warning($"Ignoring unsafe Win11Debloat argument: {a}"));
        var payload = new JsonObject
        {
            ["WinUtil"] = winutil,
            ["Win11Debloat"] = new JsonObject
            {
                ["Args"] = new JsonArray(win11Args.Select(a => (JsonNode)a).ToArray()),
                ["Sysprep"] = InstallPlan.IsItemEnabled(plan, "debloat-new-users"),
            },
        };
        var tmpPath = Path.Combine(Path.GetTempPath(), $"kiwin_install_plan_runtime_{Guid.NewGuid():N}.json");
        File.WriteAllText(tmpPath, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), Encoding.UTF8);
        return (tmpPath, true);
    }

    private static void ApplyWinUtilToggles(JsonObject plan, JsonNode winutil)
    {
        JsonArray? tweaks = winutil switch
        {
            JsonObject obj when obj["WPFTweaks"] is JsonArray arr => arr,
            JsonArray arr => arr,
            _ => null,
        };
        if (tweaks is null) return;

        bool Has(string name) => tweaks.Any(n => n is JsonValue jv && jv.TryGetValue<string>(out var s) && s == name);
        void Set(string name, bool on)
        {
            var has = Has(name);
            if (on && !has)
                tweaks.Add(name);
            else if (!on && has)
            {
                var item = tweaks.First(n => n is JsonValue jv && jv.TryGetValue<string>(out var s) && s == name);
                tweaks.Remove(item);
            }
        }

        Set("WPFTweaksWPBT", InstallPlan.IsItemEnabled(plan, "wpbt"));
        Set("WPFTweaksPreventDeviceMetadataFromNetwork", InstallPlan.IsItemEnabled(plan, "prevent-device-companion-apps"));
        Set("WPFTweaksRemoveOneDrive", InstallPlan.IsItemEnabled(plan, "remove-onedrive"));
    }

    private static void AddOutlookRemoval(JsonNode winutil, JsonObject plan)
    {
        if (winutil is not JsonObject obj) return;
        var appx = obj["WPFAppx"] as JsonArray ?? new JsonArray();
        obj["WPFAppx"] = appx;
        var required = new List<string>();
        if (InstallPlan.IsItemEnabled(plan, "remove-apps"))
            required.Add("WPFAppxMicrosoft_OutlookForWindows");
        if (InstallPlan.IsItemEnabled(plan, "remove-gaming-apps"))
        {
            required.AddRange(new[]
            {
                "WPFAppxMicrosoft_Xbox_TCUI",
                "WPFAppxMicrosoft_XboxGamingOverlay",
                "WPFAppxMicrosoft_XboxIdentityProvider",
                "WPFAppxMicrosoft_XboxSpeechToTextOverlay",
            });
        }
        foreach (var app in required)
        {
            bool has = appx.Any(n => n is JsonValue jv && jv.TryGetValue<string>(out var s) && s == app);
            if (!has) appx.Add(app);
        }
    }
}
