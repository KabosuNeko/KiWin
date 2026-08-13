using System.Windows;
using System.Windows.Threading;
using KiWin.Core;

namespace KiWin.App;

public partial class InstallOverlayWindow : Window
{
    public InstallOverlayWindow()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            TitleText.Text = Localization.T("app.install_overlay.title");
            GuidanceText.Text = Localization.T("app.install_overlay.guidance");
            Spinner.Start();
        };
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
