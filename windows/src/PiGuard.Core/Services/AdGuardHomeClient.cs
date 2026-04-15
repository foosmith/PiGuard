using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Web;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class AdGuardHomeClient : IDnsFilterClient
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
    };
    private static readonly HttpClient SharedHttpClient = new() { Timeout = TimeSpan.FromSeconds(5) };

    private readonly ConnectionConfig _connection;
    private readonly HttpClient _httpClient;
    private readonly string? _password;

    public AdGuardHomeClient(ConnectionConfig connection, string? password, HttpClient? httpClient = null)
    {
        _connection = connection;
        _password = password;
        _httpClient = httpClient ?? SharedHttpClient;
    }

    public string ConnectionId => _connection.Id;

    public async Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default)
    {
        var statusTask = GetAsync<AghStatus>("/control/status", cancellationToken);
        var statsTask = GetAsync<AghStats>("/control/stats", cancellationToken);
        await Task.WhenAll(statusTask, statsTask);

        var status = await statusTask;
        var stats = await statsTask;
        var total = stats.NumDnsQueries;
        var blocked = stats.NumBlockedFiltering;
        var percentage = total == 0 ? 0.0 : (double)blocked / total * 100;

        return new PiholeStatusSnapshot(
            ConnectionId,
            BuildDisplayName(),
            Online: true,
            CanBeManaged: !_connection.PasswordProtected || !string.IsNullOrWhiteSpace(_password),
            Enabled: status.ProtectionEnabled,
            IsV6: false,
            TotalQueriesToday: total,
            AdsBlockedToday: blocked,
            AdsPercentageToday: percentage,
            DomainsBeingBlocked: 0);
    }

    public Task EnableAsync(CancellationToken cancellationToken = default) =>
        PostAsync("/control/protection", new { enabled = true }, cancellationToken);

    public Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default) =>
        PostAsync("/control/protection", new { enabled = false }, cancellationToken);

    public Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public async Task<IReadOnlyList<TopItem>> FetchTopBlockedAsync(CancellationToken cancellationToken = default)
    {
        using var document = await GetJsonDocumentAsync("/control/stats", cancellationToken);
        return ParseTopItems(document.RootElement, "top_blocked_domains");
    }

    public async Task<IReadOnlyList<TopItem>> FetchTopClientsAsync(CancellationToken cancellationToken = default)
    {
        using var document = await GetJsonDocumentAsync("/control/stats", cancellationToken);
        return ParseTopItems(document.RootElement, "top_clients");
    }

    public async Task<IReadOnlyList<QueryLogEntry>> FetchQueryLogAsync(
        string serverDisplayName,
        int limit = 100,
        CancellationToken cancellationToken = default)
    {
        var uri = BuildUri("/control/querylog",
            [new KeyValuePair<string, string?>("limit", limit.ToString())]);
        var request = CreateRequest(HttpMethod.Get, uri);
        using var response = await SendAsync(request, cancellationToken);
        using var document = await ParseJsonDocumentAsync(response, cancellationToken);

        var blockedReasons = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "FilteredBlocked", "FilteredBlockedService", "FilteredSafeBrowsing",
            "FilteredParental", "FilteredSafeSearch", "FilteredInvalid",
            "DomainFilter", "BlockedService",
        };

        var results = new List<QueryLogEntry>();
        if (document.RootElement.TryGetProperty("data", out var dataElement) &&
            dataElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in dataElement.EnumerateArray())
            {
                if (!TryGetString(item, "time", out var timeStr) ||
                    !TryGetString(item, "reason", out var reason))
                {
                    continue;
                }

                if (!item.TryGetProperty("question", out var question) ||
                    !TryGetString(question, "name", out var domain))
                {
                    continue;
                }

                if (!DateTimeOffset.TryParse(timeStr, out var timestamp))
                {
                    continue;
                }

                var client = GetNullableString(item, "client_name");
                if (string.IsNullOrWhiteSpace(client))
                {
                    client = GetNullableString(item, "client") ?? "unknown";
                }

                results.Add(new QueryLogEntry(
                    timestamp,
                    domain,
                    client,
                    blockedReasons.Contains(reason) ? QueryLogStatus.Blocked : QueryLogStatus.Allowed,
                    ConnectionId,
                    serverDisplayName));
            }
        }

        return results;
    }

    public Task AllowDomainAsync(string domain, CancellationToken cancellationToken = default) =>
        ModifyUserRulesAsync($"@@||{domain}^", cancellationToken);

    public Task BlockDomainAsync(string domain, CancellationToken cancellationToken = default) =>
        ModifyUserRulesAsync($"||{domain}^", cancellationToken);

    private async Task ModifyUserRulesAsync(string newRule, CancellationToken cancellationToken)
    {
        // AdGuard Home replaces the entire rule list — fetch current, append, post back.
        using var document = await GetJsonDocumentAsync("/control/filtering/status", cancellationToken);

        var existingRules = new List<string>();
        if (document.RootElement.TryGetProperty("user_rules", out var rulesElement) &&
            rulesElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var rule in rulesElement.EnumerateArray())
            {
                if (rule.ValueKind == JsonValueKind.String && rule.GetString() is { } r)
                {
                    existingRules.Add(r);
                }
            }
        }

        existingRules.Add(newRule);
        await PostAsync("/control/filtering/set_rules", new { rules = existingRules }, cancellationToken);
    }

    private async Task<T> GetAsync<T>(string path, CancellationToken cancellationToken)
    {
        var request = CreateRequest(HttpMethod.Get, BuildUri(path));
        using var response = await SendAsync(request, cancellationToken);
        try
        {
            var result = await response.Content.ReadFromJsonAsync<T>(SerializerOptions, cancellationToken);
            return result ?? throw new PiholeApiException("AdGuard Home returned an empty response body.");
        }
        catch (JsonException ex)
        {
            var content = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new PiholeApiException("Failed to decode AdGuard Home response.", (int)response.StatusCode, content, ex);
        }
    }

    private async Task<JsonDocument> GetJsonDocumentAsync(string path, CancellationToken cancellationToken)
    {
        var request = CreateRequest(HttpMethod.Get, BuildUri(path));
        using var response = await SendAsync(request, cancellationToken);
        return await ParseJsonDocumentAsync(response, cancellationToken);
    }

    private static async Task<JsonDocument> ParseJsonDocumentAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        try
        {
            return JsonDocument.Parse(content);
        }
        catch (JsonException ex)
        {
            throw new PiholeApiException("Failed to decode AdGuard Home JSON response.", (int)response.StatusCode, content, ex);
        }
    }

    private async Task PostAsync(string path, object body, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(body, SerializerOptions);
        var request = CreateRequest(HttpMethod.Post, BuildUri(path));
        var content = new ByteArrayContent(Encoding.UTF8.GetBytes(json));
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        request.Content = content;
        using var response = await SendAsync(request, cancellationToken);
        if (response.Content.Headers.ContentLength is > 0)
        {
            _ = await response.Content.ReadAsStringAsync(cancellationToken);
        }
    }

    private HttpRequestMessage CreateRequest(HttpMethod method, Uri uri)
    {
        var request = new HttpRequestMessage(method, uri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.ParseAdd("PiGuard.Windows/0.1");

        if (_connection.PasswordProtected && !string.IsNullOrWhiteSpace(_password))
        {
            var credentials = Convert.ToBase64String(
                Encoding.UTF8.GetBytes($"{_connection.Username}:{_password}"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);
        }

        return request;
    }

    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            var response = await _httpClient.SendAsync(request, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            return response;
        }
        catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new PiholeApiException("AdGuard Home request timed out.", innerException: ex);
        }
        catch (HttpRequestException ex)
        {
            throw new PiholeApiException("AdGuard Home request failed.", innerException: ex);
        }
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var message = response.StatusCode switch
        {
            System.Net.HttpStatusCode.Unauthorized => "AdGuard Home request was unauthorized.",
            System.Net.HttpStatusCode.Forbidden => "AdGuard Home request was forbidden.",
            _ => $"AdGuard Home request failed with status {(int)response.StatusCode}.",
        };

        throw new PiholeApiException(message, (int)response.StatusCode, content);
    }

    private Uri BuildUri(string path, IEnumerable<KeyValuePair<string, string?>>? queryParameters = null)
    {
        var scheme = _connection.UseSsl ? "https" : "http";
        var builder = new UriBuilder($"{scheme}://{_connection.Hostname}:{_connection.Port}{path}");
        if (queryParameters is not null)
        {
            var query = HttpUtility.ParseQueryString(string.Empty);
            foreach (var parameter in queryParameters)
            {
                query[parameter.Key] = parameter.Value;
            }

            builder.Query = query.ToString() ?? string.Empty;
        }

        return builder.Uri;
    }

    private string BuildDisplayName() => $"{_connection.Hostname}:{_connection.Port}";

    private static IReadOnlyList<TopItem> ParseTopItems(JsonElement root, string propertyName)
    {
        // AdGuard Home returns top items as an array of single-key objects: [{"domain.com": 5}, ...]
        if (!root.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        var results = new List<TopItem>();
        foreach (var item in property.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            foreach (var kv in item.EnumerateObject())
            {
                if (kv.Value.TryGetInt32(out var count))
                {
                    results.Add(new TopItem(kv.Name, count));
                }
            }
        }

        return results.OrderByDescending(i => i.Count).Take(10).ToArray();
    }

    private static bool TryGetString(JsonElement element, string propertyName, out string value)
    {
        if (element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String)
        {
            value = property.GetString() ?? string.Empty;
            return true;
        }

        value = string.Empty;
        return false;
    }

    private static string? GetNullableString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

    private sealed record AghStatus(
        bool ProtectionEnabled,
        bool Running,
        int DnsPort,
        int HttpPort);

    private sealed record AghStats(
        int NumDnsQueries,
        int NumBlockedFiltering,
        int NumReplacedSafebrowsing,
        int NumReplacedParental,
        int NumReplacedSafesearch);
}
