using PiGuard.Core.Models;

namespace PiGuard.Core.Services;

public sealed class SyncActivityFeed
{
    private const int MaxEntries = 200;

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
            if (_entries.Count > MaxEntries)
            {
                _entries.RemoveRange(0, _entries.Count - MaxEntries);
            }
        }
    }

    public void Load(IEnumerable<SyncActivityEntry> entries)
    {
        lock (_gate)
        {
            _entries.Clear();
            _entries.AddRange(entries.OrderBy(entry => entry.Timestamp));
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
