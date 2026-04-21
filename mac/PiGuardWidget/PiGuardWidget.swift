//
//  PiGuardWidget.swift
//  PiGuardWidget

import WidgetKit
import SwiftUI

struct PiGuardWidget: Widget {
    let kind: String = "PiGuardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PiGuardWidgetProvider()) { entry in
            PiGuardWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "piguard://open"))
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("PiGuard")
        .description("DNS blocking status and today's statistics.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
