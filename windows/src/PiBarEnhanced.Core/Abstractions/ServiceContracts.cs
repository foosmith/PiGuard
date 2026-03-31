using PiBarEnhanced.Core.Models;

namespace PiBarEnhanced.Core.Abstractions;

public interface ISettingsStore
{
    Task<AppPreferences> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default);
}

public interface ICredentialStore
{
    Task<string?> ReadSecretAsync(string accountKey, CancellationToken cancellationToken = default);
    Task WriteSecretAsync(string accountKey, string value, CancellationToken cancellationToken = default);
    Task DeleteSecretAsync(string accountKey, CancellationToken cancellationToken = default);
}

public interface INotificationService
{
    Task ShowInfoAsync(string title, string message, CancellationToken cancellationToken = default);
    Task ShowErrorAsync(string title, string message, CancellationToken cancellationToken = default);
}

public interface IStartupService
{
    Task<bool> IsEnabledAsync(CancellationToken cancellationToken = default);
    Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken = default);
}

public interface IHotkeyService
{
    Task RegisterAsync(CancellationToken cancellationToken = default);
    Task UnregisterAsync(CancellationToken cancellationToken = default);
}

public interface IPollingService
{
    event EventHandler<PiholeNetworkOverview>? NetworkOverviewUpdated;

    Task StartAsync(CancellationToken cancellationToken = default);
    Task StopAsync(CancellationToken cancellationToken = default);
    Task RefreshNowAsync(CancellationToken cancellationToken = default);
}

public interface ISyncService
{
    event EventHandler<SyncStatusSnapshot>? SyncStatusChanged;

    Task TriggerSyncNowAsync(CancellationToken cancellationToken = default);
    Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default);
}

public interface IPiholeClientV5
{
    string ConnectionId { get; }
    Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default);
    Task EnableAsync(CancellationToken cancellationToken = default);
    Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default);
}

public interface IPiholeClientV6
{
    string ConnectionId { get; }
    Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default);
    Task EnableAsync(CancellationToken cancellationToken = default);
    Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default);
    Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default);
}
