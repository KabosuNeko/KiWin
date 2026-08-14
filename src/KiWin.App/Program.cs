using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Text.Json;
using System.Text.Json.Nodes;
using KiWin.Core;
using KiWin.Debloat;
using KiWin.Utilities;
using Microsoft.Win32;

namespace KiWin.App;

public enum DebloatKind
{
    None,
    ConfigPath,
    BrowserPackage,
}

public record DebloatStepInfo(string Slug, string MessageKey, DebloatKind Kind);

public class CliArgs
{
    public bool DeveloperMode { get; set; }
    public bool Headless { get; set; }
    public bool DryRun { get; set; }
    public bool UndoUpdatePolicy { get; set; }
    public string? Config { get; set; }
    public Dictionary<string, bool> SkipSteps { get; } = new();
}

public static class Program
{
    private const string CompletionRegistryPath = @"Software\KiWin";

    public static readonly DebloatStepInfo[] DebloatSteps =
    {
        new("remove-edge-permanently", "app.install_overlay.remove_edge", DebloatKind.None),
        new("browser-installation", "app.install_overlay.browser_installation", DebloatKind.BrowserPackage),
        new("debloat-windows-phase-one", "app.install_overlay.debloat_windows_phase_one", DebloatKind.ConfigPath),
        new("debloat-windows-phase-two", "app.install_overlay.debloat_windows_phase_two", DebloatKind.ConfigPath),
        new("configure-updates", "app.install_overlay.configure_updates", DebloatKind.None),
    };

    [STAThread]
    public static int Main(string[] args)
    {
        Logger.Init();
        var rawArgs = args.ToList();

        CliArgs cli;
        try
        {
            cli = ParseArgs(rawArgs);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.Message);
            Logger.Error(e.Message);
            return 1;
        }

        if (cli.DeveloperMode && !cli.Headless && Environment.GetEnvironmentVariable("KIWIN_DEV_CONSOLE") != "1")
        {
            if (LaunchDeveloperConsole(rawArgs)) return 0;
            return 1;
        }

        if (cli.Headless)
        {
            cli.DeveloperMode = true;
            cli.SkipSteps["browser-installation"] = true;
        }

        if (cli.UndoUpdatePolicy)
        {
            Logger.Info("Undoing Windows update policy...");
            try
            {
                PowerShellHandler.RunScript("undo_update_policy.ps1");
                Logger.Info("Update policy undone.");
                return 0;
            }
            catch (Exception e)
            {
                Logger.Error($"Failed to undo update policy: {e.Message}");
                return 1;
            }
        }

        if (cli.DryRun)
        {
            Environment.SetEnvironmentVariable("KIWIN_DRY_RUN", "1");
            Logger.Info("Dry-run mode enabled; execution steps will be previewed without modifying the system.");
        }

        if (cli.Config is not null)
        {
            var configPath = Path.GetFullPath(cli.Config);
            if (!File.Exists(configPath))
            {
                var message = Localization.T("errors.config_not_found", new() { ["path"] = configPath });
                Logger.Error(message);
                ErrorDialog.Show(message, false);
                return 1;
            }
            cli.Config = configPath;
        }

        JsonObject plan = new();
        string? runtimeConfigPath = cli.Config;
        var runtimeConfigIsTemp = false;
        var runtimeSelectedBrowserPackage = "";
        var executionSteps = DebloatSteps.Select(s => (Step: s, Enabled: true)).ToList();

        if (!cli.Headless)
        {
            ErrorDialog.Implementation = new WpfErrorDialog();
            var app = new App();
            app.InitializeComponent();
            var window = new MainWindow();
            app.Run(window);
            if (!window.StartRequested)
            {
                Logger.Info("Initial window closed without Start; exiting before debloat process starts.");
                return 0;
            }
            plan = InstallPlan.LoadInstallPlan();
            executionSteps = BuildExecutionStepsFromPlan(plan);
            if (executionSteps.Count == 0)
            {
                var message = Localization.T("errors.empty_execution_plan");
                Logger.Error(message);
                ErrorDialog.Show(message, false);
                return 0;
            }
            runtimeSelectedBrowserPackage = plan.GetString("selected_browser_package").Trim();
            foreach (var raw in plan["items"]?.AsArray() ?? new JsonArray())
            {
                if (raw is JsonObject obj && obj.GetString("key").Trim() == "developer-mode")
                {
                    if (obj.GetBool("enabled")) cli.DeveloperMode = true;
                    break;
                }
            }
            if (!cli.DryRun)
            {
                var cfg = ExecutionConfigPath(cli, plan);
                runtimeConfigPath = cfg.Path;
                runtimeConfigIsTemp = cfg.IsTemp;
            }
        }
        else
        {
            if (!cli.DryRun)
            {
                if (!AdminHelper.EnsureAdmin()) return 0;
                try
                {
                    PreChecks.Run();
                }
                catch
                {
                    return 1;
                }
            }
        }

