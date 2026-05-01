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
    
    # 子プロセス (capture.sh) の親 (caffeinate) の PID を取得
    # ps -o ppid= で親PIDを取得し、xargs で余計な空白を削除
    PPID_VAL=$(ps -o ppid= -p "$PID" 2>/dev/null | xargs)
    
    # 子プロセスを終了
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null; then
        kill -TERM "$PID" 2>/dev/null
    fi
    
    # 親プロセス (caffeinate) を終了
    if [ -n "$PPID_VAL" ] && ps -p "$PPID_VAL" > /dev/null; then
        kill -TERM "$PPID_VAL" 2>/dev/null
    fi
    
    sleep 2
fi

# 2. フォルダのロック解除
if [ -d "$SAVE_DIR" ]; then
    chflags -R nouchg "$SAVE_DIR"
fi

# 3. ZIPアーカイブの作成
if [ -f "$ID_FILE" ]; then
    STUDENT_ID=$(cat "$ID_FILE" | tr -d '[:space:]')
    ZIP_NAME="${STUDENT_ID}_evidence.zip"
    ZIP_PATH="$DESKTOP_DIR/$ZIP_NAME"
    
    # プロセス管理用ファイルを提出データから除外するために削除
    rm -f "$PID_FILE"
    
    # 既存の同名ファイルがあれば削除
    rm -f "$ZIP_PATH"
    
    # 保存フォルダ内の全データをZIP化
    # cd して相対パスで固めることで、ZIP展開時に余計な階層ができないようにする
    (cd "$SAVE_DIR" && zip -r "$ZIP_PATH" ./* > /dev/null)

    # 4. クリーンアップ
    rm -rf "$SAVE_DIR"

    MSG="【圧縮完了】\n\nデスクトップに証拠データを作成しました：\n$ZIP_NAME\n\n一時データを安全に削除しました。\n\nこのファイルを指定の方法（USBメモリ等）で提出してください。"
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note"
else
    osascript -e 'display dialog "【エラー】\n学籍番号データが見つかりません。試験が正しく開始されていなかった可能性があります。" buttons {"OK"} default button "OK" with icon stop'
fi
