using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Text.Json.Nodes;
using KiWin.Core;
using KiWin.Debloat;
using KiWin.Utilities;
using Microsoft.Win32;

namespace KiWin.App;

public static class Program
{
    private const string CompletionRegistryPath = @"Software\KiWin";

    [STAThread]
    public static int Main(string[] args)
    {
        AppPaths.EnsureExtracted();
        Logger.Init();
        var rawArgs = args.ToList();

        CliArgs cli;
        try
        {
            cli = Cli.Parse(rawArgs);
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
            if (DebloatExecuteExternalScripts.IsUrl(cli.Config))
            {
                Logger.Info($"Config URL provided; it will be downloaded at run time: {cli.Config}");
            }
            else
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
        }

        JsonObject plan = new();
        string? runtimeConfigPath = cli.Config;
        var runtimeConfigIsTemp = false;
        var runtimeSelectedBrowserPackage = "";
        var executionSteps = StepCatalog.DebloatSteps.Select(s => (Step: s, Enabled: true)).ToList();
        App? app = null;

        if (!cli.Headless)
        {
            ErrorDialog.Implementation = new WpfErrorDialog();
            app = new App();
            app.InitializeComponent();
            app.ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown;
            var window = new MainWindow();
            var startTriggered = false;
            var flowOk = false;

            window.StartTriggered += () =>
            {
                startTriggered = true;
                try
                {
                    plan = InstallPlan.LoadInstallPlan();
                    executionSteps = RuntimePlan.BuildExecutionSteps(plan);
                    if (executionSteps.Count == 0)
                    {
                        var message = Localization.T("errors.empty_execution_plan");
                        Logger.Error(message);
                        ErrorDialog.Show(message, false);
                        app.Shutdown(1);
                        return;
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
                        var cfg = RuntimePlan.ExecutionConfigPath(cli, plan);
                        runtimeConfigPath = cfg.Path;
                        runtimeConfigIsTemp = cfg.IsTemp;
                    }
                    var useOverlay = !cli.DeveloperMode;
                    InstallOverlayWindow? overlay = null;
                    var cancelToken = CancellationToken.None;
                    Action<string>? logLine = null;
                    if (useOverlay)
                    {
                        overlay = new InstallOverlayWindow();
                        overlay.Show();
                        logLine = overlay.SetLogLine;
                        var cts = new CancellationTokenSource();
                        cancelToken = cts.Token;
                        overlay.CancelRequested += () =>
                        {
                            if (cts.IsCancellationRequested) return;
                            if (!ErrorDialog.Confirm(
                                    Localization.T("app.install_overlay.cancel_confirm"),
                                    Localization.T("app.install_overlay.cancel_title")))
                                return;
                            overlay.SetStatus(Localization.T("app.install_overlay.cancelling"));
                            overlay.SetLogLine(Localization.T("app.install_overlay.cancel_initiated"));
                            cts.Cancel();
                        };
                    }

                    Task.Run(() =>
                    {
                        try
                        {
                            flowOk = RunDebloatSequence(executionSteps, cli, runtimeConfigPath, runtimeConfigIsTemp,
                                runtimeSelectedBrowserPackage, overlay, cancelToken, logLine);
                            if (overlay is not null)
                            {
                                Thread.Sleep(2500);
                                overlay.Dispatcher.Invoke(() => overlay.Close());
                            }
                            Logger.Info(flowOk ? "Debloat process finished successfully." : "Debloat process aborted.");
                        }
                        catch (Exception e)
                        {
                            flowOk = false;
                            Logger.Exception("Debloat flow failed", e);
                            try { overlay?.AllowDialogOnTop(); ErrorDialog.Show(Localization.T("errors.installation_unexpected"), false); } catch { }
                        }
                        finally
                        {
                            app?.Dispatcher.Invoke(() => app.Shutdown(flowOk ? 0 : 1));
                        }
                    });
                }
                catch (Exception e)
                {
                    flowOk = false;
                    Logger.Exception("Debloat flow initialization failed", e);
                    try { ErrorDialog.Show(Localization.T("errors.installation_unexpected"), false); } catch { }
                    app.Shutdown(1);
                }
            };

            window.Closed += (_, _) =>
            {
                if (!startTriggered)
                {
                    Logger.Info("Initial window closed without Start; exiting before debloat process starts.");
                    app?.Shutdown(0);
                }
            };

            app.Run(window);
            return flowOk ? 0 : 1;
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
            var runOk = RunDebloatSequence(executionSteps, cli, runtimeConfigPath, runtimeConfigIsTemp,
                runtimeSelectedBrowserPackage, null);
            Logger.Info(runOk ? "Debloat process finished successfully." : "Debloat process aborted.");
            return runOk ? 0 : 1;
        }
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

    private static bool RunDebloatSequence(
        List<(DebloatStepInfo Step, bool Enabled)> executionSteps,
        CliArgs cli,
        string? runtimeConfigPath,
        bool runtimeConfigIsTemp,
        string runtimeSelectedBrowserPackage,
        InstallOverlayWindow? overlay,
        CancellationToken cancel = default,
        Action<string>? logLine = null)
    {
        try
        {
            cancel.ThrowIfCancellationRequested();
            overlay?.SetStatus("");
            if (!cli.DryRun)
            {
                TryCreateRestorePoint(logLine);
            }
            var totalRun = executionSteps.Count(s => s.Enabled && !cli.SkipSteps.GetValueOrDefault(s.Step.Slug));
            var stepIndex = 0;
            foreach (var (step, enabled) in executionSteps)
            {
                cancel.ThrowIfCancellationRequested();
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
                stepIndex++;
                overlay?.SetProgress(stepIndex, totalRun);
                overlay?.SetStatus(message);
                logLine?.Invoke($"==> {message}");
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
                                DebloatExecuteExternalScripts.RunWinUtil(runtimeConfigPath, cancel, logLine);
                            else
                                DebloatExecuteExternalScripts.RunWin11Debloat(runtimeConfigPath, cancel, logLine);
                            break;
                        case DebloatKind.BrowserPackage:
                            DebloatBrowserInstallation.Main(runtimeSelectedBrowserPackage, cancel, logLine);
                            break;
                        default:
                            if (step.Slug == "remove-edge-permanently")
                                DebloatExecuteKiWinScripts.RunEdgeRemoval(cancel, logLine);
                            else if (step.Slug == "configure-updates")
                                DebloatConfigureUpdates.Main(cancel, logLine);
                            else if (step.Slug == "unpin-taskbar-start")
                                DebloatUnpinTaskbar.Main(cancel, logLine);
                            break;
                    }
                }
                catch (OperationCanceledException)
                {
                    Logger.Info("Debloat aborted by user.");
                    logLine?.Invoke(Localization.T("app.install_overlay.cancelled"));
                    overlay?.SetStatus(Localization.T("app.install_overlay.cancelled"));
                    overlay?.StopSpinner();
                    return true;
                }
                catch (Exception e)
                {
                    if (cancel.IsCancellationRequested)
                    {
                        Logger.Info("Debloat aborted by user.");
                        overlay?.SetStatus(Localization.T("app.install_overlay.cancelled"));
                        overlay?.StopSpinner();
                        return true;
                    }
                    Logger.Exception("Debloat step failed", e);
                    overlay?.StopSpinner();
                    if (!cli.Headless)
                    {
                        overlay?.AllowDialogOnTop();
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

    private static void TryCreateRestorePoint(Action<string>? logLine)
    {
        try
        {
            Logger.Info("Requesting a System Restore point (best effort)...");
            logLine?.Invoke($"==> {Localization.T("app.install_overlay.creating_restore_point")}");
            const string cmd =
                "$ErrorActionPreference='SilentlyContinue'; " +
                "try { Enable-ComputerRestore -Drive $env:SystemDrive; " +
                "Checkpoint-Computer -Description 'KiWin' -RestorePointType MODIFY_SETTINGS } catch {}; exit 0";
            PowerShellHandler.RunCommand(cmd, timeout: TimeSpan.FromMinutes(3));
            Logger.Info("System Restore point request finished.");
        }
        catch (Exception e)
        {
            Logger.Warning($"Could not create a System Restore point (continuing): {e.Message}");
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
