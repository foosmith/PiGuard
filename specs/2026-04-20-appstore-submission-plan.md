# App Store Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "AppStore" Xcode build configuration + scheme (Sparkle excluded, APPSTORE flag set), add a Sparkle strip script build phase, and add a PrivacyInfo.xcprivacy — enabling dual distribution via GitHub DMG and Mac App Store from a single target.

**Architecture:** All changes are in `project.pbxproj` (new XCBuildConfiguration objects and a PBXShellScriptBuildPhase, wired into the existing XCConfigurationLists and buildPhases array) plus two new files (`PrivacyInfo.xcprivacy` and `PiGuard AppStore.xcscheme`). No Swift source changes needed — `#if !APPSTORE` guards are already in place.

**Tech Stack:** Xcode project file (pbxproj), xcscheme XML, xcprivacy plist

> **IMPORTANT — Build signing:** Per project rules, code-signing steps can hang. Always pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild` for verification builds. Never build with signing enabled from the command line unless explicitly instructed.

> **Note on DEVELOPMENT_TEAM at project level:** The project-level Release config has `DEVELOPMENT_TEAM = 2Y9M69QJKZ` (a different team ID from the target-level value of `GB7Z2TZ8LT`). The project-level AppStore config overrides this to `GB7Z2TZ8LT` so that signing resolution is consistent at both levels for App Store distribution.

> **Note on SPM framework embedding:** Sparkle is a Swift Package dependency. Xcode embeds SPM frameworks automatically during the build (not via the explicit `files = ()` array in the Embed Frameworks phase — that array is for manually-added frameworks only). This means Sparkle IS present in the built bundle at `Contents/Frameworks/Sparkle.framework` after each build, which is exactly the path the strip script targets. Verified against an existing Release build.

> **Working directory for all steps:** `mac/` inside the repo root (`/Users/smithm/Library/CloudStorage/OneDrive-Personal/Documents/PiGuard/mac/`)

---

## File Map

| Action | Path |
|--------|------|
| Modify | `mac/PiGuard.xcodeproj/project.pbxproj` |
| Create | `mac/PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme` |
| Create | `mac/PiGuard/PrivacyInfo.xcprivacy` |

**New UUIDs used in this plan:**

| UUID | Purpose |
|------|---------|
| `PGAS0001PGAS0001PGAS0001` | Project-level AppStore XCBuildConfiguration |
| `PGAS0002PGAS0002PGAS0002` | Target-level AppStore XCBuildConfiguration |
| `PGAS0003PGAS0003PGAS0003` | Strip Sparkle PBXShellScriptBuildPhase |
| `PGAS0004PGAS0004PGAS0004` | PrivacyInfo.xcprivacy PBXFileReference |
| `PGAS0005PGAS0005PGAS0005` | PrivacyInfo.xcprivacy PBXBuildFile |

---

### Task 1: Project-level AppStore build configuration

Fix the pre-existing bug (Release has `APPSTORE` flag, breaking DMG builds) and add a proper project-level AppStore config.

**Files:**
- Modify: `mac/PiGuard.xcodeproj/project.pbxproj`

- [ ] **Step 1: Remove the APPSTORE flag from project-level Release**

In `project.pbxproj`, find and remove this exact line from the Release block (UUID `449395E12471ABD700FA0C34`):

```
				"SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*]" = APPSTORE;
```

The Release block is at line ~486. After removal, the block should go straight from `STRING_CATALOG_GENERATE_SYMBOLS = YES;` to `SWIFT_COMPILATION_MODE = wholemodule;`.

- [ ] **Step 2: Add the project-level AppStore configuration block**

In `project.pbxproj`, find the line:

```
/* End XCBuildConfiguration section */
```

Insert the following block immediately **before** that line (preserve the tab indentation — each line starts with two tabs):

```
		PGAS0001PGAS0001PGAS0001 /* AppStore */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++14";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				DEVELOPMENT_TEAM = GB7Z2TZ8LT;
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 11.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				"SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*]" = APPSTORE;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = AppStore;
		};
```

- [ ] **Step 3: Add the new UUID to the project-level XCConfigurationList**

Find this block (UUID `449395CD2471ABD600FA0C34`):

```
		449395CD2471ABD600FA0C34 /* Build configuration list for PBXProject "PiGuard" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				449395E02471ABD700FA0C34 /* Debug */,
				449395E12471ABD700FA0C34 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

