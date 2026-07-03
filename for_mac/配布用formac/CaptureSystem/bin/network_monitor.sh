#!/bin/sh

# =================================================================
# 試験中ネットワーク監視スクリプト (macOS版)
# =================================================================

SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
MONITOR_PID_FILE="/tmp/CaptureSystem_network_monitor.pid"
LOCK_SCREEN_PID_FILE="/tmp/CaptureSystem_lock_screen.pid"
ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
LOCK_SCREEN_SCRIPT="$ROOT_DIR/bin/lock_screen.sh"
STATUS_FILE="/tmp/CaptureSystem_status.json"

test_internet_connectivity() {
    ok_ping=0
    ok_dns=0
    ok_http=0

    if ping -c 1 -W 1000 8.8.8.8 >/dev/null 2>&1; then
        ok_ping=1
    fi

    if dscacheutil -q host -a name www.google.com >/dev/null 2>&1; then
        ok_dns=1
    fi

    if curl -s -o /dev/null --max-time 3 http://clients3.google.com/generate_204; then
        ok_http=1
    fi

    score=$((ok_ping + ok_dns + ok_http))
    [ "$score" -ge 2 ]
}

if [ ! -f "$SAVE_DIR_FILE" ]; then
    exit 1
fi

SAVE_DIR=$(cat "$SAVE_DIR_FILE")
if [ ! -d "$SAVE_DIR" ]; then
    exit 1
fi

LOG_FILE="$SAVE_DIR/network_warning.log"
LOCK_FLAG="$SAVE_DIR/LOCK_ACTIVE.flag"
trap 'rm -f "$MONITOR_PID_FILE"' EXIT
echo $$ > "$MONITOR_PID_FILE"

was_connected=0

while true; do
    if [ ! -d "$SAVE_DIR" ]; then
        break
    fi

    if test_internet_connectivity; then
        if [ "$was_connected" -eq 0 ]; then
            printf '[%s] インターネット接続を検知\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
            printf '[%s] ロック有効化\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK_FLAG"
            if [ -f "$STATUS_FILE" ]; then
                CURRENT_COUNT=$(awk -F'"capture_count":' '{print $2}' "$STATUS_FILE" | awk -F',' 'NR==1 {gsub(/[^0-9]/, "", $1); print $1}')
                CURRENT_ID=$(awk -F'"student_id":"' '{print $2}' "$STATUS_FILE" | awk -F'"' 'NR==1 {print $1}')
                printf '{"student_id":"%s","capture_count":%s,"current_time":"%s","mode":"warning"}\n' \
                  "$CURRENT_ID" \
                  "${CURRENT_COUNT:-0}" \
                  "$(date +%H:%M)" > "$STATUS_FILE"
            fi
            if [ -f "$LOCK_SCREEN_PID_FILE" ]; then
                LOCK_PID=$(cat "$LOCK_SCREEN_PID_FILE")
            else
                LOCK_PID=""
            fi
            if [ -z "$LOCK_PID" ] || ! ps -p "$LOCK_PID" > /dev/null 2>&1; then
                nohup sh "$LOCK_SCREEN_SCRIPT" > /dev/null 2>&1 &
            fi
            was_connected=1
        fi
    else
        was_connected=0
    fi

    SLEEP_TIME=$(jot -r 1 1 10)
    sleep "$SLEEP_TIME"
done