        var useOverlay = !cli.DeveloperMode;
        InstallOverlayWindow? overlay = null;
        if (useOverlay)
        {
            overlay = new InstallOverlayWindow();
            overlay.Show();
        }

        var runOk = RunDebloatSequence(executionSteps, cli, runtimeConfigPath, runtimeConfigIsTemp,
            runtimeSelectedBrowserPackage, overlay);

        if (overlay is not null)
        {
            Thread.Sleep(2500);
            overlay.Close();
        }

        Logger.Info(runOk ? "Debloat process finished successfully." : "Debloat process aborted.");
        return runOk ? 0 : 1;
    }

    private static bool LaunchDeveloperConsole(IReadOnlyList<string> rawArgs)
    {
        var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? AppDomain.CurrentDomain.BaseDirectory;
        var commandLine = $"\"{exe}\" {string.Join(" ", rawArgs.Select(a => $"\"{a}\""))}";
        try
        {
            var psi = new ProcessStartInfo("cmd.exe", $"/k {commandLine}")
            {
                UseShellExecute = true,
            };
            psi.EnvironmentVariables["KIWIN_DEV_CONSOLE"] = "1";
            Process.Start(psi);
            return true;
        }
        catch (Exception e)
        {
            Logger.Exception("Failed to launch developer console window", e);
            ErrorDialog.Show(Localization.T("errors.developer_console_failed", new() { ["error"] = e.Message }), false);
            return false;
        }
    }

    public static CliArgs ParseArgs(IReadOnlyList<string> rawArgs)
    {
        var args = new CliArgs();
        foreach (var slug in DebloatSteps)
            args.SkipSteps[slug.Slug] = false;

        var stepLookup = DebloatSteps.ToDictionary(s => s.Slug, s => s.Slug);

        foreach (var token in rawArgs)
        {
            if (!token.Contains('='))
            {
                throw new ArgumentException(
                    $"Invalid argument '{token}'. Use key=value format, e.g. configure-updates=false.");
            }
            var parts = token.Split(new[] { '=' }, 2);
            var key = parts[0].Trim().ToLowerInvariant();
            var value = parts[1].Trim();

            switch (key)
            {
                case "developer-mode":
                    args.DeveloperMode = ParseBool(value);
                    break;
                case "headless":
                    args.Headless = ParseBool(value);
                    break;
                case "dry-run":
                    args.DryRun = ParseBool(value);
                    break;
                case "config":
                    args.Config = value;
                    break;
                case "undo-update-policy":
                    args.UndoUpdatePolicy = ParseBool(value);
                    break;
                default:
                    if (stepLookup.ContainsKey(key))
                    {
                        args.SkipSteps[key] = !ParseBool(value);
                    }
                    else
                    {
                        throw new ArgumentException(
                            $"Unknown argument key '{key}'. Supported keys: developer-mode, headless, dry-run, config, "
                            + string.Join(", ", stepLookup.Keys));
                    }
                    break;
            }
        }
        return args;
    }

    private static bool ParseBool(string value)
    {
        switch (value.Trim().ToLowerInvariant())
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
            default:
                throw new ArgumentException($"Invalid boolean value: {value}");
        }
    }

    private static List<(DebloatStepInfo Step, bool Enabled)> BuildExecutionStepsFromPlan(JsonObject plan)
    {
        var lookup = DebloatSteps.ToDictionary(s => s.Slug);
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

    private static (string? Path, bool IsTemp) ExecutionConfigPath(CliArgs args, JsonObject plan)
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
        var payload = new JsonObject
        {
            ["WinUtil"] = winutil,
            ["Win11Debloat"] = new JsonObject
            {
                ["Args"] = new JsonArray(win11Args.Select(a => (JsonNode)a).ToArray()),
            },
        };
        var tmpPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"kiwin_install_plan_runtime_{Guid.NewGuid():N}.json");
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

    private static bool RunDebloatSequence(
        List<(DebloatStepInfo Step, bool Enabled)> executionSteps,
        CliArgs cli,
        string? runtimeConfigPath,
        bool runtimeConfigIsTemp,
        string runtimeSelectedBrowserPackage,
        InstallOverlayWindow? overlay)
    {
        try
        {
            overlay?.SetStatus("");
            foreach (var (step, enabled) in executionSteps)
            {
                if (!enabled)
                {
                    Logger.Info($"Skipping {step.Slug} step (disabled in install_plan)");
                    continue;
                }
                if (cli.SkipSteps.GetValueOrDefault(step.Slug))
                {
                    Logger.Info($"Skipping {step.Slug} step");
                    continue;
                }
                var message = Localization.T(step.MessageKey);
                overlay?.SetStatus(message);
                if (cli.DryRun)
                {
                    Logger.Info($"Dry-run: would run {step.Slug} step");
                    if (!cli.Headless && !cli.DeveloperMode)
                        Thread.Sleep(800);
                    continue;
                }
                try
                {
                    switch (step.Kind)
                    {
                        case DebloatKind.ConfigPath:
                            if (step.Slug == "debloat-windows-phase-one")
                                DebloatExecuteWinUtil.Main(runtimeConfigPath);
                            else
                                DebloatExecuteWin11Debloat.Main(runtimeConfigPath);
                            break;
                        case DebloatKind.BrowserPackage:
                            DebloatBrowserInstallation.Main(runtimeSelectedBrowserPackage);
                            break;
                        default:
                            if (step.Slug == "remove-edge-permanently")
                                DebloatRemoveEdge.Main();
                            else if (step.Slug == "configure-updates")
                                DebloatConfigureUpdates.Main();
                            break;
                    }
                }
                catch (Exception e)
                {
                    Logger.Exception("Debloat step failed", e);
                    overlay?.StopSpinner();
                    if (!cli.Headless)
                    {
                        ErrorDialog.Show(Localization.T("errors.installation_unexpected"), false);
                    }
                    return false;
                }
            }

            if (cli.DryRun)
            {
                overlay?.SetStatus(Localization.T("app.install_overlay.dry_run_complete"));
                overlay?.StopSpinner();
                return true;
            }

            try
            {
                RecordDebloatCompletion();
            }
            catch (Exception e)
            {
                Logger.Exception("Failed to record KiWin completion marker", e);
                if (!cli.Headless)
                {
                    ErrorDialog.Show(
                        Localization.T("errors.completion_marker_failed", new() { ["error"] = e.Message }),
                        allowContinue: true);
                }
            }
            overlay?.SetStatus(Localization.T("app.install_overlay.complete_no_restart"));
            overlay?.StopSpinner();
            return true;
        }
        finally
        {
            if (runtimeConfigIsTemp && runtimeConfigPath is not null)
            {
                try
                {
                    if (File.Exists(runtimeConfigPath)) File.Delete(runtimeConfigPath);
                }
                catch (Exception e)
                {
                    Logger.Warning($"Failed to clean temporary runtime config '{runtimeConfigPath}': {e.Message}");
                }
            }
        }
    }

    private static void RecordDebloatCompletion()
    {
        var epochUtc = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        using var key = Microsoft.Win32.RegistryKey.OpenBaseKey(Microsoft.Win32.RegistryHive.LocalMachine, Microsoft.Win32.RegistryView.Registry64)
            .CreateSubKey(CompletionRegistryPath, writable: true);
        key.SetValue("Version", KiWinInfo.Version, RegistryValueKind.String);
        key.SetValue("DebloatRanUtc", epochUtc, RegistryValueKind.QWord);
        Logger.Info(
            $"Recorded KiWin completion marker: HKLM\\{CompletionRegistryPath} " +
            $"Version={KiWinInfo.Version}, DebloatRanUtc={epochUtc}");
    }
}
