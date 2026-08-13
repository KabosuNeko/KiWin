using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace KiWin.App.Controls;

public partial class SpinnerControl : UserControl
{
    private DoubleAnimation? _animation;

    public SpinnerControl()
    {
        InitializeComponent();
    }

    public void Start()
    {
        if (_animation is not null) return;
        _animation = new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(1200))
        {
            RepeatBehavior = RepeatBehavior.Forever,
        };
        Arc.BeginAnimation(RotateTransform.AngleProperty, _animation);
    }

    public void Stop()
    {
        if (_animation is null) return;
        Arc.BeginAnimation(RotateTransform.AngleProperty, null);
        _animation = null;
    }
}
