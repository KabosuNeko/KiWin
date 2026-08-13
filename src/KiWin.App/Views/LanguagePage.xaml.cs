using System.Windows;
using System.Windows.Controls;
using KiWin.Core;

namespace KiWin.App.Views;

public partial class LanguagePage : UserControl
{
    public event Action? LanguageChanged;
    public event Action? BackClicked;

    public LanguagePage()
    {
        InitializeComponent();
        Refresh();
    }

    public void Refresh()
    {
        BackButton.Content = Localization.T("configuration.dialogs.cancel");
        LanguageList.Items.Clear();
        var languages = Localization.AvailableLanguages();
        foreach (var language in languages)
            LanguageList.Items.Add(language);
        var current = Localization.CurrentLanguage;
        var idx = languages.FindIndex(l => l.Code == current);
        LanguageList.SelectedIndex = idx;
    }

    private void LanguageList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LanguageList.SelectedItem is not LanguageInfo language) return;
        var before = Localization.CurrentLanguage;
        var ok = Localization.SetLanguage(language.Code);
        if (ok && Localization.CurrentLanguage != before)
            LanguageChanged?.Invoke();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e) => BackClicked?.Invoke();
}
