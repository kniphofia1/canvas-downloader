#!/bin/sh

# Install the NAS cron schedule for Fudan Canvas sync.
# Usage:
#   sh install-nas-cron.sh
#   sh install-nas-cron.sh /custom/project/path

set -eu

PROJECT_DIR="${1:-${FUDAN_CANVAS_PROJECT_DIR:-/vol1/1000/Docker/Fudan_canvasdownloader}}"
SCRIPT_PATH="$PROJECT_DIR/run-nas-cron-sync.sh"
MARKER_BEGIN="# BEGIN fudan-canvasdownloader scheduled sync"
MARKER_END="# END fudan-canvasdownloader scheduled sync"
CRON_JOB="0 7,19 * * * FUDAN_CANVAS_PROJECT_DIR='$PROJECT_DIR' sh '$SCRIPT_PATH'"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "ERROR: cron sync script not found: $SCRIPT_PATH" >&2
    exit 1
fi

tmp_current="$(mktemp)"
tmp_next="$(mktemp)"

cleanup() {
    rm -f "$tmp_current" "$tmp_next"
}
trap cleanup EXIT

crontab -l >"$tmp_current" 2>/dev/null || true

awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
' "$tmp_current" >"$tmp_next"

{
    cat "$tmp_next"
    echo "$MARKER_BEGIN"
    echo "$CRON_JOB"
    echo "$MARKER_END"
} | crontab -

echo "Installed Fudan Canvas cron schedule:"
crontab -l | awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin { show = 1 }
    show == 1 { print }
    $0 == end { show = 0 }
'
