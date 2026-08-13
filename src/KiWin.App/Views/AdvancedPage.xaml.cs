using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using KiWin.Core;

namespace KiWin.App.Views;

public partial class AdvancedPage : UserControl
{
    public event Action? BackClicked;

    public AdvancedPage()
    {
        InitializeComponent();
    }

    public void Refresh()
    {
        TitleText.Text = Localization.T("configuration.advanced.title");
        WarningText.Text = Localization.T("configuration.advanced.warning");
        StepsLabel.Text = UiText.T("configuration.advanced.steps", "Steps");
        BackButton.Content = Localization.T("configuration.dialogs.cancel");
        Win11Label.Text = Localization.T("configuration.advanced.set_win11_args");
        WinUtilLabel.Text = Localization.T("configuration.advanced.winutil_tweaks");
        WinUtilBox.ToolTip = Localization.T("configuration.advanced.winutil_tweaks_tooltip");
        SaveWin11Button.Content = Localization.T("configuration.dialogs.save_changes");
        SaveWinUtilButton.Content = Localization.T("configuration.dialogs.save_changes");
        ImportPlanButton.Content = Localization.T("configuration.advanced.import_plan");
        ImportWinutilButton.Content = Localization.T("configuration.advanced.import_winutil");
        ExportPlanButton.Content = Localization.T("configuration.advanced.export_plan");
        UndoPolicyButton.Content = Localization.T("configuration.advanced.undo_update_policy");

        var plan = InstallPlan.LoadInstallPlan();
        var steps = new List<AdvancedStep>();
        foreach (var slug in StepCatalog.BoolOptionSlugs.Concat(StepCatalog.StepSlugs))
        {
            steps.Add(new AdvancedStep(
                slug,
                StepCatalog.StepText(slug),
                StepCatalog.StepTooltip(slug),
                InstallPlan.IsItemEnabled(plan, slug)));
        }
        StepsList.ItemsSource = steps;

        Win11ArgsBox.Text = InstallPlan.FormatWin11DebloatArgsForEditor(plan.GetNode("win11debloat_args"));
        WinUtilBox.Text = FormatWinUtilTweaksForEditor(plan.GetNode("winutil_config"));
    }

