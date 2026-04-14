using PiGuard.Core.Models;

namespace PiGuard.Core.Abstractions;

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

public interface INetworkCommandService
{
    Task<OperationExecutionResult> EnableNetworkAsync(CancellationToken cancellationToken = default);
    Task<OperationExecutionResult> DisableNetworkAsync(int? seconds = null, CancellationToken cancellationToken = default);
}

public interface INetworkInsightsService
{
    Task<IReadOnlyDictionary<string, IReadOnlyList<TopItem>>> FetchTopBlockedAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyDictionary<string, IReadOnlyList<TopItem>>> FetchTopClientsAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogAsync(string? serverIdentifier = null, int limit = 100, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<DomainRuleResult>> ApplyDomainRuleAsync(string domain, DomainRuleAction action, CancellationToken cancellationToken = default);
}

public interface ISyncService : IDisposable
{
    event EventHandler<SyncStatusSnapshot>? SyncStatusChanged;

    Task StartAsync(CancellationToken cancellationToken = default);
    Task StopAsync(CancellationToken cancellationToken = default);
    Task TriggerSyncNowAsync(CancellationToken cancellationToken = default);
    Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default);
}

public interface IDnsFilterClient
{
    string ConnectionId { get; }
    Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default);
    Task EnableAsync(CancellationToken cancellationToken = default);
    Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default);
    Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<TopItem>> FetchTopBlockedAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<TopItem>> FetchTopClientsAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogAsync(string serverDisplayName, int limit = 100, CancellationToken cancellationToken = default);
    Task AllowDomainAsync(string domain, CancellationToken cancellationToken = default);
    Task BlockDomainAsync(string domain, CancellationToken cancellationToken = default);
}
