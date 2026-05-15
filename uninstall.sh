#!/usr/bin/env bash
# Uninstall Parents Hand from this Mac.
#
# Removes: the launchd job, the .app, the LaunchAgent plist, and the
# pkgutil receipt — leaving the Mac in the same state as if the .pkg had
# never been installed (with two exceptions: the FDA entry in System
# Settings and the per-user log files, both of which the script tells you
# how to clean up at the end).
#
# Logs are preserved by default. Pass --purge-logs to remove those too.

set -uo pipefail

BUNDLE_ID="io.github.androidkc.parentshand"
APP_NAME="Parents Hand"
PLIST_PATH="/Library/LaunchAgents/${BUNDLE_ID}.plist"
APP_PATH="/Applications/${APP_NAME}.app"
LOG_DIR="$HOME/Library/Logs/parentshand"

PURGE_LOGS=0
if [[ "${1:-}" == "--purge-logs" ]]; then
    PURGE_LOGS=1
fi

echo "==> unloading launchd job (no sudo needed)"
launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" 2>/dev/null || true

echo "==> removing system files (admin password required)"
sudo rm -f "$PLIST_PATH"
sudo rm -rf "$APP_PATH"

echo "==> forgetting pkgutil receipt"
sudo pkgutil --forget "$BUNDLE_ID" 2>/dev/null || true

if (( PURGE_LOGS == 1 )); then
    echo "==> removing logs"
    rm -rf "$LOG_DIR"
else
    echo "    logs preserved at: $LOG_DIR"
    echo "    (pass --purge-logs to also delete them)"
fi

echo
echo "==> verifying clean state"
ok=1
fail() { printf "    ✗ %s — %s\n" "$1" "$2"; ok=0; }
pass() { printf "    ✓ %s\n"      "$1"; }

# .app should be gone
[[ ! -e "$APP_PATH" ]] \
    && pass "no .app in /Applications" \
    || fail "no .app in /Applications" "still present at $APP_PATH"

# Plist should be gone
[[ ! -e "$PLIST_PATH" ]] \
    && pass "no LaunchAgent plist" \
    || fail "no LaunchAgent plist" "still present at $PLIST_PATH"

# pkgutil should not know about the receipt
if pkgutil --pkg-info "$BUNDLE_ID" >/dev/null 2>&1; then
    fail "no pkgutil receipt" "receipt still registered (run: sudo pkgutil --forget $BUNDLE_ID)"
else
    pass "no pkgutil receipt"
fi

# launchd should have no job loaded
if launchctl list | grep -q "$BUNDLE_ID"; then
    fail "no launchd job loaded" "still listed in launchctl"
else
    pass "no launchd job loaded"
fi

cat <<EOF

Uninstalled.

REMAINING MANUAL STEPS — macOS does not let scripts touch these:
  1. System Settings → Privacy & Security → Full Disk Access
     Select '${APP_NAME}', click "−"
  2. (If you toggled it on for testing) System Settings → Screen Time →
     Content & Privacy Restrictions → Deleting Apps → set back to Allow

OPTIONAL — a stale Background Task Management record may linger:
  System Settings → General → Login Items & Extensions
  If '${APP_NAME}' still appears, toggle it off. It's harmless either
  way (the plist it referenced is gone), but cosmetically nicer to clear.
EOF

exit $(( 1 - ok ))
