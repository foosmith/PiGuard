# PiGuard for Windows

This folder contains the Windows port foundation for PiGuard.

Current scope:
- `PiGuard.Core`: reusable models, settings abstractions, sync activity abstractions, and cross-platform service contracts
- `PiGuard.Windows`: tray-first Windows shell scaffold in `C# / .NET 8 / WPF`

The Windows app is intentionally structured so the tray utility can grow into a fuller desktop application later without replacing the core service layer.

Planning docs:
- [Windows implementation plan](docs/windows-plan.md)

Planned next implementation steps:
- Port Pi-hole v5/v6 API clients into `PiGuard.Core`
- Port polling/update/sync orchestration into the core service layer
- Replace placeholder windows with fully functional settings and sync flows
- Add Windows-specific startup, hotkey, notification, and update plumbing
