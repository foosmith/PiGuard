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
    private readonly INetworkCommandService _networkCommandService;
    private readonly ISyncService _syncService;
    private readonly Forms.NotifyIcon _notifyIcon = new();
    private readonly Forms.ToolStripMenuItem _statusMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _queriesMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blockedMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blocklistMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _enableMenuItem = new("Enable Blocking");
    private readonly Forms.ToolStripMenuItem _disableMenuItem = new("Disable Blocking");
    private readonly Forms.ToolStripMenuItem _gravityMenuItem = new("Update Gravity");
    private readonly Forms.ToolStripMenuItem _syncMenuItem = new("Sync Now");

    private PreferencesWindow? _preferencesWindow;
    private SyncSettingsWindow? _syncSettingsWindow;
    private AboutWindow? _aboutWindow;
    private PiholeNetworkOverview _lastOverview = new(PiholeNetworkStatus.Initializing, false, 0, 0, 0, 0, []);
    private SyncStatusSnapshot _lastSyncStatus = new(null, null, string.Empty, false, false, []);

    public TrayHost(
        ISettingsStore settingsStore,
        ICredentialStore credentialStore,
        IStartupService startupService,
        IPollingService pollingService,
        INetworkCommandService networkCommandService,
        ISyncService syncService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
        _pollingService = pollingService;
        _networkCommandService = networkCommandService;
        _syncService = syncService;
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
        menu.Items.Add(_enableMenuItem);
        menu.Items.Add(_disableMenuItem);
        menu.Items.Add(_gravityMenuItem);
        menu.Items.Add(_syncMenuItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
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
        _enableMenuItem.Click += async (_, _) => await EnableNetworkAsync();
        _disableMenuItem.Click += async (_, _) => await DisableNetworkAsync();
        _gravityMenuItem.Click += async (_, _) => await TriggerGravityUpdateAsync();
        _syncMenuItem.Click += async (_, _) => await TriggerSyncNowAsync();

        ApplyNetworkOverview(new PiholeNetworkOverview(PiholeNetworkStatus.Initializing, false, 0, 0, 0, 0, []));
        _pollingService.NetworkOverviewUpdated += HandleNetworkOverviewUpdated;
        _syncService.SyncStatusChanged += HandleSyncStatusChanged;
        await _pollingService.StartAsync(cancellationToken);
    }

    private void ShowPreferences() => ShowWindow(
        () => _preferencesWindow,
        window => _preferencesWindow = window,
        () => new PreferencesWindow(_settingsStore, _credentialStore, _startupService));

    private void ShowSyncSettings() => ShowWindow(
        () => _syncSettingsWindow,
        window => _syncSettingsWindow = window,
        () => new SyncSettingsWindow(_settingsStore, _syncService));

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
        _syncService.SyncStatusChanged -= HandleSyncStatusChanged;
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

    private void HandleSyncStatusChanged(object? sender, SyncStatusSnapshot status)
    {
        if (System.Windows.Application.Current.Dispatcher.CheckAccess())
        {
            ApplySyncStatus(status);
            return;
        }

        _ = System.Windows.Application.Current.Dispatcher.InvokeAsync(() => ApplySyncStatus(status));
    }

    private void ApplyNetworkOverview(PiholeNetworkOverview overview)
    {
        _lastOverview = overview;
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
        UpdateActionState();
    }

    private void ApplySyncStatus(SyncStatusSnapshot status)
    {
        _lastSyncStatus = status;
        UpdateActionState();
    }

    private void UpdateActionState()
    {
        var canManage = _lastOverview.CanBeManaged;
        var isBusy = _lastSyncStatus.IsGravityUpdateInProgress || _lastSyncStatus.IsSyncInProgress;
        var v6Count = _lastOverview.Nodes.Count(node => node.IsV6);

        _enableMenuItem.Enabled = canManage &&
            !isBusy &&
            _lastOverview.Status is PiholeNetworkStatus.Disabled;
        _disableMenuItem.Enabled = canManage &&
            !isBusy &&
            _lastOverview.Status is PiholeNetworkStatus.Enabled or PiholeNetworkStatus.PartiallyEnabled;
        _gravityMenuItem.Enabled = canManage && !isBusy && v6Count > 0;
        _syncMenuItem.Enabled = !isBusy && v6Count >= 2;
    }

    private async Task EnableNetworkAsync()
    {
        _statusMenuItem.Text = "Status: Enabling...";
        var result = await _networkCommandService.EnableNetworkAsync();
        _statusMenuItem.Text = BuildCommandSummary("Enabled", result);
    }

    private async Task DisableNetworkAsync()
    {
        _statusMenuItem.Text = "Status: Disabling...";
        var result = await _networkCommandService.DisableNetworkAsync();
        _statusMenuItem.Text = BuildCommandSummary("Disabled", result);
    }

    private async Task TriggerGravityUpdateAsync()
    {
        _statusMenuItem.Text = "Status: Updating gravity...";
        await _syncService.TriggerGravityUpdateAsync();
        _statusMenuItem.Text = "Status: Gravity update finished";
    }

    private async Task TriggerSyncNowAsync()
    {
        _statusMenuItem.Text = "Status: Running sync...";
        await _syncService.TriggerSyncNowAsync();
        _statusMenuItem.Text = "Status: Sync finished";
    }

    private static string BuildCommandSummary(string verb, OperationExecutionResult result)
    {
        if (!result.HasAnyWork && result.Skipped > 0)
        {
            return $"Status: {verb} skipped";
        }

        return $"Status: {verb} {result.Succeeded}, failed {result.Failed}, skipped {result.Skipped}";
    }

    private static string FormatStatus(PiholeNetworkStatus status) => status switch
    {
        PiholeNetworkStatus.PartiallyEnabled => "Partially Enabled",
        PiholeNetworkStatus.PartiallyOffline => "Partially Offline",
        PiholeNetworkStatus.NoneSet => "No Connections",
        _ => status.ToString(),
    };
}
