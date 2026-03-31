using PiBarEnhanced.Core.Models;

namespace PiBarEnhanced.Core.Services;

public sealed class SyncActivityFeed
{
    private readonly object _gate = new();
    private readonly List<SyncActivityEntry> _entries = [];

    public IReadOnlyList<SyncActivityEntry> Snapshot()
    {
        lock (_gate)
        {
            return _entries.ToArray();
        }
    }

    public void Append(string message)
    {
        lock (_gate)
        {
            _entries.Add(new SyncActivityEntry(DateTimeOffset.UtcNow, message));
        }
    }

    public void Clear()
    {
        lock (_gate)
        {
            _entries.Clear();
        }
    }
}
