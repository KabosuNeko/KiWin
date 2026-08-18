using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using KiWin.Core;

namespace KiWin.App;

public partial class InstallOverlayWindow : Window
{
    private const int MaxLogLines = 500;

    public event Action? CancelRequested;

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
            var icon = new BitmapImage(new Uri(iconPath));
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

    public void SetLogLine(string line)
    {
        Dispatcher.BeginInvoke(() =>
        {
            LogList.Items.Add(line);
            while (LogList.Items.Count > MaxLogLines)
                LogList.Items.RemoveAt(0);
            LogList.ScrollIntoView(LogList.Items[LogList.Items.Count - 1]);
        });
    }

    public void StopSpinner()
    {
        Dispatcher.Invoke(() => Spinner.Stop());
    }

    private void Root_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
            CancelRequested?.Invoke();
    }
}
