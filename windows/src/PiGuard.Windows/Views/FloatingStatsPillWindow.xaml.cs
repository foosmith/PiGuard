using System.Windows;
using System.Windows.Input;
using Media = System.Windows.Media;
using PiGuard.Core.Models;

namespace PiGuard.Windows.Views;

public partial class FloatingStatsPillWindow : Window
{
    public FloatingStatsPillWindow()
    {
        InitializeComponent();
        MouseLeftButtonDown += HandleMouseLeftButtonDown;
    }

    public void ApplyOverview(PiholeNetworkOverview overview)
    {
        var (headline, badgeText, badgeColor) = overview.Status switch
        {
            PiholeNetworkStatus.Enabled => ("Network online", "LIVE", Media.Color.FromRgb(0x17, 0x92, 0x70)),
            PiholeNetworkStatus.Disabled => ("Blocking paused", "PAUSED", Media.Color.FromRgb(0xC4, 0x8A, 0x2C)),
            PiholeNetworkStatus.PartiallyEnabled => ("Partially enabled", "MIXED", Media.Color.FromRgb(0x49, 0x7E, 0xD8)),
            PiholeNetworkStatus.PartiallyOffline => ("Partially offline", "WARN", Media.Color.FromRgb(0xB8, 0x5C, 0x2E)),
            PiholeNetworkStatus.Offline => ("All nodes offline", "DOWN", Media.Color.FromRgb(0xA6, 0x3B, 0x52)),
            PiholeNetworkStatus.NoneSet => ("No connections", "IDLE", Media.Color.FromRgb(0x5F, 0x6B, 0x7A)),
            _ => ("Refreshing now", "SYNC", Media.Color.FromRgb(0x5B, 0x79, 0xD6)),
        };

        HeadlineTextBlock.Text = headline;
        StatusBadgeTextBlock.Text = badgeText;
        StatusBadgeBrush.Color = badgeColor;
        QueriesValueTextBlock.Text = overview.TotalQueriesToday.ToString("N0");
        BlockedValueTextBlock.Text = overview.AdsBlockedToday.ToString("N0");
        PercentValueTextBlock.Text = $"{overview.AdsPercentageToday:F1}%";
    }

    public void PositionBottomRight()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 20;
        Top = area.Bottom - Height - 20;
    }

    private void HandleMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
        }
    }
}
