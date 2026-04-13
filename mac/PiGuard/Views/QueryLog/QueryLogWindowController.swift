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
        window.center()
        self.init(window: window)
    }
}
