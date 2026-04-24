#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PiGuard.xcodeproj"
SCHEME="PiGuard AppStore"
CONFIGURATION="Release"
OUTPUT_DIR="$ROOT_DIR/build/release"
# DerivedData is placed outside the OneDrive-synced project tree so that
# OneDrive's file provider does not add com.apple.FinderInfo xattrs to newly
# created directories (which codesign rejects as "detritus").
DERIVED_DATA_PATH="/tmp/PiGuard-release-build/DerivedData"

function usage() {
    cat <<'EOF'
Usage: scripts/build-release-zip.sh [options]

Options:
  --artifact-name NAME     Override the output file name without the .zip suffix.
  --output-dir PATH        Directory where the ZIP should be written.
  --derived-data PATH      DerivedData path to use for the build.
  --configuration NAME     Xcode build configuration. Default: Release
  --codesign               Allow Xcode code signing during the build.
  --sign-identity NAME     Build the app with this identity before zipping it.
  --notary-profile NAME    Submit the ZIP for notarization with this notarytool keychain profile.
  --help                   Show this help text.

Example:
  scripts/build-release-zip.sh \
    --artifact-name PiGuard-<version>-macOS \
    --sign-identity 'Developer ID Application: Example, Inc. (TEAMID1234)' \
    --notary-profile piguard-notary
EOF
}

ARTIFACT_NAME=""
SIGN_IDENTITY=""
NOTARY_PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact-name)
            ARTIFACT_NAME="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --derived-data)
            DERIVED_DATA_PATH="${2:-}"
            shift 2
            ;;
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --codesign)
            CODE_SIGNING_ALLOWED="YES"
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:-}"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

function read_project_setting() {
    local key="$1"
    rg -m 1 -N "^[[:space:]]*${key} = " "$PROJECT_PATH/project.pbxproj" \
        | perl -pe 's/\r$//' \
        | sed -E "s/^[[:space:]]*${key} = ([^;]+);$/\1/"
}

function run_codesign_verify() {
    local path="$1"
    echo "Verifying code signature: $path"
    # Note: --strict is intentionally omitted here. It rejects benign xattrs
    # (e.g. com.apple.FinderInfo added by codesign itself on framework bundles)
    # even though the signature is valid. Apple's notarization service is the
    # authoritative gate for submission readiness.
    /usr/bin/codesign --verify --deep --verbose=2 "$path"
}

function normalize_entitlements() {
    local source_path="$1"
    local output_path="$2"
    /usr/bin/plutil -convert xml1 -o "$output_path" "$source_path"
}

MARKETING_VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
APP_NAME="PiGuard"
DEVELOPMENT_TEAM="$(read_project_setting DEVELOPMENT_TEAM)"
APP_ENTITLEMENTS_PATH="$ROOT_DIR/PiGuard/PiGuard.entitlements"
WIDGET_ENTITLEMENTS_PATH="$ROOT_DIR/PiGuardWidget/PiGuardWidget.entitlements"
WIDGET_ENTITLEMENTS_XML_PATH="$OUTPUT_DIR/PiGuardWidget.release.entitlements"

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Try to extract team from "Name (TEAMID)" format first
    team_from_identity="$(printf '%s\n' "$SIGN_IDENTITY" | sed -nE 's/^.*\(([A-Z0-9]+)\)$/\1/p')"
    if [[ -n "$team_from_identity" ]]; then
        DEVELOPMENT_TEAM="$team_from_identity"
    else
        # SHA1 fingerprint passed — extract TeamIdentifier from the certificate itself
        team_from_cert="$(security find-certificate -a -p login.keychain-db 2>/dev/null \
            | awk -v sha="${SIGN_IDENTITY}" '
                /BEGIN CERTIFICATE/ { pem="" }
                { pem = pem $0 "\n" }
                /END CERTIFICATE/ {
                    cmd = "echo \"" pem "\" | openssl x509 -noout -fingerprint -sha1 2>/dev/null"
                    if ((cmd | getline fp) > 0) {
                        gsub(/SHA1 Fingerprint=|:/, "", fp)
                        if (toupper(fp) == toupper(sha)) found=1
                    }
                    close(cmd)
                    if (found) {
                        cmd2 = "echo \"" pem "\" | openssl x509 -noout -subject 2>/dev/null"
                        while ((cmd2 | getline subj) > 0) print subj
                        close(cmd2)
                        found=0
                        exit
                    }
                }
            ' | grep -oE "OU=[A-Z0-9]+" | head -1 | cut -d= -f2)"
        if [[ -n "$team_from_cert" ]]; then
            DEVELOPMENT_TEAM="$team_from_cert"
        fi
    fi
fi

if [[ -z "$ARTIFACT_NAME" ]]; then
    ARTIFACT_NAME="${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-macOS"
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/${APP_NAME}.app"
ZIP_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.zip"
NOTARY_STAGING_DIR="$OUTPUT_DIR/notary-staging"
APP_ENTITLEMENTS_XML_PATH="$OUTPUT_DIR/PiGuard.release.entitlements"
LAUNCH_AT_LOGIN_RESOURCES_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources"
LOGIN_HELPER_APP_PATH="$APP_PATH/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
LOGIN_HELPER_ENTITLEMENTS_PATH="$LAUNCH_AT_LOGIN_RESOURCES_PATH/LaunchAtLogin.entitlements"
LOGIN_HELPER_ENTITLEMENTS_XML_PATH="$OUTPUT_DIR/LaunchAtLogin.release.entitlements"
LOGIN_HELPER_RESOURCE_BUNDLE_PATH="$APP_PATH/Contents/Resources/LaunchAtLogin_LaunchAtLogin.bundle"

mkdir -p "$OUTPUT_DIR"

