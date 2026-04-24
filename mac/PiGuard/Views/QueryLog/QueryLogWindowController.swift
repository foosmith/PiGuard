//
//  QueryLogWindowController.swift
//  PiGuard
//

import Cocoa

final class QueryLogWindowController: NSWindowController {
    convenience init(piholes: [String: Pihole]) {
        let viewController = QueryLogViewController(piholes: piholes)
        let window = NSWindow(contentViewController: viewController)
        window.title = "Query Log"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 800, height: 500))
        window.minSize = NSSize(width: 600, height: 300)
        // Force a layout pass at the correct content size before the window is shown.
        // Without this, NSWindow(contentViewController:) triggers an initial layout
        // at the window's default small size, which NSStackView uses to compress the
        // search field — and it never fully recovers when the window grows.
        window.contentView?.layoutSubtreeIfNeeded()
        window.center()
        self.init(window: window)
    }
}
