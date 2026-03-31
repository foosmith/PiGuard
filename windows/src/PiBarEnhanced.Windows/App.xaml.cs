using System.IO;
using System.Windows;
using PiBarEnhanced.Core.Services;
using PiBarEnhanced.Windows.Services;

namespace PiBarEnhanced.Windows;

public partial class App : System.Windows.Application
{
    private TrayHost? _trayHost;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        var appDataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PiBarEnhanced");

        var settingsStore = new JsonSettingsStore(Path.Combine(appDataRoot, "settings.json"));
        var credentialStore = new WindowsCredentialStore(appDataRoot);
        var startupService = new WindowsStartupService("PiBarEnhanced", "PiBarEnhanced.Windows.exe");
        var pollingService = new PiholePollingService(settingsStore, credentialStore);

        _trayHost = new TrayHost(settingsStore, credentialStore, startupService, pollingService);
        await _trayHost.InitializeAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayHost?.Dispose();
        base.OnExit(e);
    }
}
