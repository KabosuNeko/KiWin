using System.Windows;
using System.Windows.Controls;
using KiWin.Core;

namespace KiWin.App.Views;

public partial class ReviewPage : UserControl
{
    public event Action? BackClicked;
    public event Action? AdvancedClicked;
    public event Action? StartClicked;

    public ReviewPage()
    {
        InitializeComponent();
    }

    private bool InternetAvailable { get; set; }
    private bool _presetUpdating;

    public void SetInternetAvailable(bool available)
    {
        InternetAvailable = available;
        if (ItemsList.ItemsSource is not null)
            Refresh();
    }

    public void Refresh()
    {
        _presetUpdating = true;
        try
        {
            RefreshCore();
        }
        finally
        {
            _presetUpdating = false;
        }
    }

    private void RefreshCore()
    {
        TitleText.Text = Localization.T("configuration.review.title");
        GuidanceText.Text = Localization.T("configuration.review.guidance");
        NoBrowserWarning.Text = Localization.T("configuration.review.no_browser_warning");
        NoInternetInfo.Text = Localization.T("configuration.review.no_internet_info");
        NoUpdatesWarning.Text = Localization.T("configuration.review.no_updates_warning");
        EmptyText.Text = Localization.T("configuration.review.empty");
        PresetLabel.Text = Localization.T("configuration.review.preset");
        BackButton.Content = Localization.T("configuration.review.back");
        ResetButton.Content = Localization.T("configuration.review.reset_defaults");
        AdvancedButton.Content = Localization.T("configuration.review.advanced");
        StartButton.Content = Localization.T("configuration.review.start_button");

        var plan = InstallPlan.LoadInstallPlan();
        var selectedBrowser = plan.GetString("selected_browser_package").Trim();
        NoBrowserChip.Visibility = selectedBrowser.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        NoInternetChip.Visibility = InternetAvailable ? Visibility.Collapsed : Visibility.Visible;
        var updatesEnabled = InstallPlan.IsItemEnabled(plan, "configure-updates");
        NoUpdatesChip.Visibility = updatesEnabled ? Visibility.Collapsed : Visibility.Visible;

        PresetCombo.Items.Clear();
        var presets = StepCatalog.PresetOptions();
        foreach (var preset in presets)
            PresetCombo.Items.Add(preset);
        var selectedKey = plan.GetString("selected_preset_key", StepCatalog.StandardPresetKey);
        var idx = presets.FindIndex(p => p.Key == selectedKey);
        if (idx < 0)
        {
            PresetCombo.Items.Add(new PresetOption("custom", Localization.T("configuration.review.custom_preset")));
            idx = PresetCombo.Items.Count - 1;
        }
        PresetCombo.SelectedIndex = idx;

        var items = InstallPlan.VisibleAllItems(plan)
            .Where(v => v.Key != "developer-mode")
            .Select(v => new ReviewItem(v.Key, v.Text, v.Tooltip, v.IsEnabled))
            .ToList();
        ItemsList.ItemsSource = items;
        EmptyText.Visibility = items.Any(i => i.IsEnabled) ? Visibility.Collapsed : Visibility.Visible;
    }

    private void ToggleItem_Changed(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { Tag: string key } check || !check.IsLoaded)
            return;
        var data = InstallPlan.LoadInstallPlan();
        InstallPlan.SetItemEnabled(data, key, check.IsChecked == true);
        data["include_browser_install"] = InstallPlan.IsItemEnabled(data, "browser-installation");
        InstallPlan.SaveInstallPlan(data);
        Refresh();
    }

    private void PresetCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_presetUpdating) return;
        if (PresetCombo.SelectedItem is not PresetOption preset || preset.Key == "custom")
            return;
        _presetUpdating = true;
        try
        {
            InstallPlan.ApplyPreset(preset.Key);
        }
        catch
        {
            // ignore
        }
        finally
        {
            _presetUpdating = false;
        }
        Refresh();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e) => BackClicked?.Invoke();

    private void ResetButton_Click(object sender, RoutedEventArgs e)
    {
        InstallPlan.ResetInstallPlanDefaults();
        Refresh();
    }

    private void AdvancedButton_Click(object sender, RoutedEventArgs e) => AdvancedClicked?.Invoke();

    private void StartButton_Click(object sender, RoutedEventArgs e)
    {
        var plan = InstallPlan.LoadInstallPlan();
        if (InstallPlan.EnabledPlanKeys(plan).Count == 0)
        {
            ErrorDialog.Show(Localization.T("configuration.review.nothing_to_do"), false);
            return;
        }
        StartClicked?.Invoke();
    }
}

public record ReviewItem(string Key, string Text, string Tooltip, bool IsEnabled = false);
