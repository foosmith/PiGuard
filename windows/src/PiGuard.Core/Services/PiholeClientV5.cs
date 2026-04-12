using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class PiholeClientV5 : IPiholeClientV5
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly HttpClient SharedHttpClient = new() { Timeout = TimeSpan.FromSeconds(3) };

    private readonly ConnectionConfig _connection;
    private readonly HttpClient _httpClient;
    private readonly string? _apiToken;

    public PiholeClientV5(ConnectionConfig connection, string? apiToken, HttpClient? httpClient = null)
    {
        _connection = connection;
        _apiToken = apiToken;
        _httpClient = httpClient ?? SharedHttpClient;
    }

    public string ConnectionId => _connection.Id;

    public async Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("summaryRaw");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        var summary = await ReadJsonAsync<PiholeV5Summary>(response, cancellationToken);

        return new PiholeStatusSnapshot(
            ConnectionId,
            BuildDisplayName(),
            Online: true,
            CanBeManaged: !_connection.PasswordProtected || !string.IsNullOrWhiteSpace(_apiToken),
            Enabled: string.Equals(summary.Status, "enabled", StringComparison.OrdinalIgnoreCase),
            IsV6: false,
            TotalQueriesToday: summary.DnsQueriesToday,
            AdsBlockedToday: summary.AdsBlockedToday,
            AdsPercentageToday: summary.AdsPercentageToday,
            DomainsBeingBlocked: summary.DomainsBeingBlocked);
    }

    public async Task EnableAsync(CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("enable");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        _ = await ReadJsonAsync<PiholeV5StatusResponse>(response, cancellationToken);
    }

    public async Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("disable", seconds?.ToString());
        using var response = await SendGetAsync(requestUri, cancellationToken);
        _ = await ReadJsonAsync<PiholeV5StatusResponse>(response, cancellationToken);
    }

    public async Task<IReadOnlyList<TopItem>> FetchTopBlockedAsync(CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("topItems");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        var payload = await ReadJsonAsync<PiholeV5TopAdsResponse>(response, cancellationToken);
        return payload.TopAds
            .OrderByDescending(item => item.Value)
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .Take(10)
            .Select(item => new TopItem(item.Key, item.Value))
            .ToArray();
    }

    public async Task<IReadOnlyList<TopItem>> FetchTopClientsAsync(CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("topClients");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        var payload = await ReadJsonAsync<PiholeV5TopClientsResponse>(response, cancellationToken);
        return payload.TopSources
            .Select(item => new TopItem(item.Key.Split('|', 2)[0], item.Value))
            .OrderByDescending(item => item.Count)
            .ThenBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .Take(10)
            .ToArray();
    }

    public async Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogAsync(
        string serverDisplayName,
        int limit = 100,
        CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("getAllQueries", limit.ToString());
        using var response = await SendGetAsync(requestUri, cancellationToken);
        var payload = await ReadJsonAsync<PiholeV5QueryLogResponse>(response, cancellationToken);
        var blockedCodes = new HashSet<int> { 1, 4, 5, 6, 7, 8, 9, 10, 11 };

        return payload.Data
            .Select(row =>
            {
                if (row.Count < 5 ||
                    !long.TryParse(row[0].GetString(), out var timestampValue) ||
                    row[2].GetString() is not { } domain ||
                    row[3].GetString() is not { } client ||
                    !TryReadInt(row[4], out var statusCode))
                {
                    return null;
                }

                return new QueryLogEntry(
                    DateTimeOffset.FromUnixTimeSeconds(timestampValue),
                    domain,
                    client,
                    blockedCodes.Contains(statusCode) ? QueryLogStatus.Blocked : QueryLogStatus.Allowed,
                    ConnectionId,
                    serverDisplayName);
            })
            .Where(entry => entry is not null)
            .Cast<QueryLogEntry>()
            .ToArray();
    }

    public async Task AllowDomainAsync(string domain, CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("list", $"white&add={Uri.EscapeDataString(domain)}");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        _ = await response.Content.ReadAsStringAsync(cancellationToken);
    }

    public async Task BlockDomainAsync(string domain, CancellationToken cancellationToken = default)
    {
        var requestUri = BuildApiUri("list", $"black&add={Uri.EscapeDataString(domain)}");
        using var response = await SendGetAsync(requestUri, cancellationToken);
        _ = await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private Uri BuildApiUri(string action, string? argument = null)
    {
        if (_connection.PasswordProtected && string.IsNullOrWhiteSpace(_apiToken))
        {
            throw new PiholeApiException("Missing Pi-hole v5 API token.");
        }

        var builder = new UriBuilder(BuildBaseUri());
        var authPrefix = !_connection.PasswordProtected && string.IsNullOrWhiteSpace(_apiToken)
            ? string.Empty
            : $"auth={Uri.EscapeDataString(_apiToken ?? string.Empty)}&";
        builder.Query = argument is null
            ? $"{authPrefix}{action}"
            : $"{authPrefix}{action}={argument}";
        return builder.Uri;
    }

    private Uri BuildBaseUri()
    {
        var scheme = _connection.UseSsl ? "https" : "http";
        return new Uri($"{scheme}://{_connection.Hostname}:{_connection.Port}/admin/api.php");
    }

    private string BuildDisplayName() => $"{_connection.Hostname}:{_connection.Port}";

    private async Task<HttpResponseMessage> SendGetAsync(Uri uri, CancellationToken cancellationToken)
    {
        try
        {
            var response = await _httpClient.GetAsync(uri, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            return response;
        }
        catch (TaskCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new PiholeApiException("Pi-hole v5 request timed out.", innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new PiholeApiException("Pi-hole v5 request failed.", innerException: exception);
        }
    }

    private static async Task<T> ReadJsonAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            var result = await response.Content.ReadFromJsonAsync<T>(SerializerOptions, cancellationToken);
            return result ?? throw new PiholeApiException("Pi-hole v5 returned an empty response body.");
        }
        catch (JsonException exception)
        {
            var content = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new PiholeApiException("Failed to decode Pi-hole v5 response.", (int)response.StatusCode, content, exception);
        }
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        throw new PiholeApiException(
            $"Pi-hole v5 request failed with status {(int)response.StatusCode}.",
            (int)response.StatusCode,
            content);
    }

    private static bool TryReadInt(JsonElement element, out int value)
    {
        if (element.ValueKind == JsonValueKind.Number)
        {
            return element.TryGetInt32(out value);
        }

        if (element.ValueKind == JsonValueKind.String)
        {
            return int.TryParse(element.GetString(), out value);
        }

        value = 0;
        return false;
    }

    private sealed record PiholeV5Summary(
        int DomainsBeingBlocked,
        int DnsQueriesToday,
        int AdsBlockedToday,
        double AdsPercentageToday,
        int UniqueDomains,
        int QueriesForwarded,
        int QueriesCached,
        int UniqueClients,
        int DnsQueriesAllTypes,
        string Status);

    private sealed record PiholeV5StatusResponse(string Status);
    private sealed record PiholeV5TopAdsResponse([property: JsonPropertyName("top_ads")] Dictionary<string, int> TopAds);
    private sealed record PiholeV5TopClientsResponse([property: JsonPropertyName("top_sources")] Dictionary<string, int> TopSources);
    private sealed record PiholeV5QueryLogResponse(List<List<JsonElement>> Data);
}
