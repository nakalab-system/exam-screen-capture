#!/bin/sh

# =================================================================
# 試験画面キャプチャツール (macOS版) - コアプロセス
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
SAVE_DIR="$ROOT_DIR/Logs"
FREE_DIR="/tmp/CaptureSystemLogs"
PID_FILE="/tmp/CaptureSystem_capture.pid"

mkdir -p "$SAVE_DIR"
mkdir -p "$FREE_DIR"
echo $$ > "$PID_FILE"

# メインループ
while true; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILE_NAME="img_$TIMESTAMP.jpg"
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
