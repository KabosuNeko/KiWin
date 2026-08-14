using System.Windows;
using System.Windows.Threading;
using KiWin.Core;

namespace KiWin.App;

public partial class InstallOverlayWindow : Window
{
    public InstallOverlayWindow()
    {
        InitializeComponent();
        ApplyAppIcon();
        Loaded += (_, _) =>
        {
            TitleText.Text = Localization.T("app.install_overlay.title");
            GuidanceText.Text = Localization.T("app.install_overlay.guidance");
            Spinner.Start();
        };
    }

    private void ApplyAppIcon()
    {
        try
        {
            var iconPath = AppPaths.Resolve(@"media\ICON.ico");
            if (!File.Exists(iconPath)) return;
            var icon = new System.Windows.Media.Imaging.BitmapImage(new Uri(iconPath));
            Icon = icon;
            LogoIcon.Source = icon;
        }
        catch
        {
        }
    }

    public void SetStatus(string message)
    {
        Dispatcher.Invoke(() => StatusText.Text = message);
    }

    public void StopSpinner()
    {
        Dispatcher.Invoke(() => Spinner.Stop());
    }
}
