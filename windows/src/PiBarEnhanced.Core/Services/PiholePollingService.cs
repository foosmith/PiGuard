using PiBarEnhanced.Core.Abstractions;
using PiBarEnhanced.Core.Models;

namespace PiBarEnhanced.Core.Services;

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

        await _lifetimeCts.CancelAsync();

        try
        {
            await _backgroundTask.WaitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            _lifetimeCts.Dispose();
            _lifetimeCts = null;
            _backgroundTask = null;
        }
    }

    public async Task RefreshNowAsync(CancellationToken cancellationToken = default)
    {
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            var preferences = await _settingsStore.LoadAsync(cancellationToken);
            var overview = await PollNetworkAsync(preferences, cancellationToken);
            NetworkOverviewUpdated?.Invoke(this, overview);
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    public void Dispose()
    {
        _refreshGate.Dispose();
        _lifetimeCts?.Dispose();
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        var initialPreferences = await _settingsStore.LoadAsync(cancellationToken);
        NetworkOverviewUpdated?.Invoke(this, BuildInitialOverview(initialPreferences));
        await RefreshNowAsync(cancellationToken);

        while (!cancellationToken.IsCancellationRequested)
        {
            var preferences = await _settingsStore.LoadAsync(cancellationToken);
            var interval = TimeSpan.FromSeconds(Math.Max(1, preferences.PollingRateSeconds));

            try
            {
                await Task.Delay(interval, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            await RefreshNowAsync(cancellationToken);
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
            return connection.Version switch
            {
                ConnectionVersion.V6 => await new PiholeClientV6(connection, secret).FetchStatusAsync(cancellationToken),
                _ => await new PiholeClientV5(connection, secret).FetchStatusAsync(cancellationToken),
            };
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
