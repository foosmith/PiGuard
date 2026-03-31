using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;
using PiBarEnhanced.Core.Abstractions;
using PiBarEnhanced.Windows.Views;

namespace PiBarEnhanced.Windows.Services;

public sealed class TrayHost : IDisposable
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IStartupService _startupService;
    private readonly Forms.NotifyIcon _notifyIcon = new();

    private PreferencesWindow? _preferencesWindow;
    private SyncSettingsWindow? _syncSettingsWindow;
    private AboutWindow? _aboutWindow;

    public TrayHost(ISettingsStore settingsStore, ICredentialStore credentialStore, IStartupService startupService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
    }

    public void Initialize()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Preferences", null, (_, _) => ShowPreferences());
        menu.Items.Add("Sync Settings", null, (_, _) => ShowSyncSettings());
        menu.Items.Add("About PiBar Enhanced", null, (_, _) => ShowAbout());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApplication());

        _notifyIcon.Text = "PiBar Enhanced";
        _notifyIcon.Icon = SystemIcons.Application;
        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.Visible = true;
        _notifyIcon.DoubleClick += (_, _) => ShowPreferences();
    }

    private void ShowPreferences() => ShowWindow(
        () => _preferencesWindow,
        window => _preferencesWindow = window,
        () => new PreferencesWindow(_settingsStore, _credentialStore, _startupService));

    private void ShowSyncSettings() => ShowWindow(
        () => _syncSettingsWindow,
        window => _syncSettingsWindow = window,
        () => new SyncSettingsWindow());

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
        _notifyIcon.Dispose();
    }
}
