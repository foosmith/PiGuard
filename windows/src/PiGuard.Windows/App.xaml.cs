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
    private PiholePollingService? _pollingService;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        try
        {
            var appDataRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "PiGuard");

            var settingsStore = new JsonSettingsStore(Path.Combine(appDataRoot, "settings.json"));
            var credentialStore = new WindowsCredentialStore(appDataRoot);
            var startupService = new WindowsStartupService("PiGuard", "PiGuard.Windows.exe");
            _pollingService = new PiholePollingService(settingsStore, credentialStore);
            var networkCommandService = new NetworkCommandService(settingsStore, credentialStore, _pollingService);
            _syncService = new SyncOrchestrationService(settingsStore, credentialStore, _pollingService);

            await _syncService.StartAsync();

            _trayHost = new TrayHost(
                settingsStore,
                credentialStore,
                startupService,
                _pollingService,
                networkCommandService,
                _syncService);
            await _trayHost.InitializeAsync();
        }
        catch (Exception exception)
        {
            System.Windows.MessageBox.Show(
                $"PiGuard failed to start: {exception.Message}",
                "PiGuard",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayHost?.Dispose();
        _ = _syncService?.StopAsync();
        _syncService?.Dispose();
        _pollingService?.Dispose();
        base.OnExit(e);
    }
}