Replace it with:

```
		449395CD2471ABD600FA0C34 /* Build configuration list for PBXProject "PiGuard" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				449395E02471ABD700FA0C34 /* Debug */,
				449395E12471ABD700FA0C34 /* Release */,
				PGAS0001PGAS0001PGAS0001 /* AppStore */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 4: Verify the Release config no longer has the APPSTORE flag**

```bash
grep "APPSTORE" PiGuard.xcodeproj/project.pbxproj
```

Expected: all matches are inside the `PGAS0001PGAS0001PGAS0001` block or comment lines (e.g. `/* AppStore */`). There should be **no** match inside the `449395E12471ABD700FA0C34 /* Release */` block.

- [ ] **Step 5: Commit**

```bash
git add PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add project-level AppStore build config; fix Release APPSTORE flag"
```

---

### Task 2: Target-level AppStore build configuration

Add the target-level AppStore config with `CODE_SIGN_IDENTITY` keys absent (so Automatic signing selects Distribution at archive time) and `ENABLE_USER_SCRIPT_SANDBOXING = NO`.

**Files:**
- Modify: `mac/PiGuard.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the target-level AppStore configuration block**

In `project.pbxproj`, find the line:

```
/* End XCBuildConfiguration section */
```

Insert the following block immediately **before** that line:

```
		PGAS0002PGAS0002PGAS0002 /* AppStore */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = PiGuard/PiGuard.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 703;
				DEAD_CODE_STRIPPING = YES;
				DEVELOPMENT_TEAM = GB7Z2TZ8LT;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				FRAMEWORK_SEARCH_PATHS = "$(inherited)";
				INFOPLIST_FILE = PiGuard/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = PiGuard;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 11.0;
				MARKETING_VERSION = 3.5;
				PRODUCT_BUNDLE_IDENTIFIER = com.foosmith.PiGuard;
				PRODUCT_MODULE_NAME = PiGuard;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			};
			name = AppStore;
		};
```

Note: `CODE_SIGN_IDENTITY` and `"CODE_SIGN_IDENTITY[sdk=macosx*]"` are intentionally absent — Xcode Automatic signing will select the Distribution certificate at archive time.

- [ ] **Step 2: Add the new UUID to the target-level XCConfigurationList**

Find this block (UUID `449395E22471ABD700FA0C34`):

```
		449395E22471ABD700FA0C34 /* Build configuration list for PBXNativeTarget "PiGuard" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				449395E32471ABD700FA0C34 /* Debug */,
				449395E42471ABD700FA0C34 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

Replace it with:

```
		449395E22471ABD700FA0C34 /* Build configuration list for PBXNativeTarget "PiGuard" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				449395E32471ABD700FA0C34 /* Debug */,
				449395E42471ABD700FA0C34 /* Release */,
				PGAS0002PGAS0002PGAS0002 /* AppStore */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 3: Verify both AppStore configs are registered**

```bash
grep -c "AppStore" PiGuard.xcodeproj/project.pbxproj
```

Expected: 6 or more matches (the two config blocks, two list entries, and the two `name = AppStore;` lines).

- [ ] **Step 4: Commit**

```bash
git add PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add target-level AppStore build config"
```

---

### Task 3: AppStore Xcode scheme

Create the shared scheme file so any developer (and CI) can archive with the AppStore configuration without needing their local xcuserdata.

**Files:**
- Create: `mac/PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme`

- [ ] **Step 1: Create the xcshareddata/xcschemes directory**

```bash
mkdir -p PiGuard.xcodeproj/xcshareddata/xcschemes
```

- [ ] **Step 2: Write the scheme file**

Create `PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme` with this exact content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "449395D12471ABD600FA0C34"
               BuildableName = "PiGuard.app"
               BlueprintName = "PiGuard"
               ReferencedContainer = "container:PiGuard.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "449395D12471ABD600FA0C34"
            BuildableName = "PiGuard.app"
            BlueprintName = "PiGuard"
            ReferencedContainer = "container:PiGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "AppStore"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "449395D12471ABD600FA0C34"
            BuildableName = "PiGuard.app"
            BlueprintName = "PiGuard"
            ReferencedContainer = "container:PiGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "AppStore">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "AppStore"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: Verify xcodebuild can see the new scheme**

