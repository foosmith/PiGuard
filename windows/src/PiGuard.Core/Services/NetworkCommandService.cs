using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class NetworkCommandService : INetworkCommandService
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IPollingService _pollingService;

    public NetworkCommandService(
        ISettingsStore settingsStore,
        ICredentialStore credentialStore,
        IPollingService pollingService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _pollingService = pollingService;
    }

    public Task<OperationExecutionResult> EnableNetworkAsync(CancellationToken cancellationToken = default) =>
        ExecuteAsync(
            "enable blocking",
            (clientV5, clientV6, token) => clientV5?.EnableAsync(token) ?? clientV6!.EnableAsync(token),
            cancellationToken);

    public Task<OperationExecutionResult> DisableNetworkAsync(int? seconds = null, CancellationToken cancellationToken = default) =>
        ExecuteAsync(
            seconds is > 0 ? $"disable blocking for {seconds} seconds" : "disable blocking",
            (clientV5, clientV6, token) => clientV5?.DisableAsync(seconds, token) ?? clientV6!.DisableAsync(seconds, token),
            cancellationToken);

    private async Task<OperationExecutionResult> ExecuteAsync(
        string actionLabel,
        Func<IPiholeClientV5?, IPiholeClientV6?, CancellationToken, Task> executor,
        CancellationToken cancellationToken)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        if (preferences.Connections.Count == 0)
        {
            return new OperationExecutionResult(0, 0, 1, ["No Pi-hole connections are configured."]);
        }

        var messages = new List<string>();
        var succeeded = 0;
        var failed = 0;
        var skipped = 0;

        foreach (var connection in preferences.Connections)
        {
            var displayName = $"{connection.Hostname}:{connection.Port}";
            var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
            if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
            {
                skipped++;
                messages.Add($"{displayName}: skipped because no secret is stored.");
                continue;
            }

            try
            {
                if (connection.Version == ConnectionVersion.V6)
                {
                    var client = new PiholeClientV6(connection, secret);
                    await executor(null, client, cancellationToken);
                }
                else
                {
                    var client = new PiholeClientV5(connection, secret);
                    await executor(client, null, cancellationToken);
                }

                succeeded++;
                messages.Add($"{displayName}: {actionLabel} succeeded.");
            }
            catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
            {
                failed++;
                messages.Add($"{displayName}: {actionLabel} failed. {exception.Message}");
            }
        }

        if (succeeded > 0)
        {
            await _pollingService.RefreshNowAsync(cancellationToken);
        }

        return new OperationExecutionResult(succeeded, failed, skipped, messages);
    }
}
