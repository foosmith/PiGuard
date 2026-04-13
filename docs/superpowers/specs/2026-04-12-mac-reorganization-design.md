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
| `README.md` (Xcode resource) | Remove from Xcode project | README.md is listed in `PBXResourcesBuildPhase` — after the move Xcode would look for it inside `mac/` and fail. Remove the reference from the project; it should not be bundled in the app anyway. |
| `scripts/` | Move to `mac/scripts/` | `ROOT_DIR` computed as `$(dirname "$0")/..` — still resolves to `mac/` correctly |
| `global.json` | Move to `windows/global.json` | .NET SDK pin; belongs with Windows app |
| `buildServer.json` | Delete; regenerate after move | Already gitignored; machine-specific absolute paths |
| `build/` | Leave/ignore | Gitignored; recreated by next build |

## Why It's Safe

- **Xcode project paths:** The `.pbxproj` stores paths relative to the `.xcodeproj` file. Since `PiGuard/` and `PiGuard.xcodeproj/` move together into `mac/`, all relative references (source files, `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`) remain valid.
- **Build scripts:** Both scripts compute `ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"`. After moving `scripts/` to `mac/scripts/`, `ROOT_DIR` resolves to `mac/` — where `PiGuard.xcodeproj/` and the source files now live. This also means `$ROOT_DIR/PiGuard/PiGuard.entitlements` (referenced in `build-release-zip.sh`) resolves correctly to `mac/PiGuard/PiGuard.entitlements`. No script edits required.
- **`buildServer.json`:** Contains absolute paths baked in at generation time. Already gitignored. Regenerated after the move (lands at repo root, covered by existing `.gitignore` entry).
- **Windows side:** `global.json` moves into `windows/`. The .NET SDK finds it by walking up from the working directory. Running `dotnet` from inside `windows/` (the normal case) still works. Note: running `dotnet` from the repo root will no longer find the pinned SDK version — but all Windows build activity is rooted in `windows/`.
- **`Package.resolved`:** Lives inside `PiGuard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` and contains only remote URLs — no local paths. Moves safely with the project.

## Post-Move Steps (manual)

After the git moves:

1. Regenerate `buildServer.json` from the repo root:
   ```bash
   xcode-build-server config -scheme PiGuard -project mac/PiGuard.xcodeproj
   ```

2. Clear stale DerivedData so Xcode rebuilds cleanly from the new paths:
   ```bash
   # Xcode's global DerivedData (normal development builds)
   rm -rf ~/Library/Developer/Xcode/DerivedData/PiGuard-*
   # Release script output (only exists after running a build script)
   rm -rf mac/build/
   ```

## Out of Scope

- Renaming anything inside `PiGuard/` or `PiGuard.xcodeproj/`
- Reorganizing `windows/` internals
- Updating `docs/` or `README.md` content
