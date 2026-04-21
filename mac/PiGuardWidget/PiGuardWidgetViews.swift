//
//  PiGuardWidgetViews.swift
//  PiGuardWidget

import SwiftUI
import WidgetKit

// MARK: - Entry View (dispatches to size-specific view)

struct PiGuardWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PiGuardWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: PiGuardWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor(for: snapshot.networkStatus))
                        .frame(width: 7, height: 7)
                    Text(snapshot.networkStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text(snapshot.adsBlockedToday.formatted())
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("blocked today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(blockRateString(snapshot.adsPercentageToday))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(relativeTime(snapshot.updatedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(12)
        } else {
            PlaceholderWidgetView()
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: PiGuardWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            HStack(alignment: .top, spacing: 14) {
                // Left: status
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: statusIconName(for: snapshot.networkStatus))
                        .font(.title2)
                        .foregroundStyle(statusColor(for: snapshot.networkStatus))
                    Text(snapshot.networkStatus)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor(for: snapshot.networkStatus))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(relativeTime(snapshot.updatedAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Right: 2×2 stats grid
                Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        StatCell(label: "Queries", value: snapshot.totalQueriesToday.formatted())
                        StatCell(label: "Blocked", value: snapshot.adsBlockedToday.formatted())
                    }
                    GridRow {
                        StatCell(label: "Block Rate", value: blockRateString(snapshot.adsPercentageToday))
                        StatCell(label: "Blocklist", value: abbreviatedCount(snapshot.averageBlocklist))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
        } else {
            PlaceholderWidgetView()
        }
    }
}

// MARK: - Stat Cell

struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Placeholder

struct PlaceholderWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open PiGuard\nto begin")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

// MARK: - Helpers

private func statusColor(for rawStatus: String) -> Color {
    switch rawStatus {
    case "Enabled":                       return .green
    case "Disabled":                      return .red
    case "Partially Enabled":             return .orange
    case "Offline", "Partially Offline":  return .gray
    default:                              return Color.secondary
    }
}

private func statusIconName(for rawStatus: String) -> String {
    switch rawStatus {
    case "Enabled":           return "shield.fill"
    case "Disabled":          return "shield.slash.fill"
    case "Partially Enabled": return "shield.lefthalf.filled"
    case "Offline", "Partially Offline": return "wifi.slash"
    default:                  return "shield"
    }
}

private func relativeTime(_ date: Date) -> String {
    let diff = Int(-date.timeIntervalSinceNow)
    if diff < 60   { return "Just now" }
    if diff < 3600 { return "\(diff / 60)m ago" }
    return "\(diff / 3600)h ago"
}

private func abbreviatedCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

private func blockRateString(_ pct: Double) -> String {
    String(format: "%.1f%%", pct)
}
