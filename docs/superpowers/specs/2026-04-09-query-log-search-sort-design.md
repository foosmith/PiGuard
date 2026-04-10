# Query Log Search & Sort — Design Spec

**Date:** 2026-04-09
**Status:** Approved

---

## Overview

Add a search field and column-header sorting to the Query Log window in PiGuard. The user can type to filter rows across all visible fields, and click column headers for Domain, Client, and Status to sort ascending/descending.

---

## Scope

- **In scope:** Search field in toolbar; sortable column headers for Domain, Client, and Status; sort indicators (arrows) rendered by NSTableView automatically.
- **Out of scope:** Persisting sort/search state across sessions; sorting the Time or Server columns; server-side search.

---

## Architecture

All changes are confined to `PiGuard/Views/QueryLog/QueryLogViewController.swift`. No new files are needed.

### State

Two new private stored properties are added:

```swift
private var searchText: String = ""
private var currentSortDescriptors: [NSSortDescriptor] = []
private let searchField = NSSearchField()
```

`searchField` must be a stored property so `fetchQueryLog()` can clear it on refresh and so target/action wiring works.

### Toolbar

`searchField` is added to the left side of the existing toolbar stack view, prepended before `serverFilterPopup`. The existing `NSView()` spacer is already present in the stack and must **not** be duplicated.

Updated toolbar array (left → right):
```swift
[searchField, serverFilterPopup, NSView(), statusLabel, refreshButton]
```

`searchField.target = self`, `searchField.action = #selector(searchChanged(_:))`.

`NSTableView.allowsColumnSorting` is `true` by default; no explicit flag is needed.

### Sortable Columns

`sortDescriptorPrototype` is set on three columns. The string key is used as a **convention token only** — it is never passed to KVC. The selector must be `nil` to prevent any KVC-based comparison path being invoked:

```swift
domainCol.sortDescriptorPrototype = NSSortDescriptor(key: "domain", ascending: true, selector: nil)
clientCol.sortDescriptorPrototype = NSSortDescriptor(key: "client", ascending: true, selector: nil)
statusCol.sortDescriptorPrototype = NSSortDescriptor(key: "status", ascending: true, selector: nil)
```

Time and Server columns remain unsortable (no `sortDescriptorPrototype`).

### applyFilter()

`applyFilter()` owns **all** display state updates — filtering, sorting, and the status label count. This ensures that both search input and column-header clicks keep the label current.

Steps:
1. Filter `entries` by server identifier (existing logic).
2. Further filter by `searchText` — case-insensitive `contains` across `domain`, `client`, `status.rawValue`, and `serverDisplayName`.
3. Apply `currentSortDescriptors` — use only the **first** descriptor (multi-column sort is not supported). Switch on `descriptor.key` to select the sort field; respect `descriptor.ascending`:

```swift
if let descriptor = currentSortDescriptors.first {
    filteredEntries.sort { a, b in
        let result: Bool
        switch descriptor.key {
        case "domain": result = a.domain.localizedCaseInsensitiveCompare(b.domain) == .orderedAscending
        case "client": result = a.client.localizedCaseInsensitiveCompare(b.client) == .orderedAscending
        case "status": result = a.status.rawValue < b.status.rawValue
        default: result = false
        }
        return descriptor.ascending ? result : !result
    }
}
```

> Note: Status sorts alphabetically on rawValue ("Allowed" < "Blocked"), which groups the two values together as intended.

4. Reload the table.
5. Update the status label: `statusLabel.stringValue = "\(filteredEntries.count) queries"`.

### Sort Descriptor Delegate

In the `NSTableViewDelegate` extension:

```swift
func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
    currentSortDescriptors = tableView.sortDescriptors
    applyFilter()
}
```

NSTableView automatically updates the sort arrow indicator on the active column.

### Search Action

```swift
@objc private func searchChanged(_ sender: NSSearchField) {
    searchText = sender.stringValue
    applyFilter()
}
```

Search does **not** trigger a network fetch — it filters the already-loaded `entries` in memory.

### Sort Reset on Refresh

When `fetchQueryLog()` receives new data and calls `MainActor.run`, it resets state in this order **before** calling `applyFilter()`:

```swift
self.searchText = ""
self.searchField.stringValue = ""
self.currentSortDescriptors = []
tableView.sortDescriptors = []   // fires sortDescriptorsDidChange, but currentSortDescriptors is already [] so applyFilter() is a no-op
```

Setting `currentSortDescriptors = []` first ensures the delegate callback from `tableView.sortDescriptors = []` is a no-op and does not cause a double `applyFilter()` call with stale state.

---

## Behavior Summary

| Action | Result |
|--------|--------|
| Type in search field | Rows filtered live; status label updates count |
| Click Domain/Client/Status header | Sort ascending; click again → descending |
| Change server filter popup | Re-fetches data; search and sort reset |
| Click Refresh | Re-fetches data; search and sort reset |
| Search + sort active together | Search narrows rows, sort orders them |

---

## Testing Checklist

- [ ] Search field filters rows containing the typed string in any field (domain, client, status, server)
- [ ] Search is case-insensitive
- [ ] Clicking Domain header sorts ascending; second click sorts descending
- [ ] Clicking Client header sorts ascending; second click sorts descending
- [ ] Clicking Status header sorts alphabetically by rawValue (Allowed < Blocked), grouping the two values together
- [ ] Sort arrow appears on the active column header and disappears when sort is cleared
- [ ] Status label count updates correctly after search and after sort
- [ ] Changing server filter resets search field, sort state, and sort indicator
- [ ] Refresh resets search field, sort state, and sort indicator
- [ ] Empty search field shows all entries (subject to server filter)
- [ ] Shift-clicking a second column header does not crash; only the first descriptor is applied
