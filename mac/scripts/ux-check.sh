#!/bin/bash
# UX pre-commit checks for PiGuard

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

echo "Running UX checks..."

# Only check project source files — exclude build artefacts and Swift packages
find_sources() {
    find "$ROOT_DIR" \
        -not -path "*/build/*" \
        -not -path "*/DerivedData/*" \
        -not -path "*/.git/*" \
        -not -path "*/SourcePackages/*" \
        "$@"
}

# 1. Storyboard/XIB XML validity (source files only, skip binary XIBs)
while IFS= read -r -d '' sb; do
    # Only validate XML-format files (skip compiled binary XIBs)
    if file "$sb" | grep -q "XML"; then
        if ! xmllint --noout "$sb" > /dev/null 2>&1; then
            red "FAIL: Malformed XML in storyboard/xib: $sb"
            FAILED=1
        fi
    fi
done < <(find_sources \( -name "*.storyboard" -o -name "*.xib" \) -print0 2>/dev/null)

# 2. Placeholder text left in storyboards
if find_sources -name "*.storyboard" -print0 2>/dev/null \
        | xargs -0 grep -lq "Lorem ipsum" 2>/dev/null; then
    yellow "WARN: Placeholder 'Lorem ipsum' text found in storyboard files"
fi

# 3. Hardcoded non-system color literals in Swift source
HARDCODED=$(find_sources -path "*/PiGuard*" -name "*.swift" -print0 2>/dev/null \
    | xargs -0 grep -n "NSColor(red:\|Color(red:" 2>/dev/null || true)
if [[ -n "$HARDCODED" ]]; then
    yellow "WARN: Hardcoded color literals found (prefer semantic/named colors):"
    echo "$HARDCODED" | head -5
fi

if [[ $FAILED -eq 1 ]]; then
    red "UX checks failed."
    exit 1
fi

green "UX checks passed."
exit 0
