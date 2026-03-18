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
  --help                   Show this help text.

Example:
  scripts/build-release-dmg.sh --artifact-name PiBar-1.2-beta2-macOS
EOF
}

ARTIFACT_NAME=""
CODE_SIGNING_ALLOWED="NO"

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

echo "Creating ${DMG_PATH}..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "DMG created: $DMG_PATH"
