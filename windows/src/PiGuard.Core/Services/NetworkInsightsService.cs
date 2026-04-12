using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class NetworkInsightsService : INetworkInsightsService
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;

    public NetworkInsightsService(ISettingsStore settingsStore, ICredentialStore credentialStore)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
    }

    public async Task<IReadOnlyDictionary<string, IReadOnlyList<TopItem>>> FetchTopBlockedAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        var results = await Task.WhenAll(
            preferences.Connections.Select(connection => FetchTopItemsAsync(
                connection,
                static (clientV5, clientV6, token) => clientV5?.FetchTopBlockedAsync(token) ?? clientV6!.FetchTopBlockedAsync(token),
                cancellationToken)));

        return results
            .Where(result => result.Items is not null)
            .ToDictionary(result => result.Connection.Id, result => (IReadOnlyList<TopItem>)result.Items!, StringComparer.Ordinal);
    }

    public async Task<IReadOnlyDictionary<string, IReadOnlyList<TopItem>>> FetchTopClientsAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        var results = await Task.WhenAll(
            preferences.Connections.Select(connection => FetchTopItemsAsync(
                connection,
                static (clientV5, clientV6, token) => clientV5?.FetchTopClientsAsync(token) ?? clientV6!.FetchTopClientsAsync(token),
                cancellationToken)));

        return results
            .Where(result => result.Items is not null)
            .ToDictionary(result => result.Connection.Id, result => (IReadOnlyList<TopItem>)result.Items!, StringComparer.Ordinal);
    }

    public async Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogAsync(
        string? serverIdentifier = null,
        int limit = 100,
        CancellationToken cancellationToken = default)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        var connections = preferences.Connections
            .Where(connection => string.IsNullOrWhiteSpace(serverIdentifier) || string.Equals(connection.Id, serverIdentifier, StringComparison.Ordinal))
            .ToArray();

        var results = await Task.WhenAll(
            connections.Select(connection => FetchQueryLogForConnectionAsync(connection, limit, cancellationToken)));

        return results
            .SelectMany(entries => entries)
            .OrderByDescending(entry => entry.Timestamp)
            .ToArray();
    }

    public async Task<IReadOnlyList<DomainRuleResult>> ApplyDomainRuleAsync(
        string domain,
        DomainRuleAction action,
        CancellationToken cancellationToken = default)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        var targets = DetermineRuleTargets(preferences).ToArray();
        var results = await Task.WhenAll(targets.Select(target => ApplyDomainRuleToConnectionAsync(target, domain, action, cancellationToken)));
        return results.OrderBy(result => result.ServerDisplayName, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private async Task<TopItemFetchResult> FetchTopItemsAsync(
        ConnectionConfig connection,
        Func<IPiholeClientV5?, IPiholeClientV6?, CancellationToken, Task<IReadOnlyList<TopItem>>> fetcher,
        CancellationToken cancellationToken)
    {
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            return new TopItemFetchResult(connection, []);
        }

        try
        {
            var items = connection.Version == ConnectionVersion.V6
                ? await fetcher(null, new PiholeClientV6(connection, secret), cancellationToken)
                : await fetcher(new PiholeClientV5(connection, secret), null, cancellationToken);
            return new TopItemFetchResult(connection, items);
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return new TopItemFetchResult(connection, []);
        }
    }

    private async Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogForConnectionAsync(
        ConnectionConfig connection,
        int limit,
        CancellationToken cancellationToken)
    {
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            return [];
        }

        try
        {
            var displayName = BuildDisplayName(connection);
            return connection.Version == ConnectionVersion.V6
                ? await new PiholeClientV6(connection, secret).FetchQueryLogAsync(displayName, limit, cancellationToken)
                : await new PiholeClientV5(connection, secret).FetchQueryLogAsync(displayName, limit, cancellationToken);
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return [];
        }
    }

    private async Task<DomainRuleResult> ApplyDomainRuleToConnectionAsync(
        ConnectionConfig connection,
        string domain,
        DomainRuleAction action,
        CancellationToken cancellationToken)
    {
        var displayName = BuildDisplayName(connection);
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            return new DomainRuleResult(connection.Id, displayName, false, "No stored secret.");
        }

        try
        {
            if (connection.Version == ConnectionVersion.V6)
            {
                var client = new PiholeClientV6(connection, secret);
                if (action == DomainRuleAction.Allow)
                {
                    await client.AllowDomainAsync(domain, cancellationToken);
                }
                else
                {
                    await client.BlockDomainAsync(domain, cancellationToken);
                }
            }
            else
            {
                var client = new PiholeClientV5(connection, secret);
                if (action == DomainRuleAction.Allow)
                {
                    await client.AllowDomainAsync(domain, cancellationToken);
                }
                else
                {
                    await client.BlockDomainAsync(domain, cancellationToken);
                }
            }

            return new DomainRuleResult(connection.Id, displayName, true, $"{action} succeeded.");
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return new DomainRuleResult(connection.Id, displayName, false, exception.Message);
        }
    }

    private static IEnumerable<ConnectionConfig> DetermineRuleTargets(AppPreferences preferences)
    {
        var v6Connections = preferences.Connections
            .Where(connection => connection.Version == ConnectionVersion.V6)
            .ToArray();
        var v5Connections = preferences.Connections
            .Where(connection => connection.Version == ConnectionVersion.LegacyV5);

        if (v6Connections.Length >= 2 && preferences.Sync.Enabled)
        {
            var primary = v6Connections.FirstOrDefault(connection =>
                string.Equals(connection.Id, preferences.Sync.PrimaryConnectionId, StringComparison.Ordinal));

            if (primary is not null)
            {
                return [primary, .. v5Connections];
            }
        }

        return [.. v6Connections, .. v5Connections];
    }

    private static string BuildDisplayName(ConnectionConfig connection) => $"{connection.Hostname}:{connection.Port}";

    private sealed record TopItemFetchResult(ConnectionConfig Connection, IReadOnlyList<TopItem>? Items);
}
