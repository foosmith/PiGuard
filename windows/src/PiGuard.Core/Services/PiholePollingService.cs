using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class PiholePollingService : IPollingService, IDisposable
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);

    private CancellationTokenSource? _lifetimeCts;
    private Task? _backgroundTask;

    public PiholePollingService(ISettingsStore settingsStore, ICredentialStore credentialStore)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
    }

    public event EventHandler<PiholeNetworkOverview>? NetworkOverviewUpdated;

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_backgroundTask is not null)
        {
            return Task.CompletedTask;
        }

        _lifetimeCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _backgroundTask = RunAsync(_lifetimeCts.Token);
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (_lifetimeCts is null || _backgroundTask is null)
        {
            return;
        }

        var lifetimeCts = _lifetimeCts;
        await lifetimeCts.CancelAsync();

        try
        {
            await _backgroundTask.WaitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            lifetimeCts.Dispose();
            _lifetimeCts = null;
            _backgroundTask = null;
        }
    }

    public async Task RefreshNowAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        await RefreshWithPreferencesAsync(preferences, cancellationToken);
    }

    public void Dispose()
    {
        var lifetimeCts = Interlocked.Exchange(ref _lifetimeCts, null);
        lifetimeCts?.Cancel();
        lifetimeCts?.Dispose();
        _backgroundTask = null;
        _refreshGate.Dispose();
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        NetworkOverviewUpdated?.Invoke(this, BuildInitialOverview(preferences));
        await RefreshWithPreferencesAsync(preferences, cancellationToken);

        while (!cancellationToken.IsCancellationRequested)
        {
            preferences = await _settingsStore.LoadAsync(cancellationToken);
            var interval = TimeSpan.FromSeconds(Math.Max(1, preferences.PollingRateSeconds));

            try
            {
                await Task.Delay(interval, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            await RefreshWithPreferencesAsync(preferences, cancellationToken);
        }
    }

    private async Task RefreshWithPreferencesAsync(AppPreferences preferences, CancellationToken cancellationToken)
    {
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            var overview = await PollNetworkAsync(preferences, cancellationToken);
            NetworkOverviewUpdated?.Invoke(this, overview);
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    private async Task<PiholeNetworkOverview> PollNetworkAsync(AppPreferences preferences, CancellationToken cancellationToken)
    {
        if (preferences.Connections.Count == 0)
        {
            return new PiholeNetworkOverview(PiholeNetworkStatus.NoneSet, false, 0, 0, 0, 0, []);
        }

        var pollTasks = preferences.Connections
            .Select(connection => PollConnectionAsync(connection, cancellationToken))
            .ToArray();

        var nodes = await Task.WhenAll(pollTasks);
        var onlineNodes = nodes.Where(node => node.Online).ToArray();
        var totalQueries = onlineNodes.Sum(node => node.TotalQueriesToday);
        var blockedQueries = onlineNodes.Sum(node => node.AdsBlockedToday);
        var blocklistAverage = onlineNodes.Length == 0
            ? 0
            : (int)Math.Round(onlineNodes.Average(node => node.DomainsBeingBlocked), MidpointRounding.AwayFromZero);

        var percentageBlocked = totalQueries == 0
            ? 0
            : (double)blockedQueries / totalQueries * 100;

        return new PiholeNetworkOverview(
            DetermineStatus(nodes),
            CanManage(nodes),
            totalQueries,
            blockedQueries,
            percentageBlocked,
            blocklistAverage,
            nodes.OrderBy(node => node.DisplayName, StringComparer.OrdinalIgnoreCase).ToArray());
    }

    private async Task<PiholeStatusSnapshot> PollConnectionAsync(ConnectionConfig connection, CancellationToken cancellationToken)
    {
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        var canBeManaged = !connection.PasswordProtected || !string.IsNullOrWhiteSpace(secret);

        try
        {
            return await CreateClient(connection, secret).FetchStatusAsync(cancellationToken);
        }
        catch (PiholeApiException)
        {
            return BuildOfflineSnapshot(connection, canBeManaged);
        }
        catch (HttpRequestException)
        {
            return BuildOfflineSnapshot(connection, canBeManaged);
        }
    }

    private static IDnsFilterClient CreateClient(ConnectionConfig connection, string? secret) =>
        connection.Version switch
        {
            ConnectionVersion.V6 => new PiholeClientV6(connection, secret),
            ConnectionVersion.AdGuardHome => new AdGuardHomeClient(connection, secret),
            _ => new PiholeClientV5(connection, secret),
        };

    private static PiholeStatusSnapshot BuildOfflineSnapshot(ConnectionConfig connection, bool canBeManaged) =>
        new(
            connection.Id,
            $"{connection.Hostname}:{connection.Port}",
            Online: false,
            CanBeManaged: canBeManaged,
            Enabled: null,
            IsV6: connection.Version == ConnectionVersion.V6,
            TotalQueriesToday: 0,
            AdsBlockedToday: 0,
            AdsPercentageToday: 0,
            DomainsBeingBlocked: 0);

    private static PiholeNetworkOverview BuildInitialOverview(AppPreferences preferences) =>
        preferences.Connections.Count == 0
            ? new PiholeNetworkOverview(PiholeNetworkStatus.NoneSet, false, 0, 0, 0, 0, [])
            : new PiholeNetworkOverview(PiholeNetworkStatus.Initializing, false, 0, 0, 0, 0, []);

    private static bool CanManage(IEnumerable<PiholeStatusSnapshot> nodes) =>
        nodes.Any(node => node.CanBeManaged ?? false);

    private static PiholeNetworkStatus DetermineStatus(IReadOnlyCollection<PiholeStatusSnapshot> nodes)
    {
        if (nodes.Count == 0)
        {
            return PiholeNetworkStatus.NoneSet;
        }

        var onlineNodes = nodes.Where(node => node.Online).ToArray();
        if (onlineNodes.Length == 0)
        {
            return PiholeNetworkStatus.Offline;
        }

        if (onlineNodes.Length < nodes.Count)
        {
            return PiholeNetworkStatus.PartiallyOffline;
        }

        var enabledStates = onlineNodes
            .Select(node => node.Enabled)
            .Where(enabled => enabled.HasValue)
            .Select(enabled => enabled!.Value)
            .Distinct()
            .ToArray();

        if (enabledStates.Length == 0)
        {
            return PiholeNetworkStatus.Initializing;
        }

        if (enabledStates.Length == 1)
        {
            return enabledStates[0] ? PiholeNetworkStatus.Enabled : PiholeNetworkStatus.Disabled;
        }

        return PiholeNetworkStatus.PartiallyEnabled;
    }
}
