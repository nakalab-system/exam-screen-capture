#!/bin/bash

# =================================================================
# 試験開始スクリプト (macOS版)
# =================================================================

SAVE_DIR="$HOME/Library/Application Support/CaptureSystem"
PID_FILE="$SAVE_DIR/capture.pid"
ID_FILE="$SAVE_DIR/student_id.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPTURE_SCRIPT="$SCRIPT_DIR/capture.sh"

# 1. 二重起動チェック
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        osascript -e 'display dialog "試験はすでに開始されています。" buttons {"OK"} default button "OK" with icon caution'
        exit 0
    fi
fi

# 2. 学籍番号の入力
STUDENT_ID=$(osascript -e 'display dialog "学籍番号を入力してください:" default answer "" buttons {"キャンセル", "開始"} default button "開始"' -e 'text returned of result')

if [ -z "$STUDENT_ID" ]; then
    exit 0
fi

# 3. 環境準備（ロック解除して書き込み可能にする）
if [ -d "$SAVE_DIR" ]; then
    chflags nouchg "$SAVE_DIR"
fi
mkdir -p "$SAVE_DIR"

# 4. 学籍番号の保存
echo "$STUDENT_ID" > "$ID_FILE"

# 5. 画面収録権限（TCC）の簡易チェック
# 権限がない場合、screencaptureは失敗するか空のファイルを生成する
# ここではシステム設定を開く案内を出す
CHECK_FILE="/tmp/tcc_check.png"
screencapture -x "$CHECK_FILE" 2>/dev/null
if [ ! -f "$CHECK_FILE" ] || [ ! -s "$CHECK_FILE" ]; then
    osascript -e 'display dialog "【重要】画面収録の権限が必要です。\n\n「システム設定」＞「プライバシーとセキュリティ」＞「画面収録」で、このアプリを許可してください。" buttons {"システム設定を開く", "終了"} default button "システム設定を開く"'
    if [ "$?" -eq 0 ]; then
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    fi
    rm -f "$CHECK_FILE"
    exit 1
fi
rm -f "$CHECK_FILE"

# 6. 保存先フォルダのロック（学生による削除防止）
chflags uchg "$SAVE_DIR"

# 7. キャプチャプロセスの起動
# caffeinate -d : ディスプレイのスリープを防止
# & でバックグラウンド実行
nohup caffeinate -d bash "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

osascript -e 'display notification "試験を開始しました。バックグラウンドで記録中です。" with title "試験管理システム"'
sleep 2
