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
Usage: scripts/build-release-zip.sh [options]

Options:
  --artifact-name NAME     Override the output file name without the .zip suffix.
  --output-dir PATH        Directory where the ZIP should be written.
  --derived-data PATH      DerivedData path to use for the build.
  --configuration NAME     Xcode build configuration. Default: Release
  --codesign               Allow Xcode code signing during the build.
  --sign-identity NAME     Build the app with this identity before zipping it.
  --help                   Show this help text.

Example:
  scripts/build-release-zip.sh --artifact-name PiBar-2.0-rc1-macOS
EOF
}

ARTIFACT_NAME=""
CODE_SIGNING_ALLOWED="NO"
SIGN_IDENTITY=""

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

function run_codesign_verify() {
    local path="$1"
    echo "Verifying code signature: $path"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$path"
}

MARKETING_VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
APP_NAME="PiBar"
DEVELOPMENT_TEAM="$(read_project_setting DEVELOPMENT_TEAM)"

if [[ -n "$SIGN_IDENTITY" ]]; then
    CODE_SIGNING_ALLOWED="YES"
fi

if [[ -z "$ARTIFACT_NAME" ]]; then
    ARTIFACT_NAME="${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-macOS"
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/${APP_NAME}.app"
ZIP_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.zip"

mkdir -p "$OUTPUT_DIR"

echo "Building ${APP_NAME}.app..."
xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -sdk macosx
    -derivedDataPath "$DERIVED_DATA_PATH"
    "CODE_SIGNING_ALLOWED=${CODE_SIGNING_ALLOWED}"
)

if [[ -n "$SIGN_IDENTITY" ]]; then
    xcodebuild_args+=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
        "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}"
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )
fi

xcodebuild "${xcodebuild_args[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build succeeded but ${APP_PATH} was not found." >&2
    exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    run_codesign_verify "$APP_PATH"
else
    echo "Applying ad hoc signature to ${APP_NAME}.app..."
    /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_PATH"
    run_codesign_verify "$APP_PATH"
fi

echo "Creating ${ZIP_PATH}..."
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "ZIP created: $ZIP_PATH"
