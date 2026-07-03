#!/bin/sh

# =================================================================
# 試験中ネットワーク監視スクリプト (macOS版)
# =================================================================

SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
MONITOR_PID_FILE="/tmp/CaptureSystem_network_monitor.pid"

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
            osascript -e 'display dialog "【警告】インターネット接続を検知しました。\n\nただちにTA（試験監督）を呼んでください。\nWi-Fiをオフにし、指示があるまでPCを操作しないでください。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
            was_connected=1
        fi
    else
        was_connected=0
    fi

    SLEEP_TIME=$(jot -r 1 1 10)
    sleep "$SLEEP_TIME"
done
