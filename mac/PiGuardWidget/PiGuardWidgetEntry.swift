//
//  PiGuardWidgetEntry.swift
//  PiGuardWidget

import WidgetKit
import Foundation

struct PiGuardWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil = main app hasn't run yet
    /// True when this entry should render the "App not running · cached" warning.
    /// Decided per-entry at timeline creation (WidgetKit archives each entry's view
    /// when the timeline is built, so staleness can't be computed at display time).
    var showsCachedWarning: Bool = false
}
