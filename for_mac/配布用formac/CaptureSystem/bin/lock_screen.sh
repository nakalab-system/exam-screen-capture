#!/bin/sh

# =================================================================
# ネット接続検知時のロックスクリーン (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
LOCK_SCREEN_PID_FILE="/tmp/CaptureSystem_lock_screen.pid"
HASH_FILE="$ROOT_DIR/.ta_guard"
STATUS_FILE="/tmp/CaptureSystem_status.json"
SWIFT_SCRIPT="$ROOT_DIR/bin/lock_screen.swift"
DEFAULT_HASH_PART1="9af15b336e6a9619928537df30b2e6a23"
DEFAULT_HASH_PART2="76569fcf9d7e773eccede65606529a0"

if [ ! -f "$SAVE_DIR_FILE" ]; then
    exit 1
fi

SAVE_DIR=$(cat "$SAVE_DIR_FILE")
LOCK_FLAG="$SAVE_DIR/LOCK_ACTIVE.flag"
UNLOCK_LOG="$SAVE_DIR/network_warning.log"

if [ ! -d "$SAVE_DIR" ] || [ ! -f "$LOCK_FLAG" ]; then
    exit 0
fi

cleanup() {
    if [ -n "$SWIFT_PID" ]; then
        kill "$SWIFT_PID" 2>/dev/null
    fi
    rm -f "$LOCK_SCREEN_PID_FILE"
}

trap cleanup EXIT TERM INT
echo $$ > "$LOCK_SCREEN_PID_FILE"

EXPECTED_HASH="${DEFAULT_HASH_PART1}${DEFAULT_HASH_PART2}"
if [ -f "$HASH_FILE" ]; then
    FILE_HASH=$(tr -d '\r\n[:space:]' < "$HASH_FILE")
    if [ -n "$FILE_HASH" ]; then
        EXPECTED_HASH="$FILE_HASH"
    fi
fi

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

while [ -f "$LOCK_FLAG" ]; do
    if command -v swift >/dev/null 2>&1; then
        swift "$SWIFT_SCRIPT" "$EXPECTED_HASH" "$LOCK_FLAG" &
        SWIFT_PID=$!
        wait "$SWIFT_PID"
        RESULT=$?
        SWIFT_PID=""
    else
        INPUT_PASSWORD=$(osascript -e 'text returned of (display dialog "【警告】インターネット接続を検知しました。\n\nただちにTA（試験監督）を呼んでください。\nWi-Fiをオフにし、TA用パスワードが入力されるまでPCを操作しないでください。\n\n※ このMacでは簡易ロック画面で動作中です。" default answer "" with hidden answer buttons {"解除を実行"} default button "解除を実行" with icon stop)' 2>/dev/null)

        if test_internet_connectivity; then
            osascript -e 'display dialog "【解除不可】\nWi-Fiをオフにしてから解除してください。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
            RESULT=1
        else
            INPUT_HASH=$(printf '%s' "$INPUT_PASSWORD" | shasum -a 256 | awk '{print $1}')
            if [ "$INPUT_HASH" = "$EXPECTED_HASH" ]; then
                RESULT=0
            else
                osascript -e 'display dialog "TA用パスワードが正しくありません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
                RESULT=1
            fi
        fi
    fi

    if [ "$RESULT" -eq 0 ] && [ -f "$LOCK_FLAG" ]; then
        rm -f "$LOCK_FLAG"
        printf '[%s] ロック解除\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$UNLOCK_LOG"
        if [ -f "$STATUS_FILE" ]; then
            CURRENT_COUNT=$(awk -F'"capture_count":' '{print $2}' "$STATUS_FILE" | awk -F',' 'NR==1 {gsub(/[^0-9]/, "", $1); print $1}')
            CURRENT_ID=$(awk -F'"student_id":"' '{print $2}' "$STATUS_FILE" | awk -F'"' 'NR==1 {print $1}')
            printf '{"student_id":"%s","capture_count":%s,"current_time":"%s","mode":"normal"}\n' \
              "$CURRENT_ID" \
              "${CURRENT_COUNT:-0}" \
              "$(date +%H:%M)" > "$STATUS_FILE"
        fi
        break
    fi

    if [ ! -f "$LOCK_FLAG" ]; then
        break
    fi
done
