# Query Log Search & Sort Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live search field and clickable column-header sorting (Domain, Client, Status) to the Query Log window.

**Architecture:** All changes are in a single file — `QueryLogViewController.swift`. A stored `NSSearchField` is added to the toolbar. Three columns get `sortDescriptorPrototype` set (selector `nil` to avoid KVC on a Swift struct). `applyFilter()` is extended to run search filtering and a switch-on-key sort, and owns the status label update. A new delegate method wires sort-descriptor changes back to `applyFilter()`.

**Tech Stack:** Swift, AppKit (NSTableView, NSSortDescriptor, NSSearchField)

---

## Files

- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift`

No new files.

---

## Task 1: Add stored properties

**Files:**
- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift` — after `private var filteredEntries`

Add three new stored properties immediately after the existing `private var filteredEntries` line.

- [ ] **Step 1: Add the three properties**

In `QueryLogViewController`, after line 11 (`private var filteredEntries: [QueryLogEntry] = []`), add:

```swift
private let searchField = NSSearchField()
private var searchText: String = ""
private var currentSortDescriptors: [NSSortDescriptor] = []
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
cd /Users/smithm/Library/CloudStorage/OneDrive-Personal/Documents/pibar-enhanced
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PiGuard/Views/QueryLog/QueryLogViewController.swift
git commit -m "feat(query-log): add searchField, searchText, and currentSortDescriptors properties"
```

---

## Task 2: Add search field to toolbar

**Files:**
- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift` — `loadView()`, toolbar section

Wire `searchField` target/action and insert it as the first item in the toolbar stack.

- [ ] **Step 1: Wire searchField and update toolbar array**

In `loadView()`, after `refreshButton.bezelStyle = .rounded` (around line 54), add:

```swift
searchField.target = self
searchField.action = #selector(searchChanged(_:))
searchField.placeholderString = "Search"
```

Then update the `NSStackView` initializer for `toolbar`. The existing line reads:

```swift
let toolbar = NSStackView(views: [serverFilterPopup, NSView(), statusLabel, refreshButton])
```

Change it to:

```swift
let toolbar = NSStackView(views: [searchField, serverFilterPopup, NSView(), statusLabel, refreshButton])
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

Note: The build will emit an "undeclared selector" warning for `searchChanged(_:)` — that's expected; the method is added in Task 5 Step 1.

- [ ] **Step 3: Commit**

```bash
git add PiGuard/Views/QueryLog/QueryLogViewController.swift
git commit -m "feat(query-log): add search field to toolbar"
```

---

## Task 3: Set sortDescriptorPrototype on sortable columns

**Files:**
- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift` — `loadView()`, column setup section

- [ ] **Step 1: Add sortDescriptorPrototype to domain, client, status columns**

In `loadView()`, after the five `NSTableColumn` declarations and before `tableView.addTableColumn(timeCol)`, add:

```swift
domainCol.sortDescriptorPrototype = NSSortDescriptor(key: "domain", ascending: true, selector: nil)
clientCol.sortDescriptorPrototype = NSSortDescriptor(key: "client", ascending: true, selector: nil)
statusCol.sortDescriptorPrototype = NSSortDescriptor(key: "status", ascending: true, selector: nil)
```

Time and Server columns intentionally get no prototype.

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PiGuard/Views/QueryLog/QueryLogViewController.swift
git commit -m "feat(query-log): set sortDescriptorPrototype on domain, client, status columns"
```

---

## Task 4: Update applyFilter() with search and sort

