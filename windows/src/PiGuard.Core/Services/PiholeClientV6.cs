using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class PiholeClientV6 : IPiholeClientV6
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ConnectionConfig _connection;
    private readonly HttpClient _httpClient;
    private readonly string? _appPassword;

    private string? _sessionId;
    private DateTimeOffset? _sessionExpiry;

    public PiholeClientV6(ConnectionConfig connection, string? appPassword, HttpClient? httpClient = null)
    {
        _connection = connection;
        _appPassword = appPassword;
        _httpClient = httpClient ?? new HttpClient();
        _httpClient.Timeout = TimeSpan.FromSeconds(5);
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

    private async Task<HttpRequestMessage> CreateRequestAsync(string path, HttpMethod method, CancellationToken cancellationToken, object? body = null)
    {
        var request = new HttpRequestMessage(method, BuildUri(path));
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

    private Uri BuildUri(string path)
    {
        var scheme = _connection.UseSsl ? "https" : "http";
        return new Uri($"{scheme}://{_connection.Hostname}:{_connection.Port}/api{path}");
    }

    private string BuildDisplayName() => $"{_connection.Hostname}:{_connection.Port}";
}
