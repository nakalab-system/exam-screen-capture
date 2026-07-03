#!/bin/sh

# =================================================================
# 試験画面キャプチャツール (macOS版) - コアプロセス
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
FREE_DIR="/tmp/CaptureSystemLogs"
PID_FILE="/tmp/CaptureSystem_capture.pid"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"

if [ ! -f "$SAVE_DIR_FILE" ]; then
    exit 1
fi

SAVE_DIR=$(cat "$SAVE_DIR_FILE")
ID_FILE="$SAVE_DIR/student_id.txt"

if [ ! -d "$SAVE_DIR" ] || [ ! -f "$ID_FILE" ]; then
    exit 1
fi

STUDENT_ID=$(tr -d '[:space:]' < "$ID_FILE")
CAPTURE_COUNT=$(find "$SAVE_DIR" -maxdepth 1 -type f -name "${STUDENT_ID}_*.jpg" | wc -l | tr -d '[:space:]')

mkdir -p "$SAVE_DIR"
mkdir -p "$FREE_DIR"
echo $$ > "$PID_FILE"

# メインループ
while true; do
    TIMESTAMP=$(date +%H%M%S)
    CAPTURE_COUNT=$((CAPTURE_COUNT + 1))
    COUNT_STR=$(printf "%03d" "$CAPTURE_COUNT")
    FILE_NAME="${STUDENT_ID}_${COUNT_STR}_${TIMESTAMP}.jpg"
    FILE_PATH="$SAVE_DIR/$FILE_NAME"
    FREE_FILE_PATH="$FREE_DIR/$FILE_NAME"
    
    # 画面キャプチャの実行
    # -m: メインモニターのみ
    # -x: シャッター音を鳴らさない
    # -t jpg: 保存形式をJPGに指定
    screencapture -m -x -t jpg "$FILE_PATH"
    
    if [ -f "$FILE_PATH" ]; then
        chflags uchg "$FILE_PATH"
        cp "$FILE_PATH" "$FREE_FILE_PATH"
    fi
    
    # 30〜90秒のランダムな間隔で待機 (macOS標準のjotコマンドを使用)
    # jot -r [生成数] [最小値] [最大値]
    SLEEP_TIME=$(jot -r 1 30 90)
    sleep "$SLEEP_TIME"
done
