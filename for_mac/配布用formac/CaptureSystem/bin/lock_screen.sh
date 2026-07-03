#!/bin/sh

# =================================================================
# ネット接続検知時のロックスクリーン (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
LOCK_SCREEN_PID_FILE="/tmp/CaptureSystem_lock_screen.pid"
HASH_FILE="$ROOT_DIR/.ta_guard"
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

trap 'rm -f "$LOCK_SCREEN_PID_FILE"' EXIT
echo $$ > "$LOCK_SCREEN_PID_FILE"

EXPECTED_HASH="${DEFAULT_HASH_PART1}${DEFAULT_HASH_PART2}"
if [ -f "$HASH_FILE" ]; then
    FILE_HASH=$(tr -d '\r\n[:space:]' < "$HASH_FILE")
    if [ -n "$FILE_HASH" ]; then
        EXPECTED_HASH="$FILE_HASH"
    fi
fi

while [ -f "$LOCK_FLAG" ]; do
    INPUT_PASSWORD=$(osascript -e 'text returned of (display dialog "【警告】インターネット接続を検知しました。\n\nただちにTA（試験監督）を呼んでください。\nWi-Fiをオフにし、TA用パスワードが入力されるまでPCを操作しないでください。" default answer "" with hidden answer buttons {"解除を実行"} default button "解除を実行" with icon stop)' 2>/dev/null)
    INPUT_HASH=$(printf '%s' "$INPUT_PASSWORD" | shasum -a 256 | awk '{print $1}')

    if [ "$INPUT_HASH" = "$EXPECTED_HASH" ]; then
        rm -f "$LOCK_FLAG"
        printf '[%s] ロック解除\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$UNLOCK_LOG"
        osascript -e 'display dialog "ロックを解除しました。" buttons {"OK"} default button "OK" with icon note' >/dev/null 2>&1
        break
    fi

    osascript -e 'display dialog "TA用パスワードが正しくありません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
done
