using System.IO;
using Microsoft.Win32;
using PiGuard.Core.Abstractions;

namespace PiGuard.Windows.Services;

public sealed class WindowsStartupService : IStartupService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly string _appName;
    private readonly string _executableName;

    public WindowsStartupService(string appName, string executableName)
    {
        _appName = appName;
        _executableName = executableName;
    }

    public Task<bool> IsEnabledAsync(CancellationToken cancellationToken = default)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return Task.FromResult(key?.GetValue(_appName) is string);
    }

    public Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (enabled)
        {
            var executablePath = Path.Combine(AppContext.BaseDirectory, _executableName);
            key?.SetValue(_appName, $"\"{executablePath}\"");
        }
        else
        {
            key?.DeleteValue(_appName, throwOnMissingValue: false);
        }

        return Task.CompletedTask;
    }
}
