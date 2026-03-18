#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PiBar.xcodeproj"
SCHEME="PiBar"
CONFIGURATION="Release"
OUTPUT_DIR="$ROOT_DIR/build/release"
DERIVED_DATA_PATH="$OUTPUT_DIR/DerivedData"

function usage() {
    cat <<'EOF'
Usage: scripts/build-release-dmg.sh [options]

Options:
  --artifact-name NAME     Override the output file name without the .dmg suffix.
  --output-dir PATH        Directory where the DMG should be written.
  --derived-data PATH      DerivedData path to use for the build.
  --configuration NAME     Xcode build configuration. Default: Release
  --codesign               Allow Xcode code signing during the build.
  --sign-identity NAME     Manually codesign the app and DMG with this identity.
  --notary-profile NAME    Submit the DMG for notarization with this notarytool keychain profile.
  --bundle-id ID           Bundle identifier used for notarization metadata. Default: project setting.
  --help                   Show this help text.

Example:
  scripts/build-release-dmg.sh \
    --artifact-name PiBar-1.2-beta2-macOS \
    --sign-identity 'Developer ID Application: Example, Inc. (TEAMID1234)' \
    --notary-profile pibar-notary
EOF
}

ARTIFACT_NAME=""
CODE_SIGNING_ALLOWED="NO"
SIGN_IDENTITY=""
NOTARY_PROFILE=""
BUNDLE_ID=""

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
        --bundle-id)
            BUNDLE_ID="${2:-}"
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
    rg -N "^[[:space:]]*${key} = " "$PROJECT_PATH/project.pbxproj" \
        | head -n 1 \
        | sed -E "s/^[[:space:]]*${key} = ([^;]+);$/\1/"
}

MARKETING_VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
APP_NAME="PiBar"
BUNDLE_ID="${BUNDLE_ID:-$(read_project_setting PRODUCT_BUNDLE_IDENTIFIER)}"

if [[ -z "$ARTIFACT_NAME" ]]; then
    ARTIFACT_NAME="${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-macOS"
fi

VOLUME_NAME="${APP_NAME} ${MARKETING_VERSION} (${BUILD_NUMBER})"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/${APP_NAME}.app"
DMG_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

rm -rf "$STAGING_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGING_DIR"

echo "Building ${APP_NAME}.app..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk macosx \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "CODE_SIGNING_ALLOWED=${CODE_SIGNING_ALLOWED}" \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build succeeded but ${APP_PATH} was not found." >&2
    exit 1
fi

echo "Preparing DMG staging directory..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing ${APP_NAME}.app with ${SIGN_IDENTITY}..."
    codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$STAGING_DIR/${APP_NAME}.app"
fi

echo "Creating ${DMG_PATH}..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing DMG with ${SIGN_IDENTITY}..."
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "Notarization requires --sign-identity." >&2
        exit 1
    fi

    echo "Submitting DMG for notarization with profile ${NOTARY_PROFILE}..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"

    echo "Validating stapled ticket..."
    xcrun stapler validate "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"

echo "DMG created: $DMG_PATH"
