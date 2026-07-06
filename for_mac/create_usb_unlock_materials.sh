#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/配布用formac/CaptureSystem"
POLICY_FILE="$TARGET_DIR/.ta_unlock_policy"

usage() {
    cat <<'EOF'
使い方:
  sh for_mac/create_usb_unlock_materials.sh <USBマウント先> <challenge_id> <TA_PIN>

例:
  sh for_mac/create_usb_unlock_materials.sh /Volumes/TA_USB 2026-final-01 123456

このスクリプトは次を生成します:
  - CaptureSystem/.ta_unlock_policy
  - <USBマウント先>/ta_unlock.key
EOF
}

if [ "$#" -ne 3 ]; then
    usage
    exit 1
fi

USB_MOUNT="$1"
CHALLENGE_ID="$2"
TA_PIN="$3"
KEY_FILE="$USB_MOUNT/ta_unlock.key"

if [ ! -d "$USB_MOUNT" ]; then
    echo "USBマウント先が見つかりません: $USB_MOUNT" >&2
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "CaptureSystem が見つかりません: $TARGET_DIR" >&2
    exit 1
fi

UNLOCK_KEY="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | awk 'BEGIN {ORS=""} {print substr($0, 1, 40); exit}')"

if [ -z "$UNLOCK_KEY" ]; then
    echo "unlock_key の生成に失敗しました。" >&2
    exit 1
fi

KEY_HASH="$(printf '%s' "$UNLOCK_KEY" | shasum -a 256 | awk '{print $1}')"
PIN_HASH="$(printf '%s' "$TA_PIN" | shasum -a 256 | awk '{print $1}')"

cat > "$POLICY_FILE" <<EOF
challenge_id=$CHALLENGE_ID
required_key_filename=ta_unlock.key
key_hash=$KEY_HASH
EOF

cat > "$KEY_FILE" <<EOF
challenge_id=$CHALLENGE_ID
unlock_key=$UNLOCK_KEY
pin_hash=$PIN_HASH
EOF

echo "生成完了:"
echo "  ポリシー: $POLICY_FILE"
echo "  USB鍵:    $KEY_FILE"
echo
echo "次の手順:"
echo "  1. CaptureSystem を配布用に ZIP 化する"
echo "  2. USB は TA 管理下で保管する"
echo "  3. TA PIN は別経路で共有する"
