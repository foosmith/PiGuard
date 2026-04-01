# Windows Implementation Plan

## Summary

PiGuard for Windows should be built as a Windows-native application, not as a Swift port. The right first release is a tray-first app that matches the current product's day-to-day workflow while keeping the architecture open for a larger desktop experience later.

Recommended stack:
- `C#`
- `.NET 8`
- `WPF`
- `MVVM` structure
- Windows-native integrations for tray UI, startup, notifications, hotkeys, and secure credential storage

This approach gives the best Windows fit for a utility app and avoids forcing the macOS AppKit design into a platform where it does not belong.

## Product Direction

The first Windows release should behave like the current menu bar app:
- tray icon with status and quick actions
- preferences window
- sync settings window
- about window
- sync and gravity actions
- Pi-hole status visibility across multiple connections

The architecture should still support future expansion into a broader desktop application without replacing the core services.

## Architecture

Create two main layers:

### 1. Shared Core

`PiGuard.Core` should own:
- Pi-hole v5 and v6 API clients
- models for connections, preferences, status snapshots, sync state, and activity
- polling/update orchestration
- primary-to-secondary sync engine
- logging abstractions
- interfaces for notifications, startup, credentials, and hotkeys

This layer should stay UI-agnostic so it can be tested and reused independently from the Windows shell.

### 2. Windows Shell

`PiGuard.Windows` should own:
- tray icon and context menu
- WPF windows and view models
- Windows-specific startup registration
- secure credential storage
- notifications
- packaging and release wiring

The shell should consume the core services rather than embedding business logic inside views.

## Feature Scope

Windows parity target:
- multi-instance Pi-hole connection management
- Pi-hole v5 and v6 support
- aggregate status and polling
- enable/disable blocking actions
- gravity update action
- sync now action
- dry run sync mode
- wipe-secondary sync mode
- sync activity log
- last sync summary and status
- tray feedback for in-progress sync and gravity work

## Windows Integrations

Platform-specific work includes:
- tray menu via Windows-native notification area behavior
- startup registration through Windows startup mechanisms
- secure secret storage through Windows Credential Manager or DPAPI-backed storage
- toast notifications for success/failure states
- global hotkey registration
- browser launch into the Pi-hole admin UI
- installer and update path for Windows distribution

## Current Workspace Structure

The Windows workspace currently includes:
- `windows/src/PiGuard.Core`
- `windows/src/PiGuard.Windows`
- `windows/PiGuard.Windows.sln`

The current codebase already establishes:
- shared models and service contracts
- JSON-backed settings storage
- sync activity feed scaffolding
- a tray-first WPF shell
- placeholder Preferences, Sync Settings, and About windows
- startup and credential storage service stubs

## Implementation Phases

### Phase 1: Foundation

Completed in initial scaffold:
- solution and project structure
- core contracts and models
- tray shell
- placeholder windows
- Windows startup and credential service scaffolding

### Phase 2: Core Port

Next major work:
- port Pi-hole API clients from the macOS app into `PiGuard.Core`
- port polling/state aggregation
- port sync engine behavior
- port sync progress and activity reporting

### Phase 3: Functional UI

After core behavior is in place:
- replace placeholder windows with functional forms
- bind views to real view models
- surface status, validation, and sync progress in the tray and windows

### Phase 4: Windows Polish

Then add:
- toast notifications
- startup toggle wiring
- hotkey support
- better tray icon states
- installer/update strategy

## Testing Plan

Core testing:
- API client success and failure cases
- multi-node polling behavior
- sync dry run and destructive sync behavior
- error handling and activity log output

Windows shell testing:
- tray icon lifecycle
- menu actions
- window open/close behavior
- startup registration
- credential persistence
- toast notification flow

Release testing:
- clean install on Windows
- upgrade path
- startup on login
- persistence of settings and credentials across upgrades

## Constraints

- The macOS AppKit UI does not port directly to Windows.
- The Swift codebase should be treated as the behavior reference, not as shared UI code.
- macOS can compile the solution, but real WPF runtime validation and packaging still need a Windows machine.

## Immediate Next Steps

1. Port the Pi-hole API clients into `PiGuard.Core`.
2. Port polling and sync orchestration into the core layer.
3. Build real view models for Preferences and Sync Settings.
4. Replace placeholder tray actions with live behavior.
5. Move packaging and Windows release work onto a Windows environment.
