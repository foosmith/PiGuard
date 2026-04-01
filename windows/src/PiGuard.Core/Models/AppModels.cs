namespace PiGuard.Core.Models;

public enum ConnectionVersion
{
    LegacyV5,
    V6,
}

public sealed record ConnectionConfig(
    string Id,
    string Hostname,
    int Port,
    bool UseSsl,
    ConnectionVersion Version,
    string AdminUrl,
    bool PasswordProtected);

public enum PiholeNetworkStatus
{
    Enabled,
    Disabled,
    PartiallyEnabled,
    Offline,
    PartiallyOffline,
    NoneSet,
    Initializing,
}

public sealed record PiholeStatusSnapshot(
    string ConnectionId,
    string DisplayName,
    bool Online,
    bool? CanBeManaged,
    bool? Enabled,
    bool IsV6,
    int TotalQueriesToday,
    int AdsBlockedToday,
    double AdsPercentageToday,
    int DomainsBeingBlocked);

public sealed record PiholeNetworkOverview(
    PiholeNetworkStatus Status,
    bool CanBeManaged,
    int TotalQueriesToday,
    int AdsBlockedToday,
    double AdsPercentageToday,
    int AverageBlocklist,
    IReadOnlyList<PiholeStatusSnapshot> Nodes);

public enum SyncRunStatus
{
    Success,
    Failed,
    DryRun,
    Skipped,
}

public sealed record SyncActivityEntry(DateTimeOffset Timestamp, string Message);

public sealed record SyncStatusSnapshot(
    SyncRunStatus? LastStatus,
    DateTimeOffset? LastRunAt,
    string LastSummary,
    bool IsSyncInProgress,
    bool IsGravityUpdateInProgress,
    IReadOnlyList<SyncActivityEntry> Activity);

public sealed record AppPreferences
{
    public List<ConnectionConfig> Connections { get; init; } = [];
    public bool ShowBlocked { get; init; } = true;
    public bool ShowQueries { get; init; } = true;
    public bool ShowPercentage { get; init; } = true;
    public bool ShowLabels { get; init; }
    public bool VerboseLabels { get; init; }
    public bool ShortcutEnabled { get; init; } = true;
    public bool LaunchAtStartup { get; init; }
    public int PollingRateSeconds { get; init; } = 3;
    public bool EnableLogging { get; init; }
    public SyncPreferences Sync { get; init; } = new();
}

public sealed record SyncPreferences
{
    public bool Enabled { get; init; }
    public string PrimaryConnectionId { get; init; } = string.Empty;
    public string SecondaryConnectionId { get; init; } = string.Empty;
    public int IntervalMinutes { get; init; } = 15;
    public bool SkipGroups { get; init; }
    public bool SkipAdlists { get; init; }
    public bool SkipDomains { get; init; }
    public bool DryRunEnabled { get; init; }
    public bool WipeSecondaryBeforeSync { get; init; }
    public SyncRunStatus? LastStatus { get; init; }
    public DateTimeOffset? LastRunAt { get; init; }
    public string LastSummary { get; init; } = string.Empty;
    public List<SyncActivityEntry> Activity { get; init; } = [];
}
