using System.Text;
using System.Text.Json;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class SyncOrchestrationService : ISyncService, IDisposable
{
    private static readonly KeyValuePair<string, string?> AppSudoQuery = new("app_sudo", "true");
    private static readonly KeyValuePair<string, string?> BlockTypeQuery = new("type", "block");

    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IPollingService _pollingService;
    private readonly SyncActivityFeed _activityFeed = new();
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private readonly SemaphoreSlim _gravityGate = new(1, 1);

    private CancellationTokenSource? _lifetimeCts;
    private Task? _backgroundTask;
    private SyncStatusSnapshot _currentStatus = new(null, null, string.Empty, false, false, []);

    public SyncOrchestrationService(
        ISettingsStore settingsStore,
        ICredentialStore credentialStore,
        IPollingService pollingService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _pollingService = pollingService;
    }

    public event EventHandler<SyncStatusSnapshot>? SyncStatusChanged;

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_backgroundTask is not null)
        {
            return;
        }

        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        _activityFeed.Load(preferences.Sync.Activity);

        _currentStatus = new SyncStatusSnapshot(
            preferences.Sync.LastStatus,
            preferences.Sync.LastRunAt,
            preferences.Sync.LastSummary,
            IsSyncInProgress: false,
            IsGravityUpdateInProgress: false,
            _activityFeed.Snapshot());
        PublishStatus();

        _lifetimeCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _backgroundTask = RunScheduledSyncLoopAsync(_lifetimeCts.Token);
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (_lifetimeCts is null || _backgroundTask is null)
        {
            return;
        }

        var lifetimeCts = _lifetimeCts;
        await lifetimeCts.CancelAsync();

        try
        {
            await _backgroundTask.WaitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            lifetimeCts.Dispose();
            _lifetimeCts = null;
            _backgroundTask = null;
        }
    }

    public async Task TriggerSyncNowAsync(CancellationToken cancellationToken = default)
    {
        await _syncGate.WaitAsync(cancellationToken);
        try
        {
            SetStatus(isSyncInProgress: true);
            AppendActivity("Sync requested.");

            var preferences = await _settingsStore.LoadAsync(cancellationToken);
            var (status, message) = await RunSyncAsync(preferences, cancellationToken);
            await PersistSyncStatusAsync(preferences, status, message, cancellationToken);
        }
        finally
        {
            SetStatus(isSyncInProgress: false);
            _syncGate.Release();
        }
    }

    public async Task TriggerGravityUpdateAsync(CancellationToken cancellationToken = default)
    {
        await _gravityGate.WaitAsync(cancellationToken);
        try
        {
            SetStatus(isGravityUpdateInProgress: true);
            AppendActivity("Gravity update requested.");

            var preferences = await _settingsStore.LoadAsync(cancellationToken);
            var v6Connections = preferences.Connections.Where(connection => connection.Version == ConnectionVersion.V6).ToArray();
            if (v6Connections.Length == 0)
            {
                AppendActivity("Gravity update skipped because no Pi-hole v6 connections are configured.");
                return;
            }

            var tasks = v6Connections.Select(connection => TriggerGravityForConnectionAsync(connection, cancellationToken));
            var results = await Task.WhenAll(tasks);

            var triggered = results.Count(r => r == GravityResult.Triggered);
            var failed = results.Count(r => r == GravityResult.Failed);
            var skipped = results.Count(r => r == GravityResult.Skipped);

            AppendActivity($"Gravity update finished. Triggered={triggered}, Failed={failed}, Skipped={skipped}.");
            if (triggered > 0)
            {
                await _pollingService.RefreshNowAsync(cancellationToken);
            }
        }
        finally
        {
            SetStatus(isGravityUpdateInProgress: false);
            _gravityGate.Release();
        }
    }

    public void Dispose()
    {
        var lifetimeCts = Interlocked.Exchange(ref _lifetimeCts, null);
        lifetimeCts?.Cancel();
        lifetimeCts?.Dispose();
        _backgroundTask = null;
        _syncGate.Dispose();
        _gravityGate.Dispose();
    }

    private enum GravityResult { Triggered, Failed, Skipped }

    private async Task<GravityResult> TriggerGravityForConnectionAsync(ConnectionConfig connection, CancellationToken cancellationToken)
    {
        var displayName = BuildDisplayName(connection);
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            AppendActivity($"{displayName}: skipped because no app password is stored.");
            return GravityResult.Skipped;
        }

        try
        {
            await new PiholeClientV6(connection, secret).TriggerGravityUpdateAsync(cancellationToken);
            AppendActivity($"{displayName}: gravity update triggered.");
            return GravityResult.Triggered;
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            AppendActivity($"{displayName}: gravity update failed. {exception.Message}");
            return GravityResult.Failed;
        }
    }

    private async Task RunScheduledSyncLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            var preferences = await _settingsStore.LoadAsync(cancellationToken);
            if (!ShouldRunScheduledSync(preferences))
            {
                continue;
            }

            await TriggerSyncNowAsync(cancellationToken);
        }
    }

    private static bool ShouldRunScheduledSync(AppPreferences preferences)
    {
        if (!preferences.Sync.Enabled)
        {
            return false;
        }

        if (preferences.Sync.LastRunAt is null)
        {
            return true;
        }

        return DateTimeOffset.UtcNow >= preferences.Sync.LastRunAt.Value.AddMinutes(Math.Max(1, preferences.Sync.IntervalMinutes));
    }

    private async Task<(SyncRunStatus Status, string Message)> RunSyncAsync(
        AppPreferences preferences,
        CancellationToken cancellationToken)
    {
        if (!preferences.Sync.Enabled)
        {
            return (SyncRunStatus.Skipped, "Sync skipped because it is disabled.");
        }

        var primaryConnection = preferences.Connections.FirstOrDefault(connection => connection.Id == preferences.Sync.PrimaryConnectionId);
        var secondaryConnection = preferences.Connections.FirstOrDefault(connection => connection.Id == preferences.Sync.SecondaryConnectionId);
        if (primaryConnection is null || secondaryConnection is null)
        {
            return (SyncRunStatus.Failed, "Sync failed because the selected primary or secondary connection no longer exists.");
        }

        if (primaryConnection.Version != ConnectionVersion.V6 || secondaryConnection.Version != ConnectionVersion.V6)
        {
            return (SyncRunStatus.Failed, "Sync failed because both connections must be Pi-hole v6.");
        }

        if (string.Equals(primaryConnection.Id, secondaryConnection.Id, StringComparison.Ordinal))
        {
            return (SyncRunStatus.Failed, "Sync failed because primary and secondary cannot be the same connection.");
        }

        var primarySecret = await _credentialStore.ReadSecretAsync(primaryConnection.Id, cancellationToken);
        var secondarySecret = await _credentialStore.ReadSecretAsync(secondaryConnection.Id, cancellationToken);
        if (primaryConnection.PasswordProtected && string.IsNullOrWhiteSpace(primarySecret))
        {
            return (SyncRunStatus.Failed, $"Sync failed because {BuildDisplayName(primaryConnection)} is missing an app password.");
        }

        if (secondaryConnection.PasswordProtected && string.IsNullOrWhiteSpace(secondarySecret))
        {
            return (SyncRunStatus.Failed, $"Sync failed because {BuildDisplayName(secondaryConnection)} is missing an app password.");
        }

        var primary = new PiholeClientV6(primaryConnection, primarySecret);
        var secondary = new PiholeClientV6(secondaryConnection, secondarySecret);
        var isDryRun = preferences.Sync.DryRunEnabled;

        try
        {
            await Task.WhenAll(
                primary.FetchStatusAsync(cancellationToken),
                secondary.FetchStatusAsync(cancellationToken));

            var modeTag = isDryRun ? " [dry run]" : string.Empty;
            AppendActivity($"Sync{modeTag}: starting.");

            var (groupsSummary, primaryIdToName, secondaryNameToId) = await SyncGroupsAsync(
                primary,
                secondary,
                isDryRun,
                preferences.Sync.SkipGroups,
                cancellationToken);

            var adlistsSummary = "Adlists: skipped";
            if (!preferences.Sync.SkipAdlists)
            {
                if (preferences.Sync.WipeSecondaryBeforeSync && !isDryRun)
                {
                    await WipeSecondaryAdlistsAsync(secondary, cancellationToken);
                }

                adlistsSummary = await SyncAdlistsAsync(
                    primary,
                    secondary,
                    primaryIdToName,
                    secondaryNameToId,
                    isDryRun,
                    cancellationToken);
            }

            var domainsSummary = "Domains: skipped";
            if (!preferences.Sync.SkipDomains)
            {
                var bucketResults = new List<string>();
                foreach (var bucket in Enum.GetValues<DomainBucket>())
                {
                    var result = await SyncDomainBucketAsync(
                        bucket,
                        primary,
                        secondary,
                        primaryIdToName,
                        secondaryNameToId,
                        isDryRun,
                        cancellationToken);
                    bucketResults.Add($"{bucket.Label()}: +{result.Created} ~{result.Updated} -{result.Deleted}");
                }

                domainsSummary = $"Domains - {string.Join("; ", bucketResults)}";
            }

            return (
                isDryRun ? SyncRunStatus.DryRun : SyncRunStatus.Success,
                $"{groupsSummary} | {adlistsSummary} | {domainsSummary}");
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return (SyncRunStatus.Failed, BuildSyncFailureMessage(exception));
        }
    }

    private async Task<(string Summary, Dictionary<int, string> PrimaryIdToName, Dictionary<string, int> SecondaryNameToId)> SyncGroupsAsync(
        PiholeClientV6 primary,
        PiholeClientV6 secondary,
        bool dryRun,
        bool skip,
        CancellationToken cancellationToken)
    {
        var primaryGroups = await FetchGroupsAsync(primary, cancellationToken);
        var secondaryGroups = await FetchGroupsAsync(secondary, cancellationToken);
        var primaryByName = primaryGroups.ToDictionary(group => group.Name, StringComparer.Ordinal);
        var secondaryByName = secondaryGroups.ToDictionary(group => group.Name, StringComparer.Ordinal);

        var toCreate = new List<(string Name, SyncGroup Group)>();
        var toUpdate = new List<(string Name, SyncGroup Group)>();
        var toDisable = new List<string>();

        foreach (var (name, primaryGroup) in primaryByName)
        {
            if (secondaryByName.TryGetValue(name, out var secondaryGroup))
            {
                if (secondaryGroup.Enabled != primaryGroup.Enabled || secondaryGroup.Comment != primaryGroup.Comment)
                {
                    toUpdate.Add((name, primaryGroup));
                }
            }
            else
            {
                toCreate.Add((name, primaryGroup));
            }
        }

        foreach (var (name, secondaryGroup) in secondaryByName)
        {
            if (!primaryByName.ContainsKey(name) && secondaryGroup.Enabled)
            {
                toDisable.Add(name);
            }
        }

        if (!skip && !dryRun)
        {
            foreach (var (name, group) in toCreate)
            {
                await secondary.PostJsonAsync("/groups", new GroupCreateRequest(name, group.Enabled, group.Comment), [AppSudoQuery], cancellationToken);
            }

            foreach (var (name, group) in toUpdate)
            {
                await secondary.PutJsonAsync(
                    $"/groups/{PiholeClientV6.EncodePathComponent(name)}",
                    new GroupUpdateRequest(group.Enabled, group.Comment),
                    [AppSudoQuery],
                    cancellationToken);
            }

            foreach (var name in toDisable)
            {
                var secondaryGroup = secondaryByName[name];
                await secondary.PutJsonAsync(
                    $"/groups/{PiholeClientV6.EncodePathComponent(name)}",
                    new GroupUpdateRequest(false, secondaryGroup.Comment),
                    [AppSudoQuery],
                    cancellationToken);
            }
        }

        var primaryIdToName = primaryGroups.ToDictionary(group => group.Id, group => group.Name);
        var finalSecondaryGroups = !skip && !dryRun && toCreate.Count > 0
            ? await FetchGroupsAsync(secondary, cancellationToken)
            : secondaryGroups;
        var secondaryNameToId = finalSecondaryGroups.ToDictionary(group => group.Name, group => group.Id, StringComparer.Ordinal);

        var summary = skip
            ? "Groups: skipped (ID maps built)"
            : dryRun
                ? $"[Dry run] Groups: would +{toCreate.Count} ~{toUpdate.Count} ({toDisable.Count} extras would be disabled)"
                : $"Groups: +{toCreate.Count} ~{toUpdate.Count} ({toDisable.Count} extras disabled)";
        AppendActivity($"Sync: {summary}");
        return (summary, primaryIdToName, secondaryNameToId);
    }

    private async Task<string> SyncAdlistsAsync(
        PiholeClientV6 primary,
        PiholeClientV6 secondary,
        Dictionary<int, string> primaryIdToName,
        Dictionary<string, int> secondaryNameToId,
        bool dryRun,
        CancellationToken cancellationToken)
    {
        AppendActivity("Sync: fetching adlists.");
        var primaryLists = await FetchAdlistsAsync(primary, cancellationToken);
        var secondaryListsRaw = await FetchAdlistsAsync(secondary, cancellationToken);
        var secondaryLists = dryRun
            ? secondaryListsRaw
            : await SanitizeSecondaryPercentEncodedListsAsync(secondary, secondaryListsRaw, cancellationToken);

        var primaryByAddress = IndexAdlistsByNormalizedAddress(primaryLists);
        var secondaryByAddress = IndexAdlistsByNormalizedAddress(secondaryLists);
        var toDelete = secondaryByAddress.Keys.Except(primaryByAddress.Keys, StringComparer.Ordinal).OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var toUpsert = primaryByAddress.Keys.OrderBy(value => value, StringComparer.Ordinal).ToArray();

        AppendActivity($"Sync: {(dryRun ? "[dry run] " : string.Empty)}{toUpsert.Length} primary adlists; {toDelete.Length} secondary extras to remove.");
        var deleted = 0;
        var disabled = 0;
        foreach (var address in toDelete)
        {
            var list = secondaryByAddress[address];
            if (dryRun)
            {
                deleted++;
                continue;
            }

            if (list.Id is int id)
            {
                try
                {
                    await secondary.DeleteAsync($"/lists/{id}", [BlockTypeQuery, AppSudoQuery], cancellationToken);
                    deleted++;
                    continue;
                }
                catch (PiholeApiException exception) when (exception.StatusCode == 404)
                {
                }
            }

            await DisableAdlistAsync(secondary, list, cancellationToken);
            disabled++;
        }

        var created = 0;
        var updated = 0;
        foreach (var address in toUpsert)
        {
            var desired = primaryByAddress[address];
            secondaryByAddress.TryGetValue(address, out var existing);
            var translatedGroups = TranslateGroupIds(desired.Groups, primaryIdToName, secondaryNameToId);

            if (!dryRun)
            {
                var writeAddress = SyncAdlistSanitizeWriteAddress(desired.AddressNormalized);
                if (existing?.Id is int existingId)
                {
                    await secondary.PutJsonAsync(
                        $"/lists/{existingId}",
                        new AdlistUpdateRequest("block", writeAddress, desired.Enabled, desired.Comment, translatedGroups),
                        [BlockTypeQuery, AppSudoQuery],
                        cancellationToken);
                }
                else
                {
                    await secondary.PostJsonAsync(
                        "/lists",
                        new AdlistCreateRequest(writeAddress, "block", desired.Enabled, desired.Comment, translatedGroups),
                        [BlockTypeQuery, AppSudoQuery],
                        cancellationToken);
                }
            }

            if (existing is null)
            {
                created++;
            }
            else
            {
                updated++;
            }

            if ((created + updated) % 25 == 0)
            {
                AppendActivity($"Sync: adlists processed {created + updated}/{toUpsert.Length}.");
            }
        }

        var tag = dryRun ? "[Dry run] " : string.Empty;
        return disabled > 0
            ? $"{tag}Adlists: +{created} ~{updated} -{deleted} (disabled {disabled} extras)"
            : $"{tag}Adlists: +{created} ~{updated} -{deleted}";
    }

    private async Task<(int Created, int Updated, int Deleted)> SyncDomainBucketAsync(
        DomainBucket bucket,
        PiholeClientV6 primary,
        PiholeClientV6 secondary,
        Dictionary<int, string> primaryIdToName,
        Dictionary<string, int> secondaryNameToId,
        bool dryRun,
        CancellationToken cancellationToken)
    {
        AppendActivity($"Sync: {(dryRun ? "[dry run] " : string.Empty)}syncing {bucket.Label()}.");

        var primaryDomains = await FetchDomainsAsync(primary, bucket, cancellationToken);
        var secondaryDomains = await FetchDomainsAsync(secondary, bucket, cancellationToken);
        var primaryByDomain = primaryDomains.ToDictionary(domain => domain.DomainName, StringComparer.Ordinal);
        var secondaryByDomain = secondaryDomains.ToDictionary(domain => domain.DomainName, StringComparer.Ordinal);

        var deleted = 0;
        foreach (var domainName in secondaryByDomain.Keys.Except(primaryByDomain.Keys, StringComparer.Ordinal))
        {
            if (!dryRun)
            {
                await DeleteDomainAsync(secondary, secondaryByDomain[domainName], bucket, cancellationToken);
            }

            deleted++;
        }

        var created = 0;
        var updated = 0;
        foreach (var domainName in primaryByDomain.Keys)
        {
            var desired = primaryByDomain[domainName];
            secondaryByDomain.TryGetValue(domainName, out var existing);
            var translatedGroups = TranslateGroupIds(desired.Groups, primaryIdToName, secondaryNameToId);

            if (!dryRun)
            {
                if (existing is null)
                {
                    await secondary.PostJsonAsync(
                        bucket.Path(),
                        new DomainCreateRequest(domainName, desired.Enabled, desired.Comment, translatedGroups),
                        [AppSudoQuery],
                        cancellationToken);
                }
                else
                {
                    await secondary.PutJsonAsync(
                        $"{bucket.Path()}/{PiholeClientV6.EncodePathComponent(domainName)}",
                        new DomainUpdateRequest(desired.Enabled, desired.Comment, translatedGroups),
                        [AppSudoQuery],
                        cancellationToken);
                }
            }

            if (existing is null)
            {
                created++;
            }
            else
            {
                updated++;
            }
        }

        return (created, updated, deleted);
    }

    private async Task<List<SyncGroup>> FetchGroupsAsync(PiholeClientV6 client, CancellationToken cancellationToken)
    {
        using var document = await client.GetJsonDocumentAsync("/groups", cancellationToken: cancellationToken);
        var results = new List<SyncGroup>();
        foreach (var item in EnumerateRootArray(document.RootElement, "groups"))
        {
            if (!TryGetString(item, "name", out var name) || !TryGetInt(item, "id", out var id))
            {
                continue;
            }

            results.Add(new SyncGroup(id, name, GetBool(item, "enabled", true), GetNullableString(item, "comment")));
        }

        return results;
    }

    private async Task<List<SyncAdlist>> FetchAdlistsAsync(PiholeClientV6 client, CancellationToken cancellationToken)
    {
        using var document = await client.GetJsonDocumentAsync("/lists", [BlockTypeQuery], cancellationToken);
        var results = new List<SyncAdlist>();
        foreach (var item in EnumerateRootArray(document.RootElement, "lists"))
        {
            if (TryGetString(item, "type", out var type) && !string.Equals(type, "block", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!TryGetString(item, "address", out var addressStored))
            {
                continue;
            }

            results.Add(new SyncAdlist(
                GetNullableInt(item, "id"),
                addressStored,
                Uri.UnescapeDataString(addressStored),
                GetNullableBool(item, "enabled"),
                GetNullableString(item, "comment"),
                GetIntArray(item, "groups")));
        }

        return results;
    }

    private async Task<List<SyncDomainRule>> FetchDomainsAsync(PiholeClientV6 client, DomainBucket bucket, CancellationToken cancellationToken)
    {
        using var document = await client.GetJsonDocumentAsync(bucket.Path(), cancellationToken: cancellationToken);
        var results = new List<SyncDomainRule>();
        foreach (var item in EnumerateRootArray(document.RootElement, "domains"))
        {
            if (!TryGetString(item, "domain", out var domainName))
            {
                continue;
            }

            results.Add(new SyncDomainRule(
                GetNullableInt(item, "id"),
                domainName,
                GetNullableBool(item, "enabled"),
                GetNullableString(item, "comment"),
                GetIntArray(item, "groups")));
        }

        return results;
    }

    private async Task<List<SyncAdlist>> SanitizeSecondaryPercentEncodedListsAsync(
        PiholeClientV6 secondary,
        List<SyncAdlist> lists,
        CancellationToken cancellationToken)
    {
        var badLists = lists
            .Where(list => SyncAdlistLooksPercentEncoded(list.AddressStored) &&
                Uri.UnescapeDataString(list.AddressStored) != list.AddressStored)
            .ToArray();
        if (badLists.Length == 0)
        {
            return lists;
        }

        AppendActivity($"Sync: fixing {badLists.Length} percent-encoded adlist URLs on secondary.");
        var fixedAddressesById = new Dictionary<int, string>();

        foreach (var list in badLists)
        {
            if (list.Id is not int id)
            {
                continue;
            }

            var decoded = Uri.UnescapeDataString(list.AddressStored);
            var fixedAddress = SyncAdlistSanitizeWriteAddress(decoded);

            try
            {
                await secondary.PutJsonAsync(
                    $"/lists/{id}",
                    new AdlistUpdateRequest("block", fixedAddress, false, "Fixed by PiGuard sync (was percent-encoded)", null),
                    [BlockTypeQuery, AppSudoQuery],
                    cancellationToken);
                fixedAddressesById[id] = fixedAddress;
                continue;
            }
            catch
            {
            }

            try
            {
                await secondary.DeleteAsync($"/lists/{id}", [BlockTypeQuery, AppSudoQuery], cancellationToken);
            }
            catch (PiholeApiException exception) when (exception.StatusCode == 404)
            {
            }
            catch
            {
                try
                {
                    await secondary.PutJsonAsync(
                        $"/lists/{id}",
                        new AdlistUpdateRequest("block", null, false, "Disabled by PiGuard sync (invalid encoded URL)", null),
                        [BlockTypeQuery, AppSudoQuery],
                        cancellationToken);
                }
                catch
                {
                }
            }
        }

        return lists
            .Select(list =>
            {
                if (list.Id is int id && fixedAddressesById.TryGetValue(id, out var fixedAddress))
                {
                    return list with { AddressStored = fixedAddress, AddressNormalized = fixedAddress, Enabled = false };
                }

                var decoded = Uri.UnescapeDataString(list.AddressStored);
                return decoded != list.AddressStored && SyncAdlistLooksPercentEncoded(list.AddressStored) ? null : list;
            })
            .Where(list => list is not null)
            .Cast<SyncAdlist>()
            .ToList();
    }

    private async Task WipeSecondaryAdlistsAsync(PiholeClientV6 secondary, CancellationToken cancellationToken)
    {
        AppendActivity("Sync: wiping secondary adlists (pre-clean).");
        var lists = await FetchAdlistsAsync(secondary, cancellationToken);
        if (lists.Count == 0)
        {
            AppendActivity("Sync: no adlists to wipe.");
            return;
        }

        var wiped = 0;
        foreach (var list in lists)
        {
            if (list.Id is not int id)
            {
                continue;
            }

            try
            {
                await secondary.DeleteAsync($"/lists/{id}", [BlockTypeQuery, AppSudoQuery], cancellationToken);
                wiped++;
            }
            catch (PiholeApiException exception) when (exception.StatusCode == 404)
            {
            }
            catch
            {
                try
                {
                    await secondary.PutJsonAsync(
                        $"/lists/{id}",
                        new AdlistUpdateRequest("block", null, false, "Disabled by PiGuard pre-clean", null),
                        [BlockTypeQuery, AppSudoQuery],
                        cancellationToken);
                }
                catch
                {
                }
            }

            if (wiped > 0 && wiped % 50 == 0)
            {
                AppendActivity($"Sync: pre-clean wiped {wiped}/{lists.Count} adlists.");
            }
        }

        AppendActivity($"Sync: pre-clean complete ({wiped} adlists wiped).");
    }

    private async Task DisableAdlistAsync(PiholeClientV6 secondary, SyncAdlist list, CancellationToken cancellationToken)
    {
        if (list.Id is not int id)
        {
            return;
        }

        await secondary.PutJsonAsync(
            $"/lists/{id}",
            new AdlistUpdateRequest("block", null, false, "Disabled by PiGuard sync", null),
            [BlockTypeQuery, AppSudoQuery],
            cancellationToken);
    }

    private async Task DeleteDomainAsync(PiholeClientV6 client, SyncDomainRule domain, DomainBucket bucket, CancellationToken cancellationToken)
    {
        if (domain.Id is int id)
        {
            try
            {
                await client.DeleteAsync($"/domains/{id}", [AppSudoQuery], cancellationToken);
                return;
            }
            catch (PiholeApiException exception) when (exception.StatusCode == 404)
            {
                return;
            }
            catch (PiholeApiException)
            {
            }
        }

        await client.DeleteAsync($"{bucket.Path()}/{PiholeClientV6.EncodePathComponent(domain.DomainName)}", [AppSudoQuery], cancellationToken);
    }

    private async Task PersistSyncStatusAsync(
        AppPreferences preferences,
        SyncRunStatus status,
        string summary,
        CancellationToken cancellationToken)
    {
        AppendActivity(summary);

        var updatedSync = preferences.Sync with
        {
            LastStatus = status,
            LastRunAt = DateTimeOffset.UtcNow,
            LastSummary = summary,
            Activity = _activityFeed.Snapshot().TakeLast(100).ToList(),
        };

        await _settingsStore.SaveAsync(preferences with { Sync = updatedSync }, cancellationToken);

        _currentStatus = _currentStatus with
        {
            LastStatus = updatedSync.LastStatus,
            LastRunAt = updatedSync.LastRunAt,
            LastSummary = updatedSync.LastSummary,
            Activity = updatedSync.Activity,
        };
        PublishStatus();

        if (status != SyncRunStatus.Failed)
        {
            await _pollingService.RefreshNowAsync(cancellationToken);
        }
    }

    private void AppendActivity(string message)
    {
        _activityFeed.Append(message);
        _currentStatus = _currentStatus with { Activity = _activityFeed.Snapshot().TakeLast(100).ToArray() };
        PublishStatus();
    }

    private void SetStatus(bool? isSyncInProgress = null, bool? isGravityUpdateInProgress = null)
    {
        _currentStatus = _currentStatus with
        {
            IsSyncInProgress = isSyncInProgress ?? _currentStatus.IsSyncInProgress,
            IsGravityUpdateInProgress = isGravityUpdateInProgress ?? _currentStatus.IsGravityUpdateInProgress,
        };
        PublishStatus();
    }

    private void PublishStatus() => SyncStatusChanged?.Invoke(this, _currentStatus);

    private static string BuildDisplayName(ConnectionConfig connection) => $"{connection.Hostname}:{connection.Port}";

    private static string BuildSyncFailureMessage(Exception exception)
    {
        if (exception is PiholeApiException apiException)
        {
            return apiException.StatusCode switch
            {
                403 => "Sync failed because the secondary rejected writes (403). Enable Pi-hole v6 app_sudo.",
                401 => "Sync failed because a Pi-hole v6 request was unauthorized. Re-enter the app passwords in Preferences.",
                int statusCode => $"Sync failed ({statusCode}). {apiException.Content ?? apiException.Message}",
                _ => $"Sync failed. {apiException.Message}",
            };
        }

        return $"Sync failed: {exception.Message}";
    }

    private static int[] TranslateGroupIds(
        IReadOnlyList<int> primaryIds,
        IReadOnlyDictionary<int, string> primaryIdToName,
        IReadOnlyDictionary<string, int> secondaryNameToId) =>
        primaryIds
            .Where(primaryIdToName.ContainsKey)
            .Select(id => secondaryNameToId.TryGetValue(primaryIdToName[id], out var translated) ? translated : (int?)null)
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .ToArray();

    private static Dictionary<string, SyncAdlist> IndexAdlistsByNormalizedAddress(IEnumerable<SyncAdlist> lists)
    {
        var result = new Dictionary<string, SyncAdlist>(StringComparer.Ordinal);
        foreach (var list in lists)
        {
            if (result.TryGetValue(list.AddressNormalized, out var existing))
            {
                result[list.AddressNormalized] = PreferAdlist(existing, list);
            }
            else
            {
                result[list.AddressNormalized] = list;
            }
        }

        return result;
    }

    private static SyncAdlist PreferAdlist(SyncAdlist existing, SyncAdlist candidate)
    {
        var existingEncoded = SyncAdlistLooksPercentEncoded(existing.AddressStored);
        var candidateEncoded = SyncAdlistLooksPercentEncoded(candidate.AddressStored);
        if (existingEncoded != candidateEncoded)
        {
            return existingEncoded ? candidate : existing;
        }

        return (existing.Enabled ?? true) ? existing : candidate;
    }

    private static bool SyncAdlistLooksPercentEncoded(string address) =>
        address.Contains("%2F", StringComparison.OrdinalIgnoreCase) ||
        address.Contains("%3A", StringComparison.OrdinalIgnoreCase);

    private static string SyncAdlistSanitizeWriteAddress(string raw)
    {
        var trimmed = raw.Trim();
        if (trimmed.Length == 0)
        {
            return trimmed;
        }

        var builder = new StringBuilder(trimmed.Length);
        var lastWasWhitespace = false;
        foreach (var character in trimmed)
        {
            if (char.IsWhiteSpace(character))
            {
                if (!lastWasWhitespace)
                {
                    builder.Append("%20");
                    lastWasWhitespace = true;
                }

                continue;
            }

            lastWasWhitespace = false;
            builder.Append(character);
        }

        return builder.ToString();
    }

    private static IEnumerable<JsonElement> EnumerateRootArray(JsonElement root, string propertyName)
    {
        if (root.ValueKind == JsonValueKind.Object &&
            root.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.Array)
        {
            return property.EnumerateArray().ToArray();
        }

        return root.ValueKind == JsonValueKind.Array ? root.EnumerateArray().ToArray() : [];
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

    private static bool TryGetInt(JsonElement element, string propertyName, out int value)
    {
        if (element.TryGetProperty(propertyName, out var property) && property.TryGetInt32(out value))
        {
            return true;
        }

        value = 0;
        return false;
    }

    private static int? GetNullableInt(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.TryGetInt32(out var value)
            ? value
            : null;

    private static bool GetBool(JsonElement element, string propertyName, bool fallback) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? property.GetBoolean()
            : fallback;

    private static bool? GetNullableBool(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? property.GetBoolean()
            : null;

    private static int[] GetIntArray(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return property.EnumerateArray()
            .Where(item => item.TryGetInt32(out _))
            .Select(item => item.GetInt32())
            .ToArray();
    }

    internal enum DomainBucket
    {
        AllowExact,
        DenyExact,
        AllowRegex,
        DenyRegex,
    }

    private sealed record SyncGroup(int Id, string Name, bool Enabled, string? Comment);
    private sealed record SyncAdlist(int? Id, string AddressStored, string AddressNormalized, bool? Enabled, string? Comment, int[] Groups);
    private sealed record SyncDomainRule(int? Id, string DomainName, bool? Enabled, string? Comment, int[] Groups);
    private sealed record GroupCreateRequest(string Name, bool? Enabled, string? Comment);
    private sealed record GroupUpdateRequest(bool? Enabled, string? Comment);
    private sealed record AdlistCreateRequest(string Address, string Type, bool? Enabled, string? Comment, int[]? Groups);
    private sealed record AdlistUpdateRequest(string? Type, string? Address, bool? Enabled, string? Comment, int[]? Groups);
    private sealed record DomainCreateRequest(string Domain, bool? Enabled, string? Comment, int[]? Groups);
    private sealed record DomainUpdateRequest(bool? Enabled, string? Comment, int[]? Groups);
}

internal static class SyncDomainBucketExtensions
{
    public static string Path(this SyncOrchestrationService.DomainBucket bucket) => bucket switch
    {
        SyncOrchestrationService.DomainBucket.AllowExact => "/domains/allow/exact",
        SyncOrchestrationService.DomainBucket.DenyExact => "/domains/deny/exact",
        SyncOrchestrationService.DomainBucket.AllowRegex => "/domains/allow/regex",
        SyncOrchestrationService.DomainBucket.DenyRegex => "/domains/deny/regex",
        _ => throw new ArgumentOutOfRangeException(nameof(bucket), bucket, null),
    };

    public static string Label(this SyncOrchestrationService.DomainBucket bucket) => bucket switch
    {
        SyncOrchestrationService.DomainBucket.AllowExact => "allow/exact",
        SyncOrchestrationService.DomainBucket.DenyExact => "deny/exact",
        SyncOrchestrationService.DomainBucket.AllowRegex => "allow/regex",
        SyncOrchestrationService.DomainBucket.DenyRegex => "deny/regex",
        _ => throw new ArgumentOutOfRangeException(nameof(bucket), bucket, null),
    };
}
