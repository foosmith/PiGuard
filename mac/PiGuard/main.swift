//
//  main.swift
//  PiGuard
//
//  Entry point — enforces single instance before any XIB/UI loads.
//  Widget taps open a piguard:// URL which causes macOS to launch a second
//  copy; we detect and exit here, before NSApplicationMain creates the
//  status bar item or any other UI.

import Cocoa

let currentPID = ProcessInfo.processInfo.processIdentifier
let others = NSRunningApplication.runningApplications(
    withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
).filter { $0.processIdentifier != currentPID }

if !others.isEmpty {
    others.first?.activate(options: .activateIgnoringOtherApps)
    exit(0)
}

NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
