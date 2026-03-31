using System.Text.Json;
using PiBarEnhanced.Core.Abstractions;
using PiBarEnhanced.Core.Models;

namespace PiBarEnhanced.Core.Services;

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
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);

        await using var stream = File.Create(_settingsPath);
        await JsonSerializer.SerializeAsync(stream, preferences, SerializerOptions, cancellationToken);
    }
}
