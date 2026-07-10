//
//  main.swift
//  PiGuard
//
//  Entry point — enforces single instance before any XIB/UI loads.

import Cocoa

// MARK: - Shared paths

let _logsDir = FileManager.default
    .urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Logs/PiGuard")
let _pidURL   = _logsDir.appendingPathComponent("piguard.pid")
let _flagURL  = _logsDir.appendingPathComponent("open_query_log.flag")

// MARK: - Check for a running instance via POSIX kill(pid, 0)

func _runningPID(at url: URL) -> pid_t? {
    guard let data = try? Data(contentsOf: url),
          let str  = String(data: data, encoding: .utf8),
          let pid  = pid_t(str.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid != ProcessInfo.processInfo.processIdentifier
    else { return nil }
    let result = kill(pid, 0)
    if result == 0 { return pid }
    if errno == EPERM { return pid }
    return nil
}

if _runningPID(at: _pidURL) != nil {
    // DistributedNotificationCenter reaches the running instance via distnoted —
    // same proven channel used by PiGuardManager / PiGuardWidgetProvider.
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.foosmith.PiGuard.openQueryLog"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    // App Group flag file as fallback in case the running instance isn't
    // listening yet (e.g. it just started).
    let groupID = WidgetSnapshotStore.appGroupID
    if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
        let groupFlagURL = groupURL.appendingPathComponent("open_query_log.flag")
        try? "1".write(to: groupFlagURL, atomically: true, encoding: .utf8)
    }
    // Also write to own container as fallback.
    try? "1".write(to: _flagURL, atomically: true, encoding: .utf8)
    exit(0)
}

// First (and only) instance — write our PID.
try? FileManager.default.createDirectory(at: _logsDir, withIntermediateDirectories: true)
try? "\(ProcessInfo.processInfo.processIdentifier)"
    .write(to: _pidURL, atomically: true, encoding: .utf8)

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
