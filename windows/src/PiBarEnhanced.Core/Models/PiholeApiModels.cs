using System.Text.Json.Serialization;

namespace PiBarEnhanced.Core.Models;

public sealed class PiholeApiException : Exception
{
    public PiholeApiException(string message, int? statusCode = null, string? content = null, Exception? innerException = null)
        : base(message, innerException)
    {
        StatusCode = statusCode;
        Content = content;
    }

    public int? StatusCode { get; }

    public string? Content { get; }
}

public sealed record PiholeV6PasswordResponse(PiholeV6Session Session, double Took);

public sealed record PiholeV6Session(
    bool Valid,
    bool Totp,
    string? Sid,
    string? Csrf,
    int Validity,
    string? Message);

public sealed record PiholeV6Summary(
    PiholeV6Queries Queries,
    PiholeV6Clients Clients,
    PiholeV6Gravity Gravity,
    double Took);

public sealed record PiholeV6Queries(
    int Total,
    int Blocked,
    [property: JsonPropertyName("percent_blocked")] double PercentBlocked,
    [property: JsonPropertyName("unique_domains")] int UniqueDomains,
    int Forwarded,
    int Cached);

public sealed record PiholeV6Clients(int Active, int Total);

public sealed record PiholeV6Gravity(
    [property: JsonPropertyName("domains_being_blocked")] int DomainsBeingBlocked,
    [property: JsonPropertyName("last_update")] int LastUpdate);

public sealed record PiholeV6BlockingStatus(string Blocking, double? Timer, double Took);
