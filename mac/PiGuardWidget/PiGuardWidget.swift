//
//  PiGuardWidget.swift
//  PiGuardWidget

import WidgetKit
import SwiftUI
import AppIntents

struct PiGuardWidget: Widget {
    let kind: String = "PiGuardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PiGuardWidgetProvider()) { entry in
            Button(intent: OpenQueryLogIntent()) {
                PiGuardWidgetEntryView(entry: entry)
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .configurationDisplayName("PiGuard")
        .description("DNS blocking status and today's statistics.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
