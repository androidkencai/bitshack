#!/usr/bin/env bash
# Uninstall Parents Hand from this Mac.
#
# Removes: the LaunchDaemon job, the .app, the LaunchDaemon plist,
# the /var/log/parentshand and /var/db/parentshand directories, and the
# pkgutil receipt — leaving the Mac in the same state as if the .pkg had
# never been installed. The FDA entry in System Settings is the one thing
# the script can't touch; instructions at the end.
#
# Logs and state are preserved by default. Pass --purge-logs to wipe those.

set -uo pipefail

BUNDLE_ID="io.github.androidkc.parentshand"
APP_NAME="Parents Hand"
PLIST_PATH="/Library/LaunchDaemons/${BUNDLE_ID}.plist"
LEGACY_AGENT_PLIST="/Library/LaunchAgents/${BUNDLE_ID}.plist"   # pre-ADR-0010
APP_PATH="/Applications/${APP_NAME}.app"
LOG_DIR="/var/log/parentshand"
STATE_DIR="/var/db/parentshand"

PURGE_LOGS=0
if [[ "${1:-}" == "--purge-logs" ]]; then
    PURGE_LOGS=1
fi

echo "==> unloading launchd jobs (admin password required)"
sudo launchctl bootout "system/${BUNDLE_ID}" 2>/dev/null || true
# Also clean up any legacy LaunchAgent from pre-ADR-0010 installs.
CONSOLE_USER=$(stat -f%Su /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")
if [[ -n "$CONSOLE_UID" ]]; then
    sudo launchctl bootout "gui/${CONSOLE_UID}/${BUNDLE_ID}" 2>/dev/null || true
fi

echo "==> removing system files"
sudo rm -f "$PLIST_PATH"
sudo rm -f "$LEGACY_AGENT_PLIST"
sudo rm -rf "$APP_PATH"

echo "==> forgetting pkgutil receipt"
sudo pkgutil --forget "$BUNDLE_ID" 2>/dev/null || true

if (( PURGE_LOGS == 1 )); then
    echo "==> removing logs and state"
    sudo rm -rf "$LOG_DIR" "$STATE_DIR"
else
    echo "    logs preserved at:  $LOG_DIR"
    echo "    state preserved at: $STATE_DIR"
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

# Plist should be gone (both new and legacy locations)
[[ ! -e "$PLIST_PATH" ]] \
    && pass "no LaunchDaemon plist" \
    || fail "no LaunchDaemon plist" "still present at $PLIST_PATH"
[[ ! -e "$LEGACY_AGENT_PLIST" ]] \
    && pass "no legacy LaunchAgent plist" \
    || fail "no legacy LaunchAgent plist" "still present at $LEGACY_AGENT_PLIST"

# pkgutil should not know about the receipt
if pkgutil --pkg-info "$BUNDLE_ID" >/dev/null 2>&1; then
    fail "no pkgutil receipt" "receipt still registered (run: sudo pkgutil --forget $BUNDLE_ID)"
else
    pass "no pkgutil receipt"
fi

# launchd should have no job loaded
if sudo launchctl print "system/${BUNDLE_ID}" >/dev/null 2>&1; then
    fail "no launchd job loaded" "still loaded in system domain"
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