```bash
xcodebuild -project PiGuard.xcodeproj -list 2>&1 | grep -A5 "Schemes:"
```

Expected output includes `PiGuard AppStore` in the schemes list.

- [ ] **Step 4: Verify AppStore config builds (no signing)**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

If the build fails with a Sparkle-related compile error, double-check that the `SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*] = APPSTORE` setting landed in `PGAS0001PGAS0001PGAS0001` and not in any other block.

- [ ] **Step 5: Commit**

```bash
git add PiGuard.xcodeproj/xcshareddata/xcschemes/"PiGuard AppStore.xcscheme"
git commit -m "feat: add PiGuard AppStore Xcode scheme"
```

---

### Task 4: Sparkle strip script build phase

Add a Run Script phase that removes `Sparkle.framework` from the built bundle when building the AppStore configuration.

**Files:**
- Modify: `mac/PiGuard.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the PBXShellScriptBuildPhase entry**

In `project.pbxproj`, find:

```
/* End PBXShellScriptBuildPhase section */
```

Insert the following block immediately **before** that line:

```
		PGAS0003PGAS0003PGAS0003 /* Strip Sparkle (AppStore) */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = "Strip Sparkle (AppStore)";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "if [ \"$CONFIGURATION\" = \"AppStore\" ]; then\n    rm -rf \"$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks/Sparkle.framework\"\nfi\n";
		};
```

- [ ] **Step 2: Append the phase UUID to the target's buildPhases array**

Find this block in the PBXNativeTarget section:

```
			buildPhases = (
				449395CE2471ABD600FA0C34 /* Sources */,
				449395CF2471ABD600FA0C34 /* Frameworks */,
				449395D02471ABD600FA0C34 /* Resources */,
				447CCB5D2D895B5800811F7C /* ShellScript */,
				441E78AB247E21DE00FBC7A0 /* Embed Frameworks */,
				52E46A512F92D6EC0013DD87 /* CopyFiles */,
			);
```

Replace it with:

```
			buildPhases = (
				449395CE2471ABD600FA0C34 /* Sources */,
				449395CF2471ABD600FA0C34 /* Frameworks */,
				449395D02471ABD600FA0C34 /* Resources */,
				447CCB5D2D895B5800811F7C /* ShellScript */,
				441E78AB247E21DE00FBC7A0 /* Embed Frameworks */,
				52E46A512F92D6EC0013DD87 /* CopyFiles */,
				PGAS0003PGAS0003PGAS0003 /* Strip Sparkle (AppStore) */,
			);
```

- [ ] **Step 3: Verify the strip script is last in buildPhases**

```bash
grep -A12 "buildPhases = (" PiGuard.xcodeproj/project.pbxproj | grep "PGAS0003"
```

Expected: one match containing `PGAS0003PGAS0003PGAS0003`.

- [ ] **Step 4: Build AppStore config and verify Sparkle is absent from the bundle**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

Then verify Sparkle was removed:

```bash
APP_PATH=$(xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " BUILT_PRODUCTS_DIR " | awk '{print $3}')
ls "$APP_PATH/PiGuard.app/Contents/Frameworks/" 2>/dev/null | grep -v Sparkle && echo "Sparkle absent" || echo "CHECK: Sparkle.framework found"
```

Expected: `Sparkle absent` (or a list of other frameworks with no Sparkle entry).

- [ ] **Step 5: Also verify Release config still includes Sparkle (DMG build not broken)**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme PiGuard \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add Sparkle strip script build phase for AppStore builds"
```

---

### Task 5: PrivacyInfo.xcprivacy

Add the required privacy manifest to the PiGuard target.

**Files:**
- Create: `mac/PiGuard/PrivacyInfo.xcprivacy`
- Modify: `mac/PiGuard.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the PrivacyInfo.xcprivacy file**

Create `PiGuard/PrivacyInfo.xcprivacy` with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Add PBXFileReference to project.pbxproj**

In `project.pbxproj`, find:

```
/* End PBXFileReference section */
```

Insert this line immediately **before** it:

```
		PGAS0004PGAS0004PGAS0004 /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add PBXBuildFile to project.pbxproj**

In `project.pbxproj`, find:

```
/* End PBXBuildFile section */
```

