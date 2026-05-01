#!/bin/bash

# =================================================================
# 状況確認スクリプト (macOS版)
# =================================================================

SAVE_DIR="$HOME/Library/Application Support/CaptureSystem"
PID_FILE="$SAVE_DIR/capture.pid"

# プロセス稼働チェック
RUNNING=false
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        RUNNING=true
    fi
fi

if [ "$RUNNING" = true ]; then
    # 最新の画像ファイルを取得
    LATEST_FILE=$(ls -t "$SAVE_DIR"/img_*.jpg 2>/dev/null | head -n 1)
    
    if [ -n "$LATEST_FILE" ]; then
        # 最終撮影時刻を取得 (HH時mm分ss秒)
        LAST_TIME=$(date -r "$LATEST_FILE" "+%H時%M分%S秒")
        MSG="【正常に稼働中】\n最終撮影: $LAST_TIME"
    else
        MSG="【正常に稼働中】\n（まだ画像は保存されていません）"
    fi
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note"
else
    osascript -e 'display dialog "【停止中】\nツールは動いていません。" buttons {"OK"} default button "OK" with icon caution'
fi
