using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;
using PiGuard.Windows.Views;

namespace PiGuard.Windows.Services;

public sealed class TrayHost : IDisposable
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IStartupService _startupService;
    private readonly IPollingService _pollingService;
    private readonly Forms.NotifyIcon _notifyIcon = new();
    private readonly Forms.ToolStripMenuItem _statusMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _queriesMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blockedMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blocklistMenuItem = new() { Enabled = false };

    private PreferencesWindow? _preferencesWindow;
    private SyncSettingsWindow? _syncSettingsWindow;
    private AboutWindow? _aboutWindow;

    public TrayHost(ISettingsStore settingsStore, ICredentialStore credentialStore, IStartupService startupService, IPollingService pollingService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
        _pollingService = pollingService;
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.AddRange([
            _statusMenuItem,
            _queriesMenuItem,
            _blockedMenuItem,
            _blocklistMenuItem,
            new Forms.ToolStripSeparator(),
        ]);
        menu.Items.Add("Refresh Now", null, async (_, _) => await RefreshNowAsync());
        menu.Items.Add("Preferences", null, (_, _) => ShowPreferences());
        menu.Items.Add("Sync Settings", null, (_, _) => ShowSyncSettings());
        menu.Items.Add("About PiGuard", null, (_, _) => ShowAbout());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApplication());

        _notifyIcon.Text = "PiGuard";
        _notifyIcon.Icon = SystemIcons.Application;
        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.Visible = true;
        _notifyIcon.DoubleClick += (_, _) => ShowPreferences();

        ApplyNetworkOverview(new PiholeNetworkOverview(PiholeNetworkStatus.Initializing, false, 0, 0, 0, 0, []));
        _pollingService.NetworkOverviewUpdated += HandleNetworkOverviewUpdated;
        await _pollingService.StartAsync(cancellationToken);
    }

    private void ShowPreferences() => ShowWindow(
        () => _preferencesWindow,
        window => _preferencesWindow = window,
        () => new PreferencesWindow(_settingsStore, _credentialStore, _startupService));

    private void ShowSyncSettings() => ShowWindow(
        () => _syncSettingsWindow,
        window => _syncSettingsWindow = window,
        () => new SyncSettingsWindow(_settingsStore));

    private void ShowAbout() => ShowWindow(
        () => _aboutWindow,
        window => _aboutWindow = window,
        () => new AboutWindow());

    private static void ShowWindow<TWindow>(
        Func<TWindow?> getter,
        Action<TWindow?> setter,
        Func<TWindow> factory)
        where TWindow : Window
    {
        var currentWindow = getter();
        if (currentWindow is null || !currentWindow.IsLoaded)
        {
            currentWindow = factory();
            currentWindow.Closed += (_, _) => setter(null);
            setter(currentWindow);
            currentWindow.Show();
            currentWindow.Activate();
            return;
        }

        if (currentWindow.WindowState == WindowState.Minimized)
        {
            currentWindow.WindowState = WindowState.Normal;
        }

        currentWindow.Show();
        currentWindow.Activate();
    }

    private void ExitApplication()
    {
        _notifyIcon.Visible = false;
        System.Windows.Application.Current.Shutdown();
    }

    public void Dispose()
    {
        _pollingService.NetworkOverviewUpdated -= HandleNetworkOverviewUpdated;
        _pollingService.StopAsync().GetAwaiter().GetResult();
        _notifyIcon.Dispose();
    }

    private async Task RefreshNowAsync()
    {
        try
        {
            _statusMenuItem.Text = "Status: Refreshing...";
            await _pollingService.RefreshNowAsync();
        }
        catch
        {
            _statusMenuItem.Text = "Status: Refresh failed";
        }
    }

    private void HandleNetworkOverviewUpdated(object? sender, PiholeNetworkOverview overview)
    {
        if (System.Windows.Application.Current.Dispatcher.CheckAccess())
        {
            ApplyNetworkOverview(overview);
            return;
        }

        _ = System.Windows.Application.Current.Dispatcher.InvokeAsync(() => ApplyNetworkOverview(overview));
    }

    private void ApplyNetworkOverview(PiholeNetworkOverview overview)
    {
        _statusMenuItem.Text = $"Status: {FormatStatus(overview.Status)}";
        _queriesMenuItem.Text = $"Queries: {overview.TotalQueriesToday:N0}";
        _blockedMenuItem.Text = $"Blocked: {overview.AdsBlockedToday:N0} ({overview.AdsPercentageToday:F1}%)";
        _blocklistMenuItem.Text = $"Blocklist: {overview.AverageBlocklist:N0}";

        var trayText = overview.Status switch
        {
            PiholeNetworkStatus.Enabled => $"PiGuard: {overview.TotalQueriesToday:N0} queries",
            PiholeNetworkStatus.PartiallyEnabled => "PiGuard: partially enabled",
            PiholeNetworkStatus.PartiallyOffline => "PiGuard: partially offline",
            PiholeNetworkStatus.Disabled => "PiGuard: blocking disabled",
            PiholeNetworkStatus.Offline => "PiGuard: offline",
            PiholeNetworkStatus.NoneSet => "PiGuard: no connections configured",
            _ => "PiGuard: initializing",
        };

        _notifyIcon.Text = trayText.Length <= 63 ? trayText : trayText[..63];
    }

    private static string FormatStatus(PiholeNetworkStatus status) => status switch
    {
        PiholeNetworkStatus.PartiallyEnabled => "Partially Enabled",
        PiholeNetworkStatus.PartiallyOffline => "Partially Offline",
        PiholeNetworkStatus.NoneSet => "No Connections",
        _ => status.ToString(),
    };
}
