using System.IO;
using System.Security.Cryptography;
using System.Text;
using PiGuard.Core.Abstractions;

namespace PiGuard.Windows.Services;

public sealed class WindowsCredentialStore : ICredentialStore
{
    private readonly string _credentialRoot;
    private readonly Dictionary<string, string?> _cache = new(StringComparer.Ordinal);

    public WindowsCredentialStore(string appDataRoot)
    {
        _credentialRoot = Path.Combine(appDataRoot, "credentials");
    }

    public async Task<string?> ReadSecretAsync(string accountKey, CancellationToken cancellationToken = default)
    {
        if (_cache.TryGetValue(accountKey, out var cached))
        {
            return cached;
        }

        var path = GetPath(accountKey);
        if (!File.Exists(path))
        {
            _cache[accountKey] = null;
            return null;
        }

        var protectedBytes = await File.ReadAllBytesAsync(path, cancellationToken);
        var bytes = ProtectedData.Unprotect(protectedBytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
        var value = Encoding.UTF8.GetString(bytes);
        _cache[accountKey] = value;
        return value;
    }

    public async Task WriteSecretAsync(string accountKey, string value, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_credentialRoot);
        var bytes = Encoding.UTF8.GetBytes(value);
        var protectedBytes = ProtectedData.Protect(bytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
        await File.WriteAllBytesAsync(GetPath(accountKey), protectedBytes, cancellationToken);
        _cache[accountKey] = value;
    }

    public Task DeleteSecretAsync(string accountKey, CancellationToken cancellationToken = default)
    {
        var path = GetPath(accountKey);
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        _cache.Remove(accountKey);
        return Task.CompletedTask;
    }

    private string GetPath(string accountKey) => Path.Combine(_credentialRoot, $"{Sanitize(accountKey)}.bin");

    private static string Sanitize(string key)
    {
        foreach (var invalid in Path.GetInvalidFileNameChars())
        {
            key = key.Replace(invalid, '_');
        }

        return key;
    }
}
