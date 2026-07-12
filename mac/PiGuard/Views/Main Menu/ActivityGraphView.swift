//
//  ActivityGraphView.swift
//  PiGuard
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Cocoa

/// 24-hour queries/blocked activity chart rendered inside a menu item.
/// Buckets are stacked bars: blocked (red) at the bottom, allowed above it.
final class ActivityGraphView: NSView {
    struct Bucket {
        let timestamp: Date
        let total: Int
        let blocked: Int
    }

    private var buckets: [Bucket] = []

    private let chartInsets = NSEdgeInsets(top: 24, left: 14, bottom: 16, right: 14)
    private let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private let labelFont = NSFont.systemFont(ofSize: 9)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(buckets: [Bucket]) {
        self.buckets = buckets.sorted { $0.timestamp < $1.timestamp }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let title = NSAttributedString(string: "Last 24 Hours", attributes: titleAttributes)
        title.draw(at: NSPoint(x: chartInsets.left, y: bounds.height - chartInsets.top + 6))

        let chartRect = NSRect(
            x: chartInsets.left,
            y: chartInsets.bottom,
            width: bounds.width - chartInsets.left - chartInsets.right,
            height: bounds.height - chartInsets.top - chartInsets.bottom
        )

        guard !buckets.isEmpty, let maxTotal = buckets.map(\.total).max(), maxTotal > 0 else {
            let empty = NSAttributedString(
                string: "No activity data",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
            let size = empty.size()
            empty.draw(at: NSPoint(
                x: chartRect.midX - size.width / 2,
                y: chartRect.midY - size.height / 2
            ))
            return
        }

        // Legend, right-aligned next to the title.
        drawLegend(attributes: labelAttributes)

        // Baseline.
        NSColor.quaternaryLabelColor.setFill()
        NSRect(x: chartRect.minX, y: chartRect.minY - 1, width: chartRect.width, height: 1).fill()

        let barWidth = chartRect.width / CGFloat(buckets.count)
        let allowedColor = NSColor.systemGreen.withAlphaComponent(0.65)
        let blockedColor = NSColor.systemRed

        for (index, bucket) in buckets.enumerated() {
            let x = chartRect.minX + CGFloat(index) * barWidth
            // Leave a hairline gap between bars when there is room for one.
            let width = max(barWidth - (barWidth > 2 ? 0.5 : 0), 0.5)

            let totalHeight = chartRect.height * CGFloat(bucket.total) / CGFloat(maxTotal)
            let blockedHeight = chartRect.height * CGFloat(bucket.blocked) / CGFloat(maxTotal)

            allowedColor.setFill()
            NSRect(x: x, y: chartRect.minY + blockedHeight, width: width, height: max(totalHeight - blockedHeight, 0)).fill()

            if blockedHeight > 0 {
                blockedColor.setFill()
                NSRect(x: x, y: chartRect.minY, width: width, height: blockedHeight).fill()
            }
        }

        // Time axis labels.
        if let first = buckets.first, let last = buckets.last {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            let startLabel = NSAttributedString(string: formatter.string(from: first.timestamp), attributes: labelAttributes)
            startLabel.draw(at: NSPoint(x: chartRect.minX, y: chartRect.minY - 13))

            let endLabel = NSAttributedString(string: formatter.string(from: last.timestamp), attributes: labelAttributes)
            endLabel.draw(at: NSPoint(x: chartRect.maxX - endLabel.size().width, y: chartRect.minY - 13))
        }
    }

    private func drawLegend(attributes: [NSAttributedString.Key: Any]) {
        let swatchSize: CGFloat = 6
        let y = bounds.height - chartInsets.top + 9
        var x = bounds.width - chartInsets.right

        let entries: [(String, NSColor)] = [
            ("Blocked", .systemRed),
            ("Allowed", NSColor.systemGreen.withAlphaComponent(0.65)),
        ]

        for (label, color) in entries {
            let text = NSAttributedString(string: label, attributes: attributes)
            let textSize = text.size()
            x -= textSize.width
            text.draw(at: NSPoint(x: x, y: y - textSize.height / 2 + swatchSize / 2 - 1))
            x -= swatchSize + 3
            color.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: swatchSize, height: swatchSize),
                xRadius: 1.5, yRadius: 1.5
            ).fill()
            x -= 10
        }
    }
}
