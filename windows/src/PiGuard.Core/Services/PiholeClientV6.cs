using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Web;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class PiholeClientV6 : IPiholeClientV6
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };
    private static readonly HttpClient SharedHttpClient = new() { Timeout = TimeSpan.FromSeconds(5) };
    private static readonly Lock SessionCacheLock = new();
    private static readonly Dictionary<string, SessionCacheEntry> SessionCache = [];

    private readonly ConnectionConfig _connection;
    private readonly HttpClient _httpClient;
    private readonly string? _appPassword;

    private string? _sessionId;
    private DateTimeOffset? _sessionExpiry;

    public PiholeClientV6(ConnectionConfig connection, string? appPassword, HttpClient? httpClient = null)
    {
        _connection = connection;
        _appPassword = appPassword;
        _httpClient = httpClient ?? SharedHttpClient;
    }

    public string ConnectionId => _connection.Id;

    public async Task<PiholeStatusSnapshot> FetchStatusAsync(CancellationToken cancellationToken = default)
    {
        var summary = await GetAsync<PiholeV6Summary>("/stats/summary", cancellationToken);
        var blocking = await GetAsync<PiholeV6BlockingStatus>("/dns/blocking", cancellationToken);

        return new PiholeStatusSnapshot(
            ConnectionId,
            BuildDisplayName(),
            Online: true,
            CanBeManaged: !_connection.PasswordProtected || !string.IsNullOrWhiteSpace(_appPassword),
            Enabled: string.Equals(blocking.Blocking, "enabled", StringComparison.OrdinalIgnoreCase),
            IsV6: true,
            TotalQueriesToday: summary.Queries.Total,
            AdsBlockedToday: summary.Queries.Blocked,
            AdsPercentageToday: summary.Queries.PercentBlocked,
            DomainsBeingBlocked: summary.Gravity.DomainsBeingBlocked);
    }

    public Task EnableAsync(CancellationToken cancellationToken = default) =>
        PostAsync("/dns/blocking", new { blocking = true, timer = (int?)null }, cancellationToken);

    public Task DisableAsync(int? seconds = null, CancellationToken cancellationToken = default) =>
        PostAsync("/dns/blocking", new { blocking = false, timer = seconds }, cancellationToken);

    public Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default) =>
        PostAsync("/action/gravity", body: null, cancellationToken);

    public async Task<JsonDocument> GetJsonDocumentAsync(
        string path,
        IEnumerable<KeyValuePair<string, string?>>? queryParameters = null,
        CancellationToken cancellationToken = default)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Get, cancellationToken, queryParameters: queryParameters);
        using var response = await SendAsync(request, cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        try
        {
            return JsonDocument.Parse(content);
        }
        catch (JsonException exception)
        {
            throw new PiholeApiException("Failed to decode Pi-hole v6 JSON response.", (int)response.StatusCode, content, exception);
        }
    }

    public async Task PostJsonAsync<TBody>(
        string path,
        TBody body,
        IEnumerable<KeyValuePair<string, string?>>? queryParameters = null,
        CancellationToken cancellationToken = default)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Post, cancellationToken, body, queryParameters);
        using var response = await SendAsync(request, cancellationToken);
        if (response.Content.Headers.ContentLength is > 0)
        {
            _ = await response.Content.ReadAsStringAsync(cancellationToken);
        }
    }

    public async Task PutJsonAsync<TBody>(
        string path,
        TBody body,
        IEnumerable<KeyValuePair<string, string?>>? queryParameters = null,
        CancellationToken cancellationToken = default)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Put, cancellationToken, body, queryParameters);
        using var response = await SendAsync(request, cancellationToken);
        if (response.Content.Headers.ContentLength is > 0)
        {
            _ = await response.Content.ReadAsStringAsync(cancellationToken);
        }
    }

    public async Task DeleteAsync(
        string path,
        IEnumerable<KeyValuePair<string, string?>>? queryParameters = null,
        CancellationToken cancellationToken = default)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Delete, cancellationToken, queryParameters: queryParameters);
        using var response = await SendAsync(request, cancellationToken);
        if (response.Content.Headers.ContentLength is > 0)
        {
            _ = await response.Content.ReadAsStringAsync(cancellationToken);
        }
    }

    public static string EncodePathComponent(string value) => Uri.EscapeDataString(value);

    private async Task<T> GetAsync<T>(string path, CancellationToken cancellationToken)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Get, cancellationToken);
        using var response = await SendAsync(request, cancellationToken);
        return await ReadJsonAsync<T>(response, cancellationToken);
    }

    private async Task PostAsync(string path, object? body, CancellationToken cancellationToken)
    {
        var request = await CreateRequestAsync(path, HttpMethod.Post, cancellationToken, body);
        using var response = await SendAsync(request, cancellationToken);
        if (response.Content.Headers.ContentLength is > 0)
        {
            _ = await response.Content.ReadAsStringAsync(cancellationToken);
        }
    }

    private async Task<HttpRequestMessage> CreateRequestAsync(
        string path,
        HttpMethod method,
        CancellationToken cancellationToken,
        object? body = null,
        IEnumerable<KeyValuePair<string, string?>>? queryParameters = null)
    {
        var request = new HttpRequestMessage(method, BuildUri(path, queryParameters));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.ParseAdd("PiGuard.Windows/0.1");

        var sessionId = await GetSessionTokenAsync(cancellationToken);
        if (!string.IsNullOrWhiteSpace(sessionId))
        {
            request.Headers.Add("sid", sessionId);
        }

        if (body is not null)
        {
            var json = JsonSerializer.Serialize(body, SerializerOptions);
            request.Content = new StringContent(json, Encoding.UTF8, "application/json");
            request.Headers.ExpectContinue = false;
        }

        return request;
    }

    private async Task<string?> GetSessionTokenAsync(CancellationToken cancellationToken)
    {
        if (!_connection.PasswordProtected)
        {
            return null;
        }

        var sessionCacheKey = BuildSessionCacheKey();
        var cachedSession = GetCachedSession(sessionCacheKey);
        if (cachedSession is not null)
        {
            _sessionId = cachedSession.SessionId;
            _sessionExpiry = cachedSession.ExpiresAt;
            return _sessionId;
        }

        if (!string.IsNullOrWhiteSpace(_sessionId) && _sessionExpiry is not null && _sessionExpiry > DateTimeOffset.UtcNow)
        {
            return _sessionId;
        }

        if (string.IsNullOrWhiteSpace(_appPassword))
        {
            throw new PiholeApiException("Missing Pi-hole v6 app password.", 401);
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, BuildUri("/auth"))
        {
            Content = JsonContent.Create(new { password = _appPassword, totp = (int?)null }),
        };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.ParseAdd("PiGuard.Windows/0.1");

        using var response = await SendAsync(request, cancellationToken);
        var auth = await ReadJsonAsync<PiholeV6PasswordResponse>(response, cancellationToken);

        if (!auth.Session.Valid)
        {
            throw new PiholeApiException(auth.Session.Message ?? "Invalid Pi-hole v6 app password.", 401);
        }

        _sessionId = auth.Session.Sid;
        _sessionExpiry = auth.Session.Validity > 0
            ? DateTimeOffset.UtcNow.AddSeconds(Math.Max(auth.Session.Validity - 5, 0))
            : null;
        SetCachedSession(sessionCacheKey, _sessionId, _sessionExpiry);

        return _sessionId;
    }

    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            var response = await _httpClient.SendAsync(request, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            return response;
        }
        catch (TaskCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new PiholeApiException("Pi-hole v6 request timed out.", innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new PiholeApiException("Pi-hole v6 request failed.", innerException: exception);
        }
    }

    private static async Task<T> ReadJsonAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            var result = await response.Content.ReadFromJsonAsync<T>(SerializerOptions, cancellationToken);
            return result ?? throw new PiholeApiException("Pi-hole v6 returned an empty response body.");
        }
        catch (JsonException exception)
        {
            var content = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new PiholeApiException("Failed to decode Pi-hole v6 response.", (int)response.StatusCode, content, exception);
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
            System.Net.HttpStatusCode.Unauthorized => "Pi-hole v6 request was unauthorized.",
            System.Net.HttpStatusCode.Forbidden => "Pi-hole v6 request was forbidden.",
            _ => $"Pi-hole v6 request failed with status {(int)response.StatusCode}.",
        };

        throw new PiholeApiException(message, (int)response.StatusCode, content);
    }

    private Uri BuildUri(string path, IEnumerable<KeyValuePair<string, string?>>? queryParameters = null)
    {
        var scheme = _connection.UseSsl ? "https" : "http";
        var builder = new UriBuilder($"{scheme}://{_connection.Hostname}:{_connection.Port}/api{path}");
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

    private string BuildSessionCacheKey()
    {
        var scheme = _connection.UseSsl ? "https" : "http";
        return $"{scheme}://{_connection.Hostname}:{_connection.Port}|{_appPassword}";
    }

    private static SessionCacheEntry? GetCachedSession(string cacheKey)
    {
        lock (SessionCacheLock)
        {
            if (!SessionCache.TryGetValue(cacheKey, out var entry))
            {
                return null;
            }

            if (entry.ExpiresAt is not null && entry.ExpiresAt <= DateTimeOffset.UtcNow)
            {
                SessionCache.Remove(cacheKey);
                return null;
            }

            return entry;
        }
    }

    private static void SetCachedSession(string cacheKey, string? sessionId, DateTimeOffset? expiresAt)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            return;
        }

        lock (SessionCacheLock)
        {
            SessionCache[cacheKey] = new SessionCacheEntry(sessionId, expiresAt);
        }
    }

    private sealed record SessionCacheEntry(string SessionId, DateTimeOffset? ExpiresAt);
}
