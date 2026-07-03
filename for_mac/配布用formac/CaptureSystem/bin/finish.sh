#!/bin/sh

# =================================================================
# 提出と停止スクリプト (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
SAVE_DIR="$ROOT_DIR/Logs"
FREE_DIR="/tmp/CaptureSystemLogs"
PID_FILE="/tmp/CaptureSystem_capture.pid"
ID_FILE="$SAVE_DIR/student_id.txt"

# 1. キャプチャプロセスの停止
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null; then
        kill -TERM "$PID" 2>/dev/null
    fi
    sleep 2
fi

# 2. フォルダの中身の再帰的ロック解除
if [ -d "$SAVE_DIR" ]; then
    chflags -R nouchg "$SAVE_DIR"
fi

# 3. ZIPアーカイブの作成
if [ -f "$ID_FILE" ]; then
    STUDENT_ID=$(cat "$ID_FILE" | tr -d '[:space:]')
    ZIP_NAME="${STUDENT_ID}_evidence.zip"
    ZIP_PATH="$ROOT_DIR/$ZIP_NAME"
    
    rm -f "$PID_FILE"
    
    # 既存の同名ファイルがあれば、削除せずに末尾へ _2, _3... を付けて回避
    if [ -e "$ZIP_PATH" ]; then
        base="${ZIP_PATH%.*}"
        ext="${ZIP_PATH##*.}"
        n=2
        candidate="${base}_${n}.${ext}"
        while [ -e "$candidate" ]; do
            n=$((n + 1))
            candidate="${base}_${n}.${ext}"
        done
        ZIP_PATH="$candidate"
        ZIP_NAME="$(basename "$ZIP_PATH")"
    fi
    
    # 保存フォルダ内の全データをZIP化
    (cd "$SAVE_DIR" && zip -r "$ZIP_PATH" ./* > /dev/null)

    # 4. クリーンアップ
    rm -rf "$SAVE_DIR"

    MSG="【圧縮完了】\n\n証拠データを作成しました：\n$ZIP_NAME\n\nこのファイルを指定の方法（USBメモリ等）で提出してください。"
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null 2>&1
else
    osascript -e 'display dialog "【エラー】\n学籍番号データが見つかりません。試験が正しく開始されていなかった可能性があります。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
fi
