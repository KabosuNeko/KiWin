using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace KiWin.Utilities;

public static class PowerShellHandler
{
    public static string ResolveScriptPath(string script)
    {
        string scriptPath;
        if (Path.IsPathRooted(script))
        {
            scriptPath = script;
        }
        else
        {
            var embeddedPath = Path.Combine(Logger.BasePath(), "debloat_scripts", script);
            if (File.Exists(embeddedPath))
            {
                scriptPath = embeddedPath;
            }
            else
            {
                scriptPath = Path.Combine(Path.GetTempPath(), "kiwin", script);
            }
        }
        if (!File.Exists(scriptPath))
            throw new FileNotFoundException($"PowerShell script not found: {scriptPath}");
        return scriptPath;
    }

    public static int RunScript(
        string script,
        IReadOnlyList<string>? args = null,
        bool monitorOutput = false,
        string? terminationStr = null,
        CancellationToken cancel = default,
        bool allowContinueOnFail = false)
    {
        var scriptPath = ResolveScriptPath(script);
        var argLine = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"";
        if (args is not null)
            argLine += " " + string.Join(" ", args.Select(EscapeArg));
        Logger.Info($"Launching PowerShell: powershell.exe {argLine}");
        return RunCore(argLine, Path.GetFileName(scriptPath), "PSCRIPT", monitorOutput, terminationStr, cancel, allowContinueOnFail);
    }

    public static int RunCommand(
        string command,
        bool monitorOutput = false,
        string? terminationStr = null,
        CancellationToken cancel = default,
        bool allowContinueOnFail = false)
    {
        var argLine = $"-NoProfile -ExecutionPolicy Bypass -Command {EscapeArg(command)}";
        Logger.Info($"Launching PowerShell command: {command}");
        return RunCore(argLine, "command", "PCOMMAND", monitorOutput, terminationStr, cancel, allowContinueOnFail);
    }

    private static int RunCore(
        string argLine,
        string label,
        string prefix,
        bool monitorOutput,
        string? terminationStr,
        CancellationToken cancel,
        bool allowContinueOnFail)
    {
        var psi = new ProcessStartInfo("powershell.exe")
        {
            Arguments = argLine,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        psi.StandardOutputEncoding = Encoding.UTF8;
        psi.StandardErrorEncoding = Encoding.UTF8;

        Process proc;
        try
        {
            proc = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start powershell.exe");
        }
        catch (Exception e)
        {
            Logger.Exception($"Failed to start PowerShell process", e);
            if (!ErrorDialog.Show(Localization_T("errors.powershell_script_launch_failed", new() { ["error"] = e.Message }), allowContinueOnFail))
                throw new InvalidOperationException("PowerShell launch aborted.", e);
            throw;
        }

        var terminationDetected = false;

        void StreamOut(object? s, DataReceivedEventArgs e)
        {
            if (e.Data is null) return;
            var text = e.Data.TrimEnd();
            Logger.Info($"{prefix} [{label}] STDOUT: {text}");
            if (monitorOutput && terminationStr is not null && text.Contains(terminationStr))
            {
                Logger.Info($"Termination string '{terminationStr}' detected.");
                terminationDetected = true;
                try { KillProcessTree(proc); } catch { }
            }
        }

        void StreamErr(object? s, DataReceivedEventArgs e)
        {
            if (e.Data is null) return;
            Logger.Error($"{prefix} [{label}] STDERR: {e.Data.TrimEnd()}");
        }

        proc.OutputDataReceived += StreamOut;
        proc.ErrorDataReceived += StreamErr;
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        try
        {
            while (!proc.HasExited)
            {
                if (cancel.IsCancellationRequested)
                {
                    Logger.Warning("Killing PowerShell due to external cancellation.");
                    try { KillProcessTree(proc); } catch { }
                    break;
                }
                Thread.Sleep(100);
            }
        }
        finally
        {
            try { proc.WaitForExit(); } catch { }
        }

        proc.CancelOutputRead();
        proc.CancelErrorRead();
        var rc = proc.ExitCode;
        if (terminationDetected && monitorOutput && rc != 0)
        {
            Logger.Info($"PowerShell terminated after detecting '{terminationStr}'. Treating exit code {rc} as success.");
            rc = 0;
        }
        if (rc != 0)
        {
            Logger.Error($"PowerShell exited with code {rc}");
            var message = prefix == "PSCRIPT"
                ? Localization_T("errors.powershell_script_failed", new() { ["script_name"] = label, ["exit_code"] = rc })
                : Localization_T("errors.powershell_command_failed", new() { ["exit_code"] = rc });
            if (!ErrorDialog.Show(message, allowContinueOnFail))
                throw new InvalidOperationException($"PowerShell failed (code {rc})");
        }
        else
        {
            Logger.Debug($"PowerShell completed successfully (code {rc})");
        }
        return rc;
    }

    private static string EscapeArg(string value) =>
        "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    private static void KillProcessTree(Process process)
    {
        try
        {
            var startInfo = new ProcessStartInfo("taskkill", $"/F /T /PID {process.Id}")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var killer = Process.Start(startInfo);
            killer?.WaitForExit(5000);
        }
        catch
        {
            try { process.Kill(); } catch { }
        }
    }

    private static string Localization_T(string key, Dictionary<string, object?>? parameters = null)
    {
        try
        {
            return KiWin.Core.Localization.T(key, parameters);
        }
        catch
        {
            return key;
        }
    }
}
