#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS=0
WARNINGS=0

pass() {
  echo "PASS: $*"
}

warn() {
  echo "WARN: $*"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo "FAIL: $*"
  ERRORS=$((ERRORS + 1))
}

check_command() {
  local cmd="$1"
  local guidance="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "'$cmd' is installed"
  else
    fail "'$cmd' is missing. $guidance"
  fi
}

echo "Running environment checks for GH Status Toggle..."

if [[ ! -f "$ROOT_DIR/Sources/main.swift" ]]; then
  fail "Expected source file missing: $ROOT_DIR/Sources/main.swift"
else
  pass "Project files are present"
fi

check_command "xcrun" "Install Xcode Command Line Tools: xcode-select --install"
check_command "gh" "Install GitHub CLI (Homebrew): brew install gh"
check_command "sw_vers" "This script is intended for macOS"

if command -v sw_vers >/dev/null 2>&1; then
  MACOS_VERSION="$(sw_vers -productVersion)"
  MACOS_MAJOR="${MACOS_VERSION%%.*}"
  if [[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] && (( MACOS_MAJOR >= 13 )); then
    pass "macOS version $MACOS_VERSION is supported"
  else
    fail "macOS version $MACOS_VERSION is not supported (requires 13+)"
  fi
fi

if command -v xcrun >/dev/null 2>&1; then
  if SWIFTC_PATH="$(xcrun --find swiftc 2>/dev/null)"; then
    pass "swiftc found at $SWIFTC_PATH"
  else
    fail "swiftc not found via xcrun"
  fi
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    pass "GitHub CLI auth is configured for github.com"
  else
    warn "GitHub CLI auth is not ready. Run: gh auth login -h github.com"
  fi
fi

echo
if (( ERRORS > 0 )); then
  echo "Doctor completed with $ERRORS error(s) and $WARNINGS warning(s)."
  exit 1
fi

echo "Doctor completed with $WARNINGS warning(s)."
exit 0
