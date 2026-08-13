namespace KiWin.Utilities;

public interface IErrorDialog
{
    bool Show(string message, bool allowContinue);
}

public static class ErrorDialog
{
    public static IErrorDialog? Implementation { get; set; }

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
