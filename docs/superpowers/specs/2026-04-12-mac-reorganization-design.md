# macOS Reorganization Design

**Date:** 2026-04-12  
**Status:** Approved

## Goal

Group the macOS-specific files into a `mac/` directory at the repo root, mirroring the existing `windows/` layout, without breaking any builds or tooling.

## Before / After

```
# Before
pibar-enhanced/
  PiGuard/
  PiGuard.xcodeproj/
  scripts/
  buildServer.json      (gitignored)
  build/                (gitignored)
  global.json
  windows/
  docs/
  icons/
  LICENSE, README.md, CLAUDE.md

# After
pibar-enhanced/
  mac/
    PiGuard/
    PiGuard.xcodeproj/
    scripts/
  windows/
    src/
    global.json
    ...
  docs/
  icons/
  LICENSE, README.md, CLAUDE.md
```

## Changes

| Item | Action | Notes |
|---|---|---|
| `PiGuard/` | Move to `mac/PiGuard/` | Xcode relative paths unchanged (moves with project) |
| `PiGuard.xcodeproj/` | Move to `mac/PiGuard.xcodeproj/` | Same relative layout to source files |
| `scripts/` | Move to `mac/scripts/` | `ROOT_DIR` computed as `$(dirname "$0")/..` — still resolves to `mac/` correctly |
| `global.json` | Move to `windows/global.json` | .NET SDK pin; belongs with Windows app |
| `buildServer.json` | Delete; regenerate after move | Already gitignored; machine-specific absolute paths |
| `build/` | Leave/ignore | Gitignored; recreated by next build |

## Why It's Safe

- **Xcode project paths:** The `.pbxproj` stores paths relative to the `.xcodeproj` file. Since `PiGuard/` and `PiGuard.xcodeproj/` move together into `mac/`, all relative references remain valid.
- **Build scripts:** Both scripts compute `ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"`. After moving `scripts/` to `mac/scripts/`, `ROOT_DIR` resolves to `mac/` — where `PiGuard.xcodeproj/` and the source files now live. No edits required.
- **`buildServer.json`:** Contains absolute paths baked in at generation time. It is already gitignored. After the move, the user runs `xcode-build-server config -scheme PiGuard -project mac/PiGuard.xcodeproj` to regenerate it.
- **Windows side:** `global.json` moves into `windows/`. The .NET SDK toolchain discovers it by walking up the directory tree, so placing it inside `windows/` is correct.
- **Shared files:** `docs/`, `icons/`, `LICENSE`, `README.md`, `CLAUDE.md` are untouched.

## Post-Move Step (manual)

After the git move, regenerate `buildServer.json` from the repo root:

```bash
xcode-build-server config -scheme PiGuard -project mac/PiGuard.xcodeproj
```

## Out of Scope

- Renaming anything inside `PiGuard/` or `PiGuard.xcodeproj/`
- Reorganizing `windows/` internals
- Updating `docs/` or `README.md` content
