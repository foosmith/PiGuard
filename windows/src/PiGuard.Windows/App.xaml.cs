using System.IO;
using System.Windows;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Services;
using PiGuard.Windows.Services;

namespace PiGuard.Windows;

public partial class App : System.Windows.Application
{
    private TrayHost? _trayHost;
    private ISyncService? _syncService;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        var appDataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PiGuard");

        var settingsStore = new JsonSettingsStore(Path.Combine(appDataRoot, "settings.json"));
        var credentialStore = new WindowsCredentialStore(appDataRoot);
        var startupService = new WindowsStartupService("PiGuard", "PiGuard.Windows.exe");
        var pollingService = new PiholePollingService(settingsStore, credentialStore);
        var networkCommandService = new NetworkCommandService(settingsStore, credentialStore, pollingService);
        _syncService = new SyncOrchestrationService(settingsStore, credentialStore, pollingService);

        await _syncService.StartAsync();

        _trayHost = new TrayHost(
            settingsStore,
            credentialStore,
            startupService,
            pollingService,
            networkCommandService,
            _syncService);
        await _trayHost.InitializeAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayHost?.Dispose();
        _ = _syncService?.StopAsync();
        _syncService?.Dispose();
        base.OnExit(e);
    }
}
