#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/release"
DERIVED_DATA_PATH="$OUTPUT_DIR/DerivedData"
CONFIGURATION="Release"
ARTIFACT_NAME=""
SIGN_IDENTITY=""
NOTARY_PROFILE=""

function usage() {
    cat <<'EOF'
Usage: scripts/build-release-dmg.sh [options]

Options:
  --artifact-name NAME     Override the output file name without the .dmg suffix.
  --output-dir PATH        Directory where the DMG should be written.
  --derived-data PATH      DerivedData path to use for the build.
  --configuration NAME     Xcode build configuration. Default: Release
  --sign-identity NAME     Build and sign the app with this identity.
  --notary-profile NAME    Notarize the app ZIP and the DMG with this notarytool profile.
  --help                   Show this help text.

Example:
  scripts/build-release-dmg.sh \
    --artifact-name PiBar-2.0-rc1-macOS \
    --sign-identity 'Developer ID Application: Example, Inc. (TEAMID1234)' \
    --notary-profile pibar-notary
EOF
}

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

if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "--sign-identity is required for DMG releases." >&2
    exit 1
fi

function read_project_setting() {
    local key="$1"
    rg -m 1 -N "^[[:space:]]*${key} = " "$ROOT_DIR/PiBar.xcodeproj/project.pbxproj" \
        | perl -pe 's/\r$//' \
        | sed -E "s/^[[:space:]]*${key} = ([^;]+);$/\1/"
}

function run_codesign_verify() {
    local path="$1"
    echo "Verifying code signature: $path"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$path"
}

MARKETING_VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
APP_NAME="PiBar"

if [[ -z "$ARTIFACT_NAME" ]]; then
    ARTIFACT_NAME="${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-macOS"
fi

ZIP_ARTIFACT_NAME="${ARTIFACT_NAME}-app"
ZIP_PATH="$OUTPUT_DIR/${ZIP_ARTIFACT_NAME}.zip"
DMG_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
VOLUME_NAME="${APP_NAME} ${MARKETING_VERSION} (${BUILD_NUMBER})"

zip_build_args=(
    "$ROOT_DIR/scripts/build-release-zip.sh"
    --artifact-name "$ZIP_ARTIFACT_NAME"
    --output-dir "$OUTPUT_DIR"
    --derived-data "$DERIVED_DATA_PATH"
    --configuration "$CONFIGURATION"
    --sign-identity "$SIGN_IDENTITY"
)

if [[ -n "$NOTARY_PROFILE" ]]; then
    zip_build_args+=(--notary-profile "$NOTARY_PROFILE")
fi

echo "Building release app ZIP..."
"${zip_build_args[@]}"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
/usr/bin/ditto -x -k "$ZIP_PATH" "$STAGING_DIR"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating ${DMG_PATH}..."
rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Signing DMG with ${SIGN_IDENTITY}..."
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
run_codesign_verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Submitting ${DMG_PATH} for notarization with profile ${NOTARY_PROFILE}..."
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
