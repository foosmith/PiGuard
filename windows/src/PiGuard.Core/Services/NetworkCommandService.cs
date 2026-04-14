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
            static (client, token) => client.EnableAsync(token),
            cancellationToken);

    public Task<OperationExecutionResult> DisableNetworkAsync(int? seconds = null, CancellationToken cancellationToken = default) =>
        ExecuteAsync(
            seconds is > 0 ? $"disable blocking for {seconds} seconds" : "disable blocking",
            (client, token) => client.DisableAsync(seconds, token),
            cancellationToken);

    private async Task<OperationExecutionResult> ExecuteAsync(
        string actionLabel,
        Func<IDnsFilterClient, CancellationToken, Task> executor,
        CancellationToken cancellationToken)
    {
        var preferences = await _settingsStore.LoadAsync(cancellationToken);
        if (preferences.Connections.Count == 0)
        {
            return new OperationExecutionResult(0, 0, 1, ["No Pi-hole connections are configured."]);
        }

        var results = await Task.WhenAll(
            preferences.Connections.Select((connection, index) =>
                ExecuteForConnectionAsync(connection, index, actionLabel, executor, cancellationToken)));

        var orderedResults = results.OrderBy(result => result.Index).ToArray();
        var messages = orderedResults.Select(result => result.Message).ToArray();
        var succeeded = orderedResults.Count(result => result.Status == ExecutionStatus.Succeeded);
        var failed = orderedResults.Count(result => result.Status == ExecutionStatus.Failed);
        var skipped = orderedResults.Count(result => result.Status == ExecutionStatus.Skipped);

        if (succeeded > 0)
        {
            await _pollingService.RefreshNowAsync(cancellationToken);
        }

        return new OperationExecutionResult(succeeded, failed, skipped, messages);
    }

    private async Task<ConnectionExecutionResult> ExecuteForConnectionAsync(
        ConnectionConfig connection,
        int index,
        string actionLabel,
        Func<IDnsFilterClient, CancellationToken, Task> executor,
        CancellationToken cancellationToken)
    {
        var displayName = $"{connection.Hostname}:{connection.Port}";
        var secret = await _credentialStore.ReadSecretAsync(connection.Id, cancellationToken);
        if (connection.PasswordProtected && string.IsNullOrWhiteSpace(secret))
        {
            return new ConnectionExecutionResult(index, ExecutionStatus.Skipped, $"{displayName}: skipped because no secret is stored.");
        }

        try
        {
            var client = CreateClient(connection, secret);
            await executor(client, cancellationToken);
            return new ConnectionExecutionResult(index, ExecutionStatus.Succeeded, $"{displayName}: {actionLabel} succeeded.");
        }
        catch (Exception exception) when (exception is PiholeApiException or HttpRequestException)
        {
            return new ConnectionExecutionResult(index, ExecutionStatus.Failed, $"{displayName}: {actionLabel} failed. {exception.Message}");
        }
    }

    private static IDnsFilterClient CreateClient(ConnectionConfig connection, string? secret) =>
        connection.Version switch
        {
            ConnectionVersion.V6 => new PiholeClientV6(connection, secret),
            ConnectionVersion.AdGuardHome => new AdGuardHomeClient(connection, secret),
            _ => new PiholeClientV5(connection, secret),
        };

    private enum ExecutionStatus { Succeeded, Failed, Skipped }

    private sealed record ConnectionExecutionResult(int Index, ExecutionStatus Status, string Message);
}