**Files:**
- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift` — `applyFilter()`

Replace the existing `applyFilter()` body entirely. The current implementation only filters by server and reloads the table. The new version adds search, sort, and owns the status label update.

- [ ] **Step 1: Replace applyFilter() body**

The existing `applyFilter()` method (lines 159–173) reads:

```swift
private func applyFilter() {
    let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

    if let selectedIdentifier {
        filteredEntries = entries.filter { $0.serverIdentifier == selectedIdentifier }
    } else {
        filteredEntries = entries
    }

    // Show/hide server column
    let serverCol = tableView.tableColumns.first { $0.identifier.rawValue == "server" }
    serverCol?.isHidden = selectedIdentifier != nil

    tableView.reloadData()
}
```

Replace it with:

```swift
private func applyFilter() {
    let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

    // Step 1: filter by server
    var result: [QueryLogEntry]
    if let selectedIdentifier {
        result = entries.filter { $0.serverIdentifier == selectedIdentifier }
    } else {
        result = entries
    }

    // Step 2: filter by search text
    if !searchText.isEmpty {
        result = result.filter { entry in
            entry.domain.localizedCaseInsensitiveContains(searchText) ||
            entry.client.localizedCaseInsensitiveContains(searchText) ||
            entry.status.rawValue.localizedCaseInsensitiveContains(searchText) ||
            entry.serverDisplayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Step 3: sort (first descriptor only; switch on key to avoid KVC on Swift struct)
    if let descriptor = currentSortDescriptors.first {
        result.sort { a, b in
            let ascending: Bool
            switch descriptor.key {
            case "domain":
                ascending = a.domain.localizedCaseInsensitiveCompare(b.domain) == .orderedAscending
            case "client":
                ascending = a.client.localizedCaseInsensitiveCompare(b.client) == .orderedAscending
            case "status":
                ascending = a.status.rawValue < b.status.rawValue
            default:
                ascending = false
            }
            return descriptor.ascending ? ascending : !ascending
        }
    }

    filteredEntries = result

    // Show/hide server column
    let serverCol = tableView.tableColumns.first { $0.identifier.rawValue == "server" }
    serverCol?.isHidden = selectedIdentifier != nil

    tableView.reloadData()
    statusLabel.stringValue = "\(filteredEntries.count) queries"
}
```

- [ ] **Step 2: Remove the status label update from fetchQueryLog()**

In `fetchQueryLog()`, inside `MainActor.run`, the line:

```swift
self.statusLabel.stringValue = "\(self.filteredEntries.count) queries"
```

is now handled by `applyFilter()`. Remove it so it isn't duplicated.

- [ ] **Step 3: Build to confirm it compiles**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PiGuard/Views/QueryLog/QueryLogViewController.swift
git commit -m "feat(query-log): update applyFilter with search, sort, and status label"
```

---

## Task 5: Add searchChanged action, sortDescriptorsDidChange delegate, and refresh reset

**Files:**
- Modify: `PiGuard/Views/QueryLog/QueryLogViewController.swift`

Three additions: the search action method, the sort descriptor delegate method, and reset logic in `fetchQueryLog()`.

- [ ] **Step 1: Add searchChanged(_:) action**

In the `// MARK: - Fetching` section, after `refreshAction()`, add:

```swift
@objc private func searchChanged(_ sender: NSSearchField) {
    searchText = sender.stringValue
    applyFilter()
}
```

- [ ] **Step 2: Add sortDescriptorsDidChange to the NSTableViewDelegate extension**

In the `NSTableViewDelegate` extension (after the `tableView(_:viewFor:row:)` method), add:

```swift
func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
    currentSortDescriptors = tableView.sortDescriptors
    applyFilter()
}
```

- [ ] **Step 3: Reset search and sort state on refresh**

In `fetchQueryLog()`, inside the `await MainActor.run { }` block, add these lines **before** the call to `self.applyFilter()`:

```swift
self.searchText = ""
self.searchField.stringValue = ""
self.currentSortDescriptors = []
self.tableView.sortDescriptors = []
```

The full `MainActor.run` block should now read:

```swift
await MainActor.run {
    self.entries = allEntries
    self.searchText = ""
    self.searchField.stringValue = ""
    self.currentSortDescriptors = []
    self.tableView.sortDescriptors = []
    self.applyFilter()
    self.refreshButton.isEnabled = true
    self.isLoading = false
}
```

Note: setting `tableView.sortDescriptors = []` fires `sortDescriptorsDidChange`, which calls `applyFilter()` again — but since `currentSortDescriptors` is already `[]` at that point, the second call produces identical output. This is harmless.

- [ ] **Step 4: Build to confirm it compiles cleanly**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` with no warnings about undeclared selectors.

- [ ] **Step 5: Commit**

```bash
git add PiGuard/Views/QueryLog/QueryLogViewController.swift
git commit -m "feat(query-log): add search action, sort delegate, and reset on refresh"
```

---

## Task 6: Manual verification

Run the app and verify each item from the spec's testing checklist.

- [ ] **Build and run**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard -configuration Debug build 2>&1 | tail -5
```

Open the `.app` from the build output, or run from Xcode.

- [ ] **Verify search**
  - Type a domain fragment — matching rows appear, others hide
  - Type a client IP — matching rows appear
  - Type "blocked" — only blocked rows appear (case-insensitive)
  - Type a server name — matching rows appear
  - Clear the field — all rows return
  - Status label count updates with each keystroke

- [ ] **Verify sort**
  - Click Domain header — rows sort A→Z; arrow appears
  - Click Domain header again — rows sort Z→A
  - Click Client header — rows sort by client
  - Click Status header — Allowed rows group together, Blocked rows group together
  - Sort arrow moves to the clicked column

- [ ] **Verify compose**
  - Type "google" in search, then click Domain header — filtered rows are sorted

- [ ] **Verify reset**
  - With search + sort active, click Refresh — both clear, arrow disappears
  - With search + sort active, change server filter popup — both clear

- [ ] **Verify no crash**
  - Shift-click a second column header — no crash; only first descriptor applied
