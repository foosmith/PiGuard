#!/bin/bash
# Security pre-commit checks for PiGuard

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

echo "Running security checks..."

# 1. No hardcoded secrets / API keys / tokens in staged files
SECRET_PATTERNS='(password|secret|api[_-]?key|auth[_-]?token|private[_-]?key)\s*=\s*"[^"]{8,}'
if git diff --cached -U0 | grep -iEq "$SECRET_PATTERNS"; then
    red "FAIL: Possible hardcoded secret detected in staged changes."
    git diff --cached -U0 | grep -iE "$SECRET_PATTERNS" | head -5
    FAILED=1
fi

# 2. No .env files staged
if git diff --cached --name-only | grep -qE '\.env($|\.)'; then
    red "FAIL: .env file is staged — do not commit secrets."
    FAILED=1
fi

# 3. No private keys staged
if git diff --cached --name-only | grep -qE '\.(pem|p12|key|cer|mobileprovision)$'; then
    red "FAIL: Certificate/key file staged — do not commit signing material."
    FAILED=1
fi

# 4. Warn on kSecAttrAccessible usage weaker than AfterFirstUnlock
WEAK_KEYCHAIN=$(grep -rn "kSecAttrAccessibleAlways\b\|kSecAttrAccessibleWhenUnlockedThisDeviceOnly" \
    "$ROOT_DIR"/PiGuard/**/*.swift \
    "$ROOT_DIR"/Shared/**/*.swift 2>/dev/null || true)
if [[ -n "$WEAK_KEYCHAIN" ]]; then
    yellow "WARN: Keychain accessibility may be too permissive:"
    echo "$WEAK_KEYCHAIN" | head -5
fi

# 5. No force-disabled App Transport Security
if grep -rq "NSAllowsArbitraryLoads.*true\|NSExceptionAllowsInsecureHTTPLoads.*true" \
    "$ROOT_DIR"/**/*.plist 2>/dev/null; then
    red "FAIL: App Transport Security exception allowing insecure HTTP found."
    FAILED=1
fi

if [[ $FAILED -eq 1 ]]; then
    red "Security checks failed."
    exit 1
fi

green "Security checks passed."
exit 0
