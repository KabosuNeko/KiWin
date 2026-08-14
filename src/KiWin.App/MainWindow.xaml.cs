using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.App;

public partial class MainWindow : Window
{
    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    private const int DwmwaUseImmersiveDarkMode = 20;

    private UserControl? _currentPage;
    private UserControl? _pageBeforeLanguage;

    public event Action? StartTriggered;

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
        catch (Exception e)
        {
            Logger.Exception("Failed to load app icon", e);
        }
    }

    public MainWindow()
    {
        InitializeComponent();
        ApplyAppIcon();
        SourceInitialized += (_, _) => SetDarkTitleBar();
        BrowserPage.BrowserSelected += (packageId, name) =>
        {
            try
            {
                InstallPlan.SetBrowser(packageId, name);
            }
            catch (Exception e)
            {
                Logger.Exception("Failed to set browser", e);
            }
            NavigateTo(ReviewPage);
        };
        BrowserPage.SkipClicked += () =>
        {
            try
            {
                InstallPlan.SkipBrowserInstall();
            }
            catch (Exception e)
            {
                Logger.Exception("Failed to skip browser install", e);
            }
            NavigateTo(ReviewPage);
        };
        ReviewPage.BackClicked += () => NavigateTo(BrowserPage);
        ReviewPage.AdvancedClicked += () => NavigateTo(AdvancedPage);
        ReviewPage.StartClicked += () =>
        {
            StartTriggered?.Invoke();
            Close();
        };
        AdvancedPage.BackClicked += () => NavigateTo(ReviewPage);
        LanguagePage.BackClicked += () => NavigateTo(_pageBeforeLanguage ?? ReviewPage);
        LanguagePage.LanguageChanged += () => RefreshAllText();

        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        RefreshAllText();
        NavigateTo(BrowserPage);
        System.Threading.Tasks.Task.Run(() =>
        {
            try
            {
                var (internetAvailable, relaunched) = Preflight.RunConfigurationPreflight();
                Dispatcher.Invoke(() =>
                {
                    if (relaunched)
                    {
                        Close();
                        return;
                    }
                    try
                    {
                        InstallPlan.ApplyInternetAvailability(internetAvailable);
                    }
                    catch (Exception ex)
                    {
                        Logger.Exception("Failed to apply internet availability", ex);
                    }
                    ReviewPage.SetInternetAvailable(internetAvailable);
                });
            }
            catch (Exception ex)
            {
                Logger.Exception("Configuration preflight failed", ex);
                Dispatcher.Invoke(() => Close());
            }
        });
    }

    private void SetDarkTitleBar()
    {
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            var useDark = 1;
            DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref useDark, sizeof(int));
        }
        catch (Exception e)
        {
            Logger.Debug($"Failed to set dark title bar: {e.Message}");
        }
    }

    private void NavigateTo(UserControl page)
    {
        if (page == LanguagePage)
            _pageBeforeLanguage = _currentPage;
        _currentPage = page;
        BrowserPage.Visibility = page == BrowserPage ? Visibility.Visible : Visibility.Collapsed;
        ReviewPage.Visibility = page == ReviewPage ? Visibility.Visible : Visibility.Collapsed;
        AdvancedPage.Visibility = page == AdvancedPage ? Visibility.Visible : Visibility.Collapsed;
        LanguagePage.Visibility = page == LanguagePage ? Visibility.Visible : Visibility.Collapsed;
        if (page == ReviewPage) ReviewPage.Refresh();
        if (page == AdvancedPage) AdvancedPage.Refresh();
        if (page == LanguagePage) LanguagePage.Refresh();
    }

    private void RefreshAllText()
    {
        Title = "KiWin";
        TitleBarLanguage.Text = Localization.T("configuration.advanced.language") == "configuration.advanced.language"
            ? "🌐 Language"
            : "🌐 " + Localization.T("configuration.advanced.language");
        BrowserPage.Refresh();
        ReviewPage.Refresh();
        AdvancedPage.Refresh();
    }

    private void TitleBarLanguage_Click(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        NavigateTo(LanguagePage);
    }
}
