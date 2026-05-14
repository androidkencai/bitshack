#!/usr/bin/env bash
# Uninstall Safari History Agent from this Mac.
#
# Removes: the launchd job, the .app, the LaunchAgent plist, and the
# pkgutil receipt — leaving the Mac in the same state as if the .pkg had
# never been installed (with two exceptions: the FDA entry in System
# Settings and the per-user log files, both of which the script tells you
# how to clean up at the end).
#
# Logs are preserved by default. Pass --purge-logs to remove those too.

set -uo pipefail

BUNDLE_ID="io.github.androidkc.safari-history-poc"
APP_NAME="Safari History Agent"
PLIST_PATH="/Library/LaunchAgents/${BUNDLE_ID}.plist"
APP_PATH="/Applications/${APP_NAME}.app"
LOG_DIR="$HOME/Library/Logs/safari-history-agent"

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
check() {
    local label="$1" cmd="$2" expected="$3"
    local got
    got="$(eval "$cmd" 2>&1)"
    if [[ "$got" == "$expected" ]]; then
        printf "    ✓ %s\n" "$label"
    else
        printf "    ✗ %s — got: %s\n" "$label" "$got"
        ok=0
    fi
}
check "no .app in /Applications"           "ls -d '$APP_PATH' 2>&1 || echo absent" "absent"
check "no LaunchAgent plist"               "ls '$PLIST_PATH' 2>&1 || echo absent" "absent"
check "no pkgutil receipt"                 "pkgutil --pkg-info '$BUNDLE_ID' 2>&1 | head -1 || echo absent" "No receipt for '$BUNDLE_ID' found at '/'."
check "no launchd job loaded"              "launchctl list | grep -c '$BUNDLE_ID' || true" "0"

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
