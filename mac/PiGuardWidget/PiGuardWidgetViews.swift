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

                WidgetFooterView(snapshot: snapshot, showTimestamp: true)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: statusIconName(for: snapshot.networkStatus))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(statusColor(for: snapshot.networkStatus))
                            Text(snapshot.networkStatus)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(statusColor(for: snapshot.networkStatus))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(relativeTime(snapshot.updatedAt))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(width: 72, alignment: .leading)

                    HStack(alignment: .top, spacing: 10) {
                        CompactStatCell(label: "Queries", value: snapshot.totalQueriesToday.formatted())
                        CompactStatCell(label: "Blocked", value: snapshot.adsBlockedToday.formatted())
                        CompactStatCell(label: "Rate", value: blockRateString(snapshot.adsPercentageToday))
                        CompactStatCell(label: "List", value: abbreviatedCount(snapshot.averageBlocklist))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 14) {
                    RankedListColumn(
                        title: "Top blocked",
                        items: Array(snapshot.topBlocked.prefix(3)),
                        emptyLabel: "No blocked domains"
                    )

                    RankedListColumn(
                        title: "Top queries",
                        items: Array(snapshot.topQueries.prefix(3)),
                        emptyLabel: "No query domains"
                    )
                }

                WidgetFooterView(snapshot: snapshot, showTimestamp: false)
            }
            .padding(14)
        } else {
            PlaceholderWidgetView()
        }
    }
}

// MARK: - Widget Footer

/// Shows "Query Log →" when the app is running, or a "not running / cached" warning when stale.
struct WidgetFooterView: View {
    let snapshot: WidgetSnapshot
    /// Small widget: show the timestamp on the left. Medium: timestamp is already in the header.
    let showTimestamp: Bool

    var body: some View {
        HStack(spacing: 3) {
            if showTimestamp {
                Text(relativeTime(snapshot.updatedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isStale(snapshot.updatedAt) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.7))
                Text("App not running · cached")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange.opacity(0.7))
            } else {
                Image(systemName: "list.bullet")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("Query Log")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
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
                .font(.system(.title3, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactStatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RankedListColumn: View {
    let title: String
    let items: [String]
    let emptyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(emptyLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: 10, alignment: .leading)
                            Text(item)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
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

/// PiGuard polls every 10 s. If the snapshot is older than 2 minutes, the app isn't running.
private func isStale(_ date: Date) -> Bool {
    -date.timeIntervalSinceNow > 120
}
