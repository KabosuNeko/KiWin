using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using KiWin.Core;

namespace KiWin.App.Views;

public partial class BrowserPage : UserControl
{
    public event Action<string, string>? BrowserSelected;
    public event Action? SkipClicked;

    public BrowserPage()
    {
        InitializeComponent();
        Refresh();
    }

    public void Refresh()
    {
        TitleText.Text = Localization.T("configuration.browser.title");
        SubtitleText.Text = Localization.T("configuration.browser.subtitle");
        SkipButton.Content = Localization.T("configuration.browser.skip");
        var list = new List<BrowserItem>();
        foreach (var b in StepCatalog.BrowserOptionsLocalized())
        {
            var iconFile = Path.Combine(Logger.BasePath(), "media", b.Icon);
            BitmapImage? icon = null;
            if (File.Exists(iconFile))
                icon = new BitmapImage(new Uri(iconFile));
            list.Add(new BrowserItem(b.PackageId, b.Name, icon, b.Tooltip));
        }
        BrowserGrid.ItemsSource = list;
    }

    private void BrowserButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string packageId } && BrowserGrid.ItemsSource is IEnumerable<BrowserItem> items)
        {
            var item = items.FirstOrDefault(i => i.PackageId == packageId);
            BrowserSelected?.Invoke(packageId, item?.Name ?? packageId);
        }
    }

    private void SkipButton_Click(object sender, RoutedEventArgs e) => SkipClicked?.Invoke();
}

public record BrowserItem(string PackageId, string Name, BitmapImage? IconPath, string Tooltip);