echo "Building ${APP_NAME}.app..."
WIDGET_APPEX_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/PiGuardWidget.appex"

xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -sdk macosx
    -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ -n "$SIGN_IDENTITY" ]]; then
    # CODE_SIGN_ENTITLEMENTS="" (empty) bypasses GatherProvisioningInputs:
    #   - keychain-access-groups would normally require a provisioning profile
    #   - clearing CODE_SIGN_ENTITLEMENTS removes that trigger while still allowing signing
    # CODE_SIGNING_ALLOWED=YES lets Xcode sign the widget during the build, so
    # embeddedBinaryValidationUtility sees a properly signed extension.
    # All final re-signing (with correct entitlements) is done by post-build steps below.
    xcodebuild_args+=(
        "CODE_SIGNING_ALLOWED=YES"
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
        "EXPANDED_CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
        "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}"
        "CODE_SIGN_ENTITLEMENTS="
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )

    xcodebuild "${xcodebuild_args[@]}" build
else
    xcodebuild_args+=("CODE_SIGNING_ALLOWED=NO")
    xcodebuild "${xcodebuild_args[@]}" build
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build succeeded but ${APP_PATH} was not found." >&2
    exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Cleaning up build-only LaunchAtLogin resources..."
    rm -rf "$LOGIN_HELPER_RESOURCE_BUNDLE_PATH"
    normalize_entitlements "$APP_ENTITLEMENTS_PATH" "$APP_ENTITLEMENTS_XML_PATH"

    if [[ -d "$LOGIN_HELPER_APP_PATH" ]]; then
        normalize_entitlements "$LOGIN_HELPER_ENTITLEMENTS_PATH" "$LOGIN_HELPER_ENTITLEMENTS_XML_PATH"
        echo "Re-signing embedded login helper..."
        /usr/bin/codesign \
            --force \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            --options runtime \
            --entitlements "$LOGIN_HELPER_ENTITLEMENTS_XML_PATH" \
            "$LOGIN_HELPER_APP_PATH"
        run_codesign_verify "$LOGIN_HELPER_APP_PATH"
    fi

    echo "Stripping extended attributes from app bundle..."
    xattr -cr "$APP_PATH" 2>/dev/null || true

    echo "Re-signing embedded frameworks (inside-out)..."
    # Sign Sparkle's nested helpers and bundles first (inside-out).
    # Autoupdate is a bare Mach-O binary (not a .app bundle), so it needs explicit handling.
    SPARKLE_VERSIONS="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions"
    for sparkle_ver in "$SPARKLE_VERSIONS"/*/; do
        ver_path="${sparkle_ver%/}"
        [[ -d "$ver_path" ]] || continue
        [[ -L "$ver_path" ]] && continue  # skip Current symlink
        for item in \
            "$ver_path/XPCServices/Downloader.xpc" \
            "$ver_path/XPCServices/Installer.xpc" \
            "$ver_path/Updater.app" \
            "$ver_path/Autoupdate"; do
            if [[ -e "$item" ]]; then
                xattr -cr "$item" 2>/dev/null || true
                /usr/bin/codesign \
                    --force \
                    --sign "$SIGN_IDENTITY" \
                    --timestamp \
                    --options runtime \
                    "$item"
            fi
        done
    done
    # Sign remaining frameworks and dylibs
    find "$APP_PATH/Contents/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null | while read -r item; do
        /usr/bin/codesign \
            --force \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            --options runtime \
            "$item"
    done

    # Sign app extensions (e.g. widgets in PlugIns/)
    normalize_entitlements "$WIDGET_ENTITLEMENTS_PATH" "$WIDGET_ENTITLEMENTS_XML_PATH"
    find "$APP_PATH/Contents/PlugIns" -name "*.appex" 2>/dev/null | while read -r item; do
        xattr -cr "$item" 2>/dev/null || true
        echo "Re-signing app extension: $item"
        /usr/bin/codesign \
            --force \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            --options runtime \
            --entitlements "$WIDGET_ENTITLEMENTS_XML_PATH" \
            "$item"
    done

    echo "Stripping extended attributes before final app signing..."
    xattr -cr "$APP_PATH" 2>/dev/null || true

    echo "Re-signing ${APP_NAME}.app with release entitlements..."
    /usr/bin/codesign \
        --force \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        --options runtime \
        --entitlements "$APP_ENTITLEMENTS_XML_PATH" \
        "$APP_PATH"

    echo "Stripping extended attributes added by codesign..."
    xattr -cr "$APP_PATH" 2>/dev/null || true

    run_codesign_verify "$APP_PATH"
else
    echo "Applying ad hoc signature to ${APP_NAME}.app..."
    /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_PATH"
    run_codesign_verify "$APP_PATH"
fi

echo "Stripping extended attributes before archiving..."
xattr -cr "$APP_PATH" 2>/dev/null || true

echo "Creating ${ZIP_PATH}..."
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "Notarization requires --sign-identity." >&2
        exit 1
    fi

    echo "Submitting ${ZIP_PATH} for notarization with profile ${NOTARY_PROFILE}..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    rm -rf "$NOTARY_STAGING_DIR"
    mkdir -p "$NOTARY_STAGING_DIR"
    /usr/bin/ditto -x -k "$ZIP_PATH" "$NOTARY_STAGING_DIR"

    echo "Stapling notarization ticket to ${APP_NAME}.app..."
    xcrun stapler staple "$NOTARY_STAGING_DIR/${APP_NAME}.app"

    echo "Validating stapled ticket..."
    xcrun stapler validate "$NOTARY_STAGING_DIR/${APP_NAME}.app"

    echo "Repacking notarized ZIP..."
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent \
        "$NOTARY_STAGING_DIR/${APP_NAME}.app" \
        "$ZIP_PATH"
fi

echo "ZIP created: $ZIP_PATH"
