using System.Drawing;
using System.Diagnostics;
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
    private readonly INetworkInsightsService _networkInsightsService;
    private readonly ISyncService _syncService;
    private readonly Forms.NotifyIcon _notifyIcon = new();
    private readonly Forms.ToolStripMenuItem _statusMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _queriesMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blockedMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _blocklistMenuItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _topBlockedMenuItem = new("Top Blocked");
    private readonly Forms.ToolStripMenuItem _topClientsMenuItem = new("Top Clients");
    private readonly Forms.ToolStripMenuItem _queryLogMenuItem = new("Query Log...");
    private readonly Forms.ToolStripMenuItem _enableMenuItem = new("Enable Blocking");
    private readonly Forms.ToolStripMenuItem _disableMenuItem = new("Disable Blocking");
    private readonly Forms.ToolStripMenuItem _adminConsoleMenuItem = new("Admin Console");
    private readonly Forms.ToolStripMenuItem _gravityMenuItem = new("Update Gravity");
    private readonly Forms.ToolStripMenuItem _syncMenuItem = new("Sync Now");

    private PreferencesWindow? _preferencesWindow;
    private SyncSettingsWindow? _syncSettingsWindow;
    private AboutWindow? _aboutWindow;
    private QueryLogWindow? _queryLogWindow;
    private FloatingStatsPillWindow? _floatingStatsPillWindow;
    private TrayMiniPanelWindow? _trayMiniPanelWindow;
    private PiholeNetworkOverview _lastOverview = new(PiholeNetworkStatus.Initializing, false, 0, 0, 0, 0, []);
    private SyncStatusSnapshot _lastSyncStatus = new(null, null, string.Empty, false, false, []);
    private AppPreferences _preferences = new();

    public TrayHost(
        ISettingsStore settingsStore,
        ICredentialStore credentialStore,
        IStartupService startupService,
        IPollingService pollingService,
        INetworkCommandService networkCommandService,
        INetworkInsightsService networkInsightsService,
        ISyncService syncService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
        _pollingService = pollingService;
        _networkCommandService = networkCommandService;
        _networkInsightsService = networkInsightsService;
        _syncService = syncService;
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        await RefreshPreferencesAsync(cancellationToken);
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += async (_, _) => await HandleMenuOpeningAsync();
        menu.Items.AddRange([
            _statusMenuItem,
            _queriesMenuItem,
            _blockedMenuItem,
            _blocklistMenuItem,
            _topBlockedMenuItem,
            _topClientsMenuItem,
            _queryLogMenuItem,
            new Forms.ToolStripSeparator(),
        ]);
        menu.Items.Add(_enableMenuItem);
        menu.Items.Add(_disableMenuItem);
        menu.Items.Add(_adminConsoleMenuItem);
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
        _notifyIcon.DoubleClick += HandleNotifyIconDoubleClick;
        _notifyIcon.MouseUp += HandleNotifyIconMouseUp;
        _queryLogMenuItem.Click += (_, _) => ShowQueryLog();
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

    private void ShowQueryLog() => ShowWindow(
        () => _queryLogWindow,
        window => _queryLogWindow = window,
        () => new QueryLogWindow(_settingsStore, _networkInsightsService));

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
        _notifyIcon.DoubleClick -= HandleNotifyIconDoubleClick;
        _notifyIcon.MouseUp -= HandleNotifyIconMouseUp;
        _ = _pollingService.StopAsync();
        _notifyIcon.Dispose();
        _floatingStatsPillWindow?.Close();
        _trayMiniPanelWindow?.Close();
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

    private async Task HandleMenuOpeningAsync()
    {
        await RefreshPreferencesAsync();
        await RefreshTopItemsMenuAsync(_topBlockedMenuItem, static service => service.FetchTopBlockedAsync());
        await RefreshTopItemsMenuAsync(_topClientsMenuItem, static service => service.FetchTopClientsAsync());
        await RefreshAdminConsoleMenuAsync();
    }

    private void HandleNotifyIconDoubleClick(object? sender, EventArgs e)
    {
        if (_preferences.EnableTrayMiniPanel)
        {
            return;
        }

        ShowPreferences();
    }

    private void HandleNotifyIconMouseUp(object? sender, Forms.MouseEventArgs e)
    {
        if (e.Button != Forms.MouseButtons.Left || !_preferences.EnableTrayMiniPanel)
        {
            return;
        }

        if (System.Windows.Application.Current.Dispatcher.CheckAccess())
        {
            ToggleTrayMiniPanel();
            return;
        }

        _ = System.Windows.Application.Current.Dispatcher.InvokeAsync(ToggleTrayMiniPanel);
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
        _notifyIcon.Text = BuildTrayText(overview);
        UpdateActionState();
        ApplyFloatingStatsPill();
        ApplyTrayMiniPanel();
        _ = RefreshPreferencesAsync();
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
        _queryLogMenuItem.Enabled = _lastOverview.Nodes.Count > 0;
        _topBlockedMenuItem.Enabled = _lastOverview.Nodes.Count > 0;
        _topClientsMenuItem.Enabled = _lastOverview.Nodes.Count > 0;
        _adminConsoleMenuItem.Enabled = _lastOverview.Nodes.Count > 0;
        _gravityMenuItem.Enabled = canManage && !isBusy && v6Count > 0;
        _syncMenuItem.Enabled = !isBusy && v6Count >= 2;
        ApplyTrayMiniPanel();
    }

    private async Task EnableNetworkAsync()
    {
        _statusMenuItem.Text = "Status: Enabling...";
        try
        {
            var result = await _networkCommandService.EnableNetworkAsync();
            _statusMenuItem.Text = BuildCommandSummary("Enabled", result);
        }
        catch
        {
            _statusMenuItem.Text = "Status: Enable failed";
        }
    }

    private async Task DisableNetworkAsync()
    {
        _statusMenuItem.Text = "Status: Disabling...";
        try
        {
            var result = await _networkCommandService.DisableNetworkAsync();
            _statusMenuItem.Text = BuildCommandSummary("Disabled", result);
        }
        catch
        {
            _statusMenuItem.Text = "Status: Disable failed";
        }
    }

    private async Task TriggerGravityUpdateAsync()
    {
        _statusMenuItem.Text = "Status: Updating gravity...";
        try
        {
            await _syncService.TriggerGravityUpdateAsync();
            _statusMenuItem.Text = "Status: Gravity update finished";
        }
        catch
        {
            _statusMenuItem.Text = "Status: Gravity update failed";
        }
    }

    private async Task TriggerSyncNowAsync()
    {
        _statusMenuItem.Text = "Status: Running sync...";
        try
        {
            await _syncService.TriggerSyncNowAsync();
            _statusMenuItem.Text = "Status: Sync finished";
        }
        catch
        {
            _statusMenuItem.Text = "Status: Sync failed";
        }
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

    private async Task RefreshTopItemsMenuAsync(
        Forms.ToolStripMenuItem menuItem,
        Func<INetworkInsightsService, Task<IReadOnlyDictionary<string, IReadOnlyList<TopItem>>>> fetcher)
    {
        menuItem.DropDownItems.Clear();
        menuItem.DropDownItems.Add("Loading...");

        try
        {
            var preferences = await _settingsStore.LoadAsync();
            var topItems = await fetcher(_networkInsightsService);
            var connections = preferences.Connections
                .OrderBy(connection => $"{connection.Hostname}:{connection.Port}", StringComparer.OrdinalIgnoreCase)
                .ToArray();

            menuItem.DropDownItems.Clear();
            var showServerHeaders = connections.Length > 1;
            for (var index = 0; index < connections.Length; index++)
            {
                var connection = connections[index];
                if (showServerHeaders)
                {
                    if (index > 0)
                    {
                        menuItem.DropDownItems.Add(new Forms.ToolStripSeparator());
                    }

                    menuItem.DropDownItems.Add(new Forms.ToolStripMenuItem($"{connection.Hostname}:{connection.Port}") { Enabled = false });
                }

                if (!topItems.TryGetValue(connection.Id, out var items) || items.Count == 0)
                {
                    menuItem.DropDownItems.Add(new Forms.ToolStripMenuItem("No data") { Enabled = false });
                    continue;
                }

                foreach (var item in items)
                {
                    menuItem.DropDownItems.Add(new Forms.ToolStripMenuItem($"{item.Name} ({item.Count:N0})") { Enabled = false });
                }
            }
        }
        catch
        {
            menuItem.DropDownItems.Clear();
            menuItem.DropDownItems.Add(new Forms.ToolStripMenuItem("Unavailable") { Enabled = false });
        }
    }

    private async Task RefreshAdminConsoleMenuAsync()
    {
        _adminConsoleMenuItem.DropDownItems.Clear();

        try
        {
            var preferences = await _settingsStore.LoadAsync();
            if (preferences.Connections.Count == 0)
            {
                _adminConsoleMenuItem.Enabled = false;
                _adminConsoleMenuItem.DropDownItems.Add(new Forms.ToolStripMenuItem("No connections") { Enabled = false });
                return;
            }

            foreach (var connection in preferences.Connections.OrderBy(connection => $"{connection.Hostname}:{connection.Port}", StringComparer.OrdinalIgnoreCase))
            {
                var item = new Forms.ToolStripMenuItem($"{connection.Hostname}:{connection.Port}");
                item.Click += (_, _) => LaunchAdminConsole(connection.AdminUrl);
                _adminConsoleMenuItem.DropDownItems.Add(item);
            }

            _adminConsoleMenuItem.Enabled = true;
        }
        catch
        {
            _adminConsoleMenuItem.Enabled = false;
            _adminConsoleMenuItem.DropDownItems.Add(new Forms.ToolStripMenuItem("Unavailable") { Enabled = false });
        }
    }

    private static void LaunchAdminConsole(string adminUrl)
    {
        if (string.IsNullOrWhiteSpace(adminUrl))
        {
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = adminUrl,
            UseShellExecute = true,
        });
    }

    private async Task RefreshPreferencesAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            _preferences = await _settingsStore.LoadAsync(cancellationToken);
            ApplyFloatingStatsPill();
            ApplyTrayMiniPanel();
            _notifyIcon.Text = BuildTrayText(_lastOverview);
        }
        catch
        {
        }
    }

    private string BuildTrayText(PiholeNetworkOverview overview)
    {
        var trayText = _preferences.EnableRichTrayTooltip
            ? overview.Status switch
            {
                PiholeNetworkStatus.Enabled or PiholeNetworkStatus.PartiallyEnabled =>
                    $"PiGuard {overview.TotalQueriesToday:N0}q {overview.AdsBlockedToday:N0}b {overview.AdsPercentageToday:F1}%",
                PiholeNetworkStatus.PartiallyOffline => $"PiGuard partial {overview.TotalQueriesToday:N0}q",
                PiholeNetworkStatus.Disabled => "PiGuard blocking disabled",
                PiholeNetworkStatus.Offline => "PiGuard offline",
                PiholeNetworkStatus.NoneSet => "PiGuard no connections",
                _ => "PiGuard refreshing",
            }
            : overview.Status switch
            {
                PiholeNetworkStatus.Enabled => $"PiGuard: {overview.TotalQueriesToday:N0} queries",
                PiholeNetworkStatus.PartiallyEnabled => "PiGuard: partially enabled",
                PiholeNetworkStatus.PartiallyOffline => "PiGuard: partially offline",
                PiholeNetworkStatus.Disabled => "PiGuard: blocking disabled",
                PiholeNetworkStatus.Offline => "PiGuard: offline",
                PiholeNetworkStatus.NoneSet => "PiGuard: no connections configured",
                _ => "PiGuard: initializing",
            };

        return trayText.Length <= 63 ? trayText : trayText[..63];
    }

    private void ApplyFloatingStatsPill()
    {
        if (!_preferences.EnableFloatingStatsPill)
        {
            _floatingStatsPillWindow?.Hide();
            return;
        }

        _floatingStatsPillWindow ??= CreateFloatingStatsPillWindow();
        _floatingStatsPillWindow.ApplyOverview(_lastOverview);
        _floatingStatsPillWindow.PositionBottomRight();
        if (!_floatingStatsPillWindow.IsVisible)
        {
            _floatingStatsPillWindow.Show();
        }
    }

    private void ApplyTrayMiniPanel()
    {
        if (_trayMiniPanelWindow is null)
        {
            return;
        }

        _trayMiniPanelWindow.ApplyOverview(_lastOverview, _lastOverview.CanBeManaged && !(_lastSyncStatus.IsGravityUpdateInProgress || _lastSyncStatus.IsSyncInProgress));
        _trayMiniPanelWindow.PositionBottomRight();

        if (!_preferences.EnableTrayMiniPanel)
        {
            _trayMiniPanelWindow.Hide();
        }
    }

    private void ToggleTrayMiniPanel()
    {
        _trayMiniPanelWindow ??= CreateTrayMiniPanelWindow();
        if (_trayMiniPanelWindow.IsVisible)
        {
            _trayMiniPanelWindow.Hide();
            return;
        }

        _trayMiniPanelWindow.ApplyOverview(_lastOverview, _lastOverview.CanBeManaged && !(_lastSyncStatus.IsGravityUpdateInProgress || _lastSyncStatus.IsSyncInProgress));
        _trayMiniPanelWindow.PositionBottomRight();
        _trayMiniPanelWindow.Show();
        _trayMiniPanelWindow.Activate();
    }

    private FloatingStatsPillWindow CreateFloatingStatsPillWindow()
    {
        var window = new FloatingStatsPillWindow();
        window.PositionBottomRight();
        window.Closed += (_, _) => _floatingStatsPillWindow = null;
        return window;
    }

    private TrayMiniPanelWindow CreateTrayMiniPanelWindow()
    {
        var window = new TrayMiniPanelWindow();
        window.RefreshRequested += async (_, _) => await RefreshNowAsync();
        window.EnableRequested += async (_, _) => await EnableNetworkAsync();
        window.DisableRequested += async (_, _) => await DisableNetworkAsync();
        window.Closed += (_, _) => _trayMiniPanelWindow = null;
        return window;
    }
}
