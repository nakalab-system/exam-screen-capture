#!/bin/sh

STATUS_BAR_PID_FILE="/tmp/CaptureSystem_status_bar.pid"
STATUS_FILE="/tmp/CaptureSystem_status.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_SCRIPT="$SCRIPT_DIR/status_bar.swift"

cleanup() {
    if [ -n "$SWIFT_PID" ]; then
        kill "$SWIFT_PID" 2>/dev/null
    fi
    rm -f "$STATUS_BAR_PID_FILE"
}

trap cleanup EXIT TERM INT

echo $$ > "$STATUS_BAR_PID_FILE"
swift "$SWIFT_SCRIPT" "$STATUS_FILE" &
SWIFT_PID=$!
wait "$SWIFT_PID"
