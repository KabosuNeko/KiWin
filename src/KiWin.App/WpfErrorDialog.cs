using System.Windows;
using KiWin.Core;
using KiWin.Utilities;

namespace KiWin.App;

public class WpfErrorDialog : IErrorDialog
{
    public bool Show(string message, bool allowContinue)
    {
        if (Application.Current is not null &&
            Application.Current.Dispatcher.Thread != Thread.CurrentThread)
        {
            var result = false;
            Application.Current.Dispatcher.Invoke(() => result = ShowCore(message, allowContinue));
            return result;
        }
        return ShowCore(message, allowContinue);
    }

    private static bool ShowCore(string message, bool allowContinue)
    {
        var title = Localization.T("errors.dialog_title");
        if (!allowContinue)
        {
            var stopText = Localization.T("errors.stop_installation");
            var box = MessageBox.Show(message, title, MessageBoxButton.OK, MessageBoxImage.Error,
                MessageBoxResult.OK, MessageBoxOptions.None);
            return box == MessageBoxResult.OK && false;
        }
        var continueText = Localization.T("errors.continue_anyways");
        var result = MessageBox.Show(message + $"\n\n[{continueText}] / [{Localization.T("errors.stop_installation")}]",
            title, MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        return result == MessageBoxResult.Yes;
    }
}