Insert this line immediately **before** it:

```
		PGAS0005PGAS0005PGAS0005 /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = PGAS0004PGAS0004PGAS0004 /* PrivacyInfo.xcprivacy */; };
```

- [ ] **Step 4: Add file to the PiGuard group**

Find the PiGuard group (UUID `449395D42471ABD600FA0C34`):

```
		449395D42471ABD600FA0C34 /* PiGuard */ = {
			isa = PBXGroup;
			children = (
				449395DE2471ABD700FA0C34 /* Info.plist */,
				449395DF2471ABD700FA0C34 /* PiGuard.entitlements */,
				449395D92471ABD700FA0C34 /* Assets.xcassets */,
```

Replace the `children` opening to add PrivacyInfo alongside the other config files:

```
		449395D42471ABD600FA0C34 /* PiGuard */ = {
			isa = PBXGroup;
			children = (
				449395DE2471ABD700FA0C34 /* Info.plist */,
				449395DF2471ABD700FA0C34 /* PiGuard.entitlements */,
				PGAS0004PGAS0004PGAS0004 /* PrivacyInfo.xcprivacy */,
				449395D92471ABD700FA0C34 /* Assets.xcassets */,
```

- [ ] **Step 5: Add build file to the Resources build phase**

Find the Resources build phase (UUID `449395D02471ABD600FA0C34`):

```
		449395D02471ABD600FA0C34 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				449395DA2471ABD700FA0C34 /* Assets.xcassets in Resources */,
				449395DD2471ABD700FA0C34 /* Main.storyboard in Resources */,
				449395E62471AC0700FA0C34 /* MainMenu.xib in Resources */,
			);
```

Replace it with:

```
		449395D02471ABD600FA0C34 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				449395DA2471ABD700FA0C34 /* Assets.xcassets in Resources */,
				449395DD2471ABD700FA0C34 /* Main.storyboard in Resources */,
				449395E62471AC0700FA0C34 /* MainMenu.xib in Resources */,
				PGAS0005PGAS0005PGAS0005 /* PrivacyInfo.xcprivacy in Resources */,
			);
```

- [ ] **Step 6: Verify the file is bundled in a build**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

Then check the built bundle contains the file:

```bash
APP_PATH=$(xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " BUILT_PRODUCTS_DIR " | awk '{print $3}')
ls "$APP_PATH/PiGuard.app/Contents/Resources/PrivacyInfo.xcprivacy" && echo "PrivacyInfo present"
```

Expected: `PrivacyInfo present`

- [ ] **Step 7: Commit**

```bash
git add PiGuard/PrivacyInfo.xcprivacy PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add PrivacyInfo.xcprivacy to PiGuard target"
```

---

### Task 6: Final verification and WindowsHotkeyService commit

Tidy up: run a full AppStore build, confirm clean, and commit the outstanding `WindowsHotkeyService.cs` file that has been sitting untracked.

**Files:**
- Verify: `mac/PiGuard.xcodeproj/` (build)
- Commit: `windows/src/PiGuard.Windows/Services/WindowsHotkeyService.cs`

- [ ] **Step 1: Full AppStore build — confirm Sparkle absent and PrivacyInfo present**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme "PiGuard AppStore" \
  -configuration AppStore \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Full Release build — confirm Sparkle still present (direct download not broken)**

```bash
xcodebuild \
  -project PiGuard.xcodeproj \
  -scheme PiGuard \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit WindowsHotkeyService.cs (from repo root)**

```bash
cd ..
git add windows/src/PiGuard.Windows/Services/WindowsHotkeyService.cs
git commit -m "feat: add WindowsHotkeyService implementing IHotkeyService for global hotkey (Ctrl+Alt+Shift+P)"
```

---

## What's Left (Manual Steps)

After this plan is complete, the following steps require your Apple Developer account and cannot be automated:

1. **Open Xcode** → open `mac/PiGuard.xcodeproj`
2. **Select the "PiGuard AppStore" scheme**
3. **Product → Archive** — Xcode will sign with your Distribution certificate automatically
4. **Xcode Organizer** → select the archive → "Distribute App" → "App Store Connect" → upload
5. **App Store Connect** → complete the listing: description, keywords, support URL, screenshots (1280×800 or 1440×900 for macOS), and submit for review
