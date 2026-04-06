using System.Text.Json;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class JsonSettingsStore : ISettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly string _settingsPath;

    public JsonSettingsStore(string settingsPath)
    {
        _settingsPath = settingsPath;
    }

    public async Task<AppPreferences> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_settingsPath))
        {
            return new AppPreferences();
        }

        await using var stream = File.OpenRead(_settingsPath);
        var preferences = await JsonSerializer.DeserializeAsync<AppPreferences>(stream, SerializerOptions, cancellationToken);
        return preferences ?? new AppPreferences();
    }

    public async Task SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default)
    {
        var directory = Path.GetDirectoryName(_settingsPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using var stream = File.Create(_settingsPath);
        await JsonSerializer.SerializeAsync(stream, preferences, SerializerOptions, cancellationToken);
    }
}
