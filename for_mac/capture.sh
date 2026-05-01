#!/bin/bash

# =================================================================
# 試験画面キャプチャツール (macOS版) - コアプロセス
# =================================================================

SAVE_DIR="$HOME/Library/Application Support/CaptureSystem"
PID_FILE="$SAVE_DIR/capture.pid"

# 保存先ディレクトリの作成（存在しない場合）
mkdir -p "$SAVE_DIR"

# 自身のPIDを記録（二重起動防止や終了処理に使用）
echo $$ > "$PID_FILE"

# メインループ
# ※呼び出し側（1_開始.app）で caffeinate -d を介して実行されることを想定
while true; do
    # タイムスタンプの生成
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILE_PATH="$SAVE_DIR/img_$TIMESTAMP.jpg"
    
    # 画面キャプチャの実行
    # -m: メインモニターのみ
    # -x: シャッター音を鳴らさない
    # -t jpg: 保存形式をJPGに指定
    screencapture -m -x -t jpg "$FILE_PATH"
    
    # 30〜90秒のランダムな間隔で待機
    SLEEP_TIME=$((RANDOM % 61 + 30))
    sleep "$SLEEP_TIME"
done