    private static string FormatWinUtilTweaksForEditor(JsonNode? value)
    {
        if (value is JsonObject obj && obj["WPFTweaks"] is JsonArray arr)
        {
            var tweaks = arr.Where(n => n is JsonValue).Select(n => n!.GetValue<string>().Trim())
                .Where(s => s.Length > 0).ToList();
            return string.Join("\n", tweaks);
        }
        if (value is JsonArray list)
        {
            var tweaks = list.Where(n => n is JsonValue).Select(n => n!.GetValue<string>().Trim())
                .Where(s => s.Length > 0).ToList();
            return string.Join("\n", tweaks);
        }
        return value?.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) ?? "";
    }

    private void StepCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { Tag: string key } check || !check.IsLoaded)
            return;
        var data = InstallPlan.LoadInstallPlan();
        InstallPlan.SetItemEnabled(data, key, check.IsChecked == true);
        data["include_browser_install"] = InstallPlan.IsItemEnabled(data, "browser-installation");
        if (key == "browser-installation" && string.IsNullOrEmpty(data.GetString("selected_browser_package")))
            data["include_browser_install"] = false;
        InstallPlan.SaveInstallPlan(data);
    }

    private void SaveWin11_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var data = InstallPlan.LoadInstallPlan();
            data["win11debloat_args"] = InstallPlan.NormalizeWin11DebloatArgsText(Win11ArgsBox.Text);
            InstallPlan.MarkCustom(data);
            InstallPlan.SaveInstallPlan(data);
        }
        catch (Exception ex)
        {
            ErrorDialog.Show(Localization.T("errors.save_win11_args_failed", new() { ["error"] = ex.Message }), true);
        }
    }

    private void SaveWinUtil_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var lines = WinUtilBox.Text.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0)
                .ToList();
            var config = new JsonObject
            {
                ["WPFTweaks"] = new JsonArray(lines.Select(l => (JsonNode)l).ToArray()),
            };
            var data = InstallPlan.LoadInstallPlan();
            data["winutil_config"] = config;
            InstallPlan.MarkCustom(data);
            InstallPlan.SaveInstallPlan(data);
        }
        catch (Exception ex)
        {
            ErrorDialog.Show(Localization.T("errors.save_winutil_failed", new() { ["error"] = ex.Message }), true);
        }
    }

    private void ImportPlan_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = Localization.T("configuration.dialogs.import_plan_title"),
                Filter = Localization.T("configuration.dialogs.json_files_filter"),
            };
            if (dialog.ShowDialog() != true) return;
            var payload = JsonNode.Parse(File.ReadAllText(dialog.FileName, System.Text.Encoding.UTF8)) as JsonObject
                          ?? throw new InvalidDataException("Install plan must be a JSON object.");
            var data = InstallPlan.NormalizeImportedPlan(payload);
            InstallPlan.MarkCustom(data);
            InstallPlan.SaveInstallPlan(data);
            Refresh();
        }
        catch (Exception ex)
        {
            ErrorDialog.Show(Localization.T("errors.import_plan_failed", new() { ["error"] = ex.Message }), true);
        }
    }

    private void ImportWinutil_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = Localization.T("configuration.dialogs.import_winutil_title"),
                Filter = Localization.T("configuration.dialogs.json_files_filter"),
            };
            if (dialog.ShowDialog() != true) return;
            var payload = JsonNode.Parse(File.ReadAllText(dialog.FileName, System.Text.Encoding.UTF8));
            if (payload is not JsonObject and not JsonArray)
                throw new ArgumentException(Localization.T("errors.winutil_config_invalid"));
            var data = InstallPlan.LoadInstallPlan();
            data["winutil_config"] = InstallPlan.NormalizeWinutilConfig(payload);
            InstallPlan.MarkCustom(data);
            InstallPlan.SaveInstallPlan(data);
        }
        catch (Exception ex)
        {
            ErrorDialog.Show(Localization.T("errors.import_winutil_failed", new() { ["error"] = ex.Message }), true);
        }
    }

    private void ExportPlan_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Title = Localization.T("configuration.dialogs.export_plan_title"),
                Filter = Localization.T("configuration.dialogs.json_files_filter"),
                FileName = "install_plan.json",
            };
            if (dialog.ShowDialog() != true) return;
            var path = dialog.FileName;
            if (!path.EndsWith(".json", StringComparison.OrdinalIgnoreCase)) path += ".json";
            var data = InstallPlan.LoadInstallPlan();
            File.WriteAllText(path, data.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), System.Text.Encoding.UTF8);
        }
        catch (Exception ex)
        {
            ErrorDialog.Show(Localization.T("errors.export_plan_failed", new() { ["error"] = ex.Message }), true);
        }
    }

    private void UndoPolicy_Click(object sender, RoutedEventArgs e)
    {
        UndoPolicyButton.IsEnabled = false;
        Task.Run(() =>
        {
            try
            {
                PowerShellHandler.RunScript("undo_update_policy.ps1");
                Dispatcher.Invoke(() =>
                {
                    UndoPolicyButton.IsEnabled = true;
                    MessageBox.Show(
                        Localization.T("configuration.advanced.undo_policy_done"),
                        Localization.T("errors.dialog_title"),
                        MessageBoxButton.OK, MessageBoxImage.Information);
                });
            }
            catch (Exception ex)
            {
                Logger.Error($"Failed to undo update policy: {ex.Message}");
                Dispatcher.Invoke(() =>
                {
                    UndoPolicyButton.IsEnabled = true;
                    ErrorDialog.Show(
                        Localization.T("errors.undo_policy_failed", new() { ["error"] = ex.Message }),
                        false);
                });
            }
        });
    }

    private void BackButton_Click(object sender, RoutedEventArgs e) => BackClicked?.Invoke();
}

public record AdvancedStep(string Key, string Text, string Tooltip, bool IsEnabled);
