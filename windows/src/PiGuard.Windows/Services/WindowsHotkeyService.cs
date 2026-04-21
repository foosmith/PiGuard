using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Interop;
using PiGuard.Core.Abstractions;

namespace PiGuard.Windows.Services;

/// <summary>
/// Registers a global hotkey (Ctrl+Alt+Shift+P) that calls a user-supplied action
/// when the hotkey is pressed. Uses the WPF ComponentDispatcher message pump so no
/// hidden window is required.
/// </summary>
public sealed class WindowsHotkeyService : IHotkeyService, IDisposable
{
    private const int  HotkeyId  = 0x4750;  // 'PG'
    private const uint ModAlt    = 0x0001;
    private const uint ModCtrl   = 0x0002;
    private const uint ModShift  = 0x0004;
    private const uint VkP       = 0x50;
    private const int  WmHotkey  = 0x0312;

    private readonly Func<Task> _onFired;
    private bool _registered;

    public WindowsHotkeyService(Func<Task> onFired)
    {
        _onFired = onFired;
    }

    /// <summary>
    /// Registers Ctrl+Alt+Shift+P. Idempotent — safe to call when already registered.
    /// </summary>
    public Task RegisterAsync(CancellationToken cancellationToken = default)
    {
        if (_registered)
        {
            return Task.CompletedTask;
        }

        if (RegisterHotKey(IntPtr.Zero, HotkeyId, ModCtrl | ModAlt | ModShift, VkP))
        {
            ComponentDispatcher.ThreadPreprocessMessage += HandleMessage;
            _registered = true;
        }

        return Task.CompletedTask;
    }

    /// <summary>
    /// Unregisters the hotkey. Idempotent — safe to call when not registered.
    /// </summary>
    public Task UnregisterAsync(CancellationToken cancellationToken = default)
    {
        if (!_registered)
        {
            return Task.CompletedTask;
        }

        UnregisterHotKey(IntPtr.Zero, HotkeyId);
        ComponentDispatcher.ThreadPreprocessMessage -= HandleMessage;
        _registered = false;
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        if (_registered)
        {
            UnregisterHotKey(IntPtr.Zero, HotkeyId);
            ComponentDispatcher.ThreadPreprocessMessage -= HandleMessage;
        }
    }

    private void HandleMessage(ref MSG msg, ref bool handled)
    {
        if (msg.message == WmHotkey && (int)msg.wParam == HotkeyId)
        {
            _ = _onFired();
            handled = true;
        }
    }

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
