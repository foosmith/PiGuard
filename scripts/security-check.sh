#!/usr/bin/env bash
set -euo pipefail

git diff --cached --check
git diff --cached --name-only | grep -E '\.(py|js|ts|tsx|jsx|go|rs|java|rb|php|sh)$' >/dev/null || exit 0

if command -v detect-secrets >/dev/null 2>&1; then
  detect-secrets scan --baseline .secrets.baseline
fi

if command -v trufflehog >/dev/null 2>&1; then
  trufflehog git file://. --only-verified
fi

if command -v semgrep >/dev/null 2>&1; then
  semgrep --config auto --error --quiet
fi
