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
                static (client, token) => client.FetchTopBlockedAsync(token),
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
                static (client, token) => client.FetchTopClientsAsync(token),
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
        Func<IDnsFilterClient, CancellationToken, Task<IReadOnlyList<TopItem>>> fetcher,
        CancellationToken cancellationToken)
    {
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            return new TopItemFetchResult(connection, []);
        }

        try
        {
            var client = CreateClient(connection, secret);
            var items = await fetcher(client, cancellationToken);
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
            return await CreateClient(connection, secret).FetchQueryLogAsync(displayName, limit, cancellationToken);
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
            var client = CreateClient(connection, secret);
            if (action == DomainRuleAction.Allow)
            {
                await client.AllowDomainAsync(domain, cancellationToken);
            }
            else
            {
                await client.BlockDomainAsync(domain, cancellationToken);
            }

            return new DomainRuleResult(connection.Id, displayName, true, $"{action} succeeded.");
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return new DomainRuleResult(connection.Id, displayName, false, exception.Message);
        }
    }

    // AdGuard Home nodes are treated like V5 — they always receive rules directly.
    // When sync is on with a matched primary V6, only the primary V6 + V5 + AGH nodes receive rules
    // (not the secondary V6, because sync will propagate it). If primary is not matched, all nodes receive rules.
    private static IEnumerable<ConnectionConfig> DetermineRuleTargets(AppPreferences preferences)
    {
        var v6Connections = preferences.Connections
            .Where(connection => connection.Version == ConnectionVersion.V6)
            .ToArray();
        var nonV6Connections = preferences.Connections
            .Where(connection => connection.Version != ConnectionVersion.V6);

        if (v6Connections.Length >= 2 && preferences.Sync.Enabled)
        {
            var primary = v6Connections.FirstOrDefault(connection =>
                string.Equals(connection.Id, preferences.Sync.PrimaryConnectionId, StringComparison.Ordinal));

            if (primary is not null)
            {
                return [primary, .. nonV6Connections];
            }
        }

        return [.. v6Connections, .. nonV6Connections];
    }

    private static IDnsFilterClient CreateClient(ConnectionConfig connection, string? secret) =>
        connection.Version switch
        {
            ConnectionVersion.V6 => new PiholeClientV6(connection, secret),
            ConnectionVersion.AdGuardHome => new AdGuardHomeClient(connection, secret),
            _ => new PiholeClientV5(connection, secret),
        };

    private static string BuildDisplayName(ConnectionConfig connection) => $"{connection.Hostname}:{connection.Port}";

    private sealed record TopItemFetchResult(ConnectionConfig Connection, IReadOnlyList<TopItem>? Items);
}
