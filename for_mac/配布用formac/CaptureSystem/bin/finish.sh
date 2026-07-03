#!/bin/sh

# =================================================================
# 提出と停止スクリプト (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
FREE_DIR="/tmp/CaptureSystemLogs"
PID_FILE="/tmp/CaptureSystem_capture.pid"
MONITOR_PID_FILE="/tmp/CaptureSystem_network_monitor.pid"
LOCK_SCREEN_PID_FILE="/tmp/CaptureSystem_lock_screen.pid"
STATUS_BAR_PID_FILE="/tmp/CaptureSystem_status_bar.pid"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
ANSWER_DIR_FILE="/tmp/CaptureSystem_answer_dir.txt"
STATUS_FILE="/tmp/CaptureSystem_status.json"
DESKTOP_DIR="$HOME/Desktop"
DOWNLOADS_DIR="$HOME/Downloads"

SAVE_DIR=""
if [ -f "$SAVE_DIR_FILE" ]; then
    SAVE_DIR=$(cat "$SAVE_DIR_FILE")
fi

ID_FILE="$SAVE_DIR/student_id.txt"
LOCK_FLAG="$SAVE_DIR/LOCK_ACTIVE.flag"

if [ -f "$LOCK_FLAG" ]; then
    osascript -e 'display dialog "【提出不可】\nインターネット接続の警告状態です。\nTAによる解除が完了するまで提出処理は実行できません。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
    exit 1
fi

# 1. キャプチャプロセスの停止
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null; then
        kill -TERM "$PID" 2>/dev/null
    fi
    sleep 2
fi

if [ -f "$MONITOR_PID_FILE" ]; then
    MONITOR_PID=$(cat "$MONITOR_PID_FILE")

    if [ -n "$MONITOR_PID" ] && ps -p "$MONITOR_PID" > /dev/null; then
        kill -TERM "$MONITOR_PID" 2>/dev/null
    fi
fi

if [ -f "$LOCK_SCREEN_PID_FILE" ]; then
    LOCK_SCREEN_PID=$(cat "$LOCK_SCREEN_PID_FILE")

    if [ -n "$LOCK_SCREEN_PID" ] && ps -p "$LOCK_SCREEN_PID" > /dev/null; then
        kill -TERM "$LOCK_SCREEN_PID" 2>/dev/null
    fi
fi

if [ -f "$STATUS_BAR_PID_FILE" ]; then
    STATUS_BAR_PID=$(cat "$STATUS_BAR_PID_FILE")

    if [ -n "$STATUS_BAR_PID" ] && ps -p "$STATUS_BAR_PID" > /dev/null; then
        kill -TERM "$STATUS_BAR_PID" 2>/dev/null
    fi
fi

# 2. フォルダの中身の再帰的ロック解除
if [ -d "$SAVE_DIR" ]; then
    chflags -R nouchg "$SAVE_DIR"
fi

# 3. ZIPアーカイブの作成
if [ -f "$ID_FILE" ]; then
    STUDENT_ID=$(cat "$ID_FILE" | tr -d '[:space:]')
    ZIP_NAME="${STUDENT_ID}_$(date +%Y%m%d_%H%M%S).zip"
    ANSWER_DIR=""
    if [ -f "$ANSWER_DIR_FILE" ]; then
        ANSWER_DIR=$(cat "$ANSWER_DIR_FILE")
    fi

    if [ -z "$ANSWER_DIR" ] || [ ! -d "$ANSWER_DIR" ]; then
        TODAY_STR=$(date +%Y%m%d)
        ANSWER_DIR_DESKTOP="$DESKTOP_DIR/${STUDENT_ID}_${TODAY_STR}"
        ANSWER_DIR_DOWNLOADS="$DOWNLOADS_DIR/${STUDENT_ID}_${TODAY_STR}"

        if [ -d "$ANSWER_DIR_DESKTOP" ] || mkdir -p "$ANSWER_DIR_DESKTOP" 2>/dev/null; then
            ANSWER_DIR="$ANSWER_DIR_DESKTOP"
        elif [ -d "$ANSWER_DIR_DOWNLOADS" ] || mkdir -p "$ANSWER_DIR_DOWNLOADS" 2>/dev/null; then
            ANSWER_DIR="$ANSWER_DIR_DOWNLOADS"
        else
            ANSWER_DIR="$ROOT_DIR"
        fi
    fi

    ZIP_PATH="$ANSWER_DIR/$ZIP_NAME"
    
    rm -f "$PID_FILE"
    rm -f "$MONITOR_PID_FILE"
    rm -f "$LOCK_SCREEN_PID_FILE"
    rm -f "$STATUS_BAR_PID_FILE"
    rm -f "$SAVE_DIR_FILE"
    rm -f "$ANSWER_DIR_FILE"
    rm -f "$STATUS_FILE"
    
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

    MSG="【圧縮完了】\n\n証拠データを作成しました：\n$ZIP_NAME\n\n保存先:\n$ANSWER_DIR\n\nこのファイルを指定の方法（USBメモリ等）で提出してください。"
    osascript -e "display dialog \"$MSG\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null 2>&1
else
    osascript -e 'display dialog "【エラー】\n学籍番号データが見つかりません。試験が正しく開始されていなかった可能性があります。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
fi
