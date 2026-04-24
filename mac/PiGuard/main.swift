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
let _traceURL = _logsDir.appendingPathComponent("main_trace.log")

// Append a line to the trace file so we can see exactly what the second
// instance does without needing startFileLogging().
func _trace(_ msg: String) {
    try? FileManager.default.createDirectory(at: _logsDir, withIntermediateDirectories: true)
    let line = "[\(Date())] PID=\(ProcessInfo.processInfo.processIdentifier) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: _traceURL.path) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: _traceURL)
    }
}

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

_trace("started — logsDir=\(_logsDir.path)")

if let runningPID = _runningPID(at: _pidURL) {
    _trace("found running instance PID=\(runningPID) — signalling via DistributedNotificationCenter and exiting")
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
    let groupID = "group.com.foosmith.PiGuard"
    if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
        let groupFlagURL = groupURL.appendingPathComponent("open_query_log.flag")
        try? "1".write(to: groupFlagURL, atomically: true, encoding: .utf8)
    }
    // Also write to own container as fallback.
    try? "1".write(to: _flagURL, atomically: true, encoding: .utf8)
    _trace("signal sent, flag written")
    exit(0)
} else {
    // Log why we didn't detect a running instance
    if let data = try? Data(contentsOf: _pidURL),
       let str = String(data: data, encoding: .utf8),
       let pid = pid_t(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
        let result = kill(pid, 0)
        _trace("PID file contained \(pid), kill(pid,0)=\(result) errno=\(errno) — treating as dead")
    } else {
        _trace("no valid PID file found — starting as first instance")
    }
}

// First (and only) instance — write our PID.
try? FileManager.default.createDirectory(at: _logsDir, withIntermediateDirectories: true)
try? "\(ProcessInfo.processInfo.processIdentifier)"
    .write(to: _pidURL, atomically: true, encoding: .utf8)
_trace("wrote PID file, calling NSApplicationMain")

NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
