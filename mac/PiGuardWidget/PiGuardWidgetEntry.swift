//
//  PiGuardWidgetEntry.swift
//  PiGuardWidget

import WidgetKit
import Foundation

struct PiGuardWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil = main app hasn't run yet
}
