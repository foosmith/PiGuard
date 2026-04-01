using System.Net.Http.Json;
using System.Text.Json;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class PiholeClientV5 : IPiholeClientV5
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ConnectionConfig _connection;
    private readonly HttpClient _httpClient;
    private readonly string? _apiToken;

    public PiholeClientV5(ConnectionConfig connection, string? apiToken, HttpClient? httpClient = null)
    {
        _connection = connection;
        _apiToken = apiToken;
        _httpClient = httpClient ?? new HttpClient();
        _httpClient.Timeout = TimeSpan.FromSeconds(3);
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
        var argumentSuffix = argument is null ? string.Empty : $"={Uri.EscapeDataString(argument)}";
        builder.Query = $"{authPrefix}{action}{argumentSuffix}";
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
}
