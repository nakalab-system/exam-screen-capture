#!/bin/bash

# =================================================================
# 提出と停止スクリプト (macOS版)
# =================================================================

SAVE_DIR="$HOME/Library/Application Support/CaptureSystem"
PID_FILE="$SAVE_DIR/capture.pid"
ID_FILE="$SAVE_DIR/student_id.txt"
DESKTOP_DIR="$HOME/Desktop"

# 1. キャプチャプロセスの停止
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    # capture.sh と、それを実行している caffeinate の両方を止める
    # pkill -P は親プロセスIDを指定して子を殺すが、ここでは関連プロセスをまとめて落とす
    pkill -TERM -f "capture.sh"
    pkill -TERM -f "caffeinate -d bash"
    sleep 2
fi

# 2. フォルダのロック解除
if [ -d "$SAVE_DIR" ]; then
    chflags nouchg "$SAVE_DIR"
fi

# 3. ZIPアーカイブの作成
if [ -f "$ID_FILE" ]; then
    STUDENT_ID=$(cat "$ID_FILE" | tr -d '[:space:]')
    ZIP_NAME="${STUDENT_ID}_evidence.zip"
    ZIP_PATH="$DESKTOP_DIR/$ZIP_NAME"
    
    # 既存の同名ファイルがあれば削除
    rm -f "$ZIP_PATH"
    
    # 保存フォルダ内の全データをZIP化
    # cd して相対パスで固めることで、ZIP展開時に余計な階層ができないようにする
    (cd "$SAVE_DIR" && zip -r "$ZIP_PATH" ./* > /dev/null)

    # 4. クリーンアップ
    rm -rf "$SAVE_DIR"

    MSG="【提出完了】\n\nデスクトップに証拠データを作成しました：\n$ZIP_NAME\n\nこのファイルを指定の方法（USBメモリ等）で提出してください。"
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note"
else
    osascript -e 'display dialog "【エラー】\n学籍番号データが見つかりません。試験が正しく開始されていなかった可能性があります。" buttons {"OK"} default button "OK" with icon stop'
fi
