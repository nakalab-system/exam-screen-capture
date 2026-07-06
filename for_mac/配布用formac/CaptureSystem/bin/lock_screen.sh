#!/bin/sh

# =================================================================
# ネット接続検知時のロックスクリーン (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
LOCK_SCREEN_PID_FILE="/tmp/CaptureSystem_lock_screen.pid"
POLICY_FILE="$ROOT_DIR/.ta_unlock_policy"
STATUS_FILE="/tmp/CaptureSystem_status.json"
SWIFT_SCRIPT="$ROOT_DIR/bin/lock_screen.swift"

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

read_key_value() {
    file_path="$1"
    key_name="$2"

    awk -F'=' -v key_name="$key_name" '$1 == key_name {print substr($0, index($0, "=") + 1); exit}' "$file_path" 2>/dev/null | tr -d '\r'
}

CHALLENGE_ID=""
REQUIRED_KEY_FILENAME=""
KEY_HASH=""

if [ -f "$POLICY_FILE" ]; then
    CHALLENGE_ID=$(read_key_value "$POLICY_FILE" "challenge_id")
    REQUIRED_KEY_FILENAME=$(read_key_value "$POLICY_FILE" "required_key_filename")
    KEY_HASH=$(read_key_value "$POLICY_FILE" "key_hash")
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

find_usb_key_file() {
    required_filename="$1"
    expected_challenge="$2"

    for volume_dir in /Volumes/*; do
        [ -d "$volume_dir" ] || continue
        candidate_file="$volume_dir/$required_filename"
        [ -f "$candidate_file" ] || continue

        candidate_challenge=$(read_key_value "$candidate_file" "challenge_id")
        if [ -n "$expected_challenge" ] && [ "$candidate_challenge" != "$expected_challenge" ]; then
            continue
        fi

        echo "$candidate_file"
        return 0
    done

    return 1
}

validate_usb_key_file() {
    key_file="$1"
    expected_challenge="$2"
    expected_key_hash="$3"

    file_challenge=$(read_key_value "$key_file" "challenge_id")
    unlock_key=$(read_key_value "$key_file" "unlock_key")

    if [ -z "$file_challenge" ] || [ -z "$unlock_key" ]; then
        return 1
    fi

    if [ "$file_challenge" != "$expected_challenge" ]; then
        return 1
    fi

    computed_key_hash=$(printf '%s' "$unlock_key" | shasum -a 256 | awk '{print $1}')
    [ "$computed_key_hash" = "$expected_key_hash" ]
}

read_usb_pin_hash() {
    key_file="$1"
    read_key_value "$key_file" "pin_hash"
}

while [ -f "$LOCK_FLAG" ]; do
    if [ -z "$CHALLENGE_ID" ] || [ -z "$REQUIRED_KEY_FILENAME" ] || [ -z "$KEY_HASH" ]; then
        osascript -e 'display dialog "【解除不可】\nUSB解除設定が見つかりません。\n\n`.ta_unlock_policy` を確認してください。\n緊急時は TA が `LOCK_ACTIVE.flag` を削除して復旧してください。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
        sleep 2
        continue
    fi

    if command -v swift >/dev/null 2>&1; then
        swift "$SWIFT_SCRIPT" "$POLICY_FILE" "$LOCK_FLAG" &
        SWIFT_PID=$!
        wait "$SWIFT_PID"
        RESULT=$?
        SWIFT_PID=""
    else
        INPUT_PASSWORD=$(osascript -e 'text returned of (display dialog "【警告】インターネット接続を検知しました。\n\nただちにTA（試験監督）を呼んでください。\nWi-Fiをオフにし、TA用USBを接続したうえで、TA用PINを入力してください。\n\n※ このMacでは簡易ロック画面で動作中です。" default answer "" with hidden answer buttons {"解除を実行"} default button "解除を実行" with icon stop)' 2>/dev/null)

        if test_internet_connectivity; then
            osascript -e 'display dialog "【解除不可】\nWi-Fiをオフにしてから解除してください。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
            RESULT=1
        else
            KEY_FILE=$(find_usb_key_file "$REQUIRED_KEY_FILENAME" "$CHALLENGE_ID")

            if [ -z "$KEY_FILE" ]; then
                osascript -e 'display dialog "【解除不可】\nTA用USBまたは鍵ファイルが見つかりません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
                RESULT=1
            elif ! validate_usb_key_file "$KEY_FILE" "$CHALLENGE_ID" "$KEY_HASH"; then
                osascript -e 'display dialog "【解除不可】\nTA用USBの鍵が一致しません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
                RESULT=1
            else
                USB_PIN_HASH=$(read_usb_pin_hash "$KEY_FILE")
                if [ -z "$USB_PIN_HASH" ]; then
                    osascript -e 'display dialog "【解除不可】\nTA用USB内の PIN 設定が見つかりません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
                    RESULT=1
                    continue
                fi

                INPUT_HASH=$(printf '%s' "$INPUT_PASSWORD" | shasum -a 256 | awk '{print $1}')
                if [ "$INPUT_HASH" = "$USB_PIN_HASH" ]; then
                    RESULT=0
                else
                    osascript -e 'display dialog "TA用PINが正しくありません。" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
                    RESULT=1
                fi
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
