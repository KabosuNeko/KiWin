namespace KiWin.Utilities;

public interface IErrorDialog
{
    bool Show(string message, bool allowContinue);
    bool Confirm(string message, string title);
}

public static class ErrorDialog
{
    public static IErrorDialog? Implementation { get; set; }

    public static bool Confirm(string message, string title)
    {
        if (Implementation is not null)
        {
            try
            {
                return Implementation.Confirm(message, title);
            }
            catch (Exception e)
            {
                Logger.Exception("Confirm dialog failed", e);
            }
        }
        return false;
    }

    public static bool Show(string message, bool allowContinue = false)
    {
        if (Implementation is not null)
        {
            try
            {
                return Implementation.Show(message, allowContinue);
            }
            catch (Exception e)
            {
                Logger.Exception("Error dialog failed", e);
            }
        }
        Logger.Error(message);
        if (!allowContinue)
        {
            throw new OperationCanceledException(message);
        }
        return true;
    }
}
