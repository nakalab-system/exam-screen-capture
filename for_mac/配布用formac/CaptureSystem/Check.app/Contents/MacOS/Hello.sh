#!/bin/sh

# =================================================================
# 状況確認スクリプト (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/../../.. && pwd)"
FREE_DIR="/tmp/CaptureSystemLogs"
PID_FILE="/tmp/CaptureSystem_capture.pid"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
STATUS_FILE="/tmp/CaptureSystem_status.json"

# プロセス稼働チェック
RUNNING=false
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>&1)
    if ps -p "$PID" > /dev/null 2>&1; then
        RUNNING=true
    fi
fi

if [ "$RUNNING" = true ]; then
    STUDENT_ID=""
    CAPTURE_COUNT=""
    CURRENT_TIME=""

    if [ -f "$STATUS_FILE" ]; then
        STUDENT_ID=$(awk -F'"student_id":"' '{print $2}' "$STATUS_FILE" | awk -F'"' 'NR==1 {print $1}')
        CAPTURE_COUNT=$(awk -F'"capture_count":' '{print $2}' "$STATUS_FILE" | awk -F',' 'NR==1 {gsub(/[^0-9]/, "", $1); print $1}')
        CURRENT_TIME=$(awk -F'"current_time":"' '{print $2}' "$STATUS_FILE" | awk -F'"' 'NR==1 {print $1}')
    fi

    if [ -z "$STUDENT_ID" ] || [ -z "$CAPTURE_COUNT" ]; then
        if [ -f "$SAVE_DIR_FILE" ]; then
            SAVE_DIR=$(cat "$SAVE_DIR_FILE" 2>/dev/null)
            ID_FILE="$SAVE_DIR/student_id.txt"
            if [ -f "$ID_FILE" ]; then
                STUDENT_ID=$(tr -d '[:space:]' < "$ID_FILE")
            fi
            if [ -d "$SAVE_DIR" ] && [ -n "$STUDENT_ID" ]; then
                CAPTURE_COUNT=$(find "$SAVE_DIR" -maxdepth 1 -type f -name "${STUDENT_ID}_*.jpg" | wc -l | tr -d '[:space:]')
            fi
        fi
    fi

    if [ -z "$CURRENT_TIME" ]; then
        CURRENT_TIME=$(date "+%H:%M")
    fi

    if [ -z "$STUDENT_ID" ]; then
        STUDENT_ID="不明"
    fi

    if [ -z "$CAPTURE_COUNT" ]; then
        CAPTURE_COUNT="0"
    fi

    MSG="【正常に稼働中】\n学籍番号: $STUDENT_ID\n枚数: ${CAPTURE_COUNT}枚\n時刻: $CURRENT_TIME"
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note"
else
    osascript -e 'display dialog "【停止中】\nツールは動いていません。" buttons {"OK"} default button "OK" with icon caution'
fi
