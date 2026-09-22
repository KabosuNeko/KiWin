using KiWin.Core;

namespace KiWin.App;

public class CliArgs
{
    public bool DeveloperMode { get; set; }
    public bool Headless { get; set; }
    public bool DryRun { get; set; }
    public bool UndoUpdatePolicy { get; set; }
    public string? Config { get; set; }
    public Dictionary<string, bool> SkipSteps { get; } = new();
}

public static class Cli
{
    public static CliArgs Parse(IReadOnlyList<string> rawArgs)
    {
        var args = new CliArgs();
        foreach (var slug in StepCatalog.DebloatSteps)
            args.SkipSteps[slug.Slug] = false;

        var stepLookup = StepCatalog.DebloatSteps.ToDictionary(s => s.Slug, s => s.Slug);

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
}
