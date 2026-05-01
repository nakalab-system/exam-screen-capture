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
STUDENT_ID=$(osascript -e 'display dialog "学籍番号を入力してください:" default answer "" buttons {"キャンセル", "開始"} default button "開始" cancel button "キャンセル"' -e 'text returned of result')

if [ $? -ne 0 ] || [ -z "$STUDENT_ID" ]; then
    exit 0
fi

# 3. 環境準備
if [ -d "$SAVE_DIR" ]; then
    chflags -R nouchg "$SAVE_DIR"
fi
mkdir -p "$SAVE_DIR"
chflags hidden "$SAVE_DIR"

# 4. 学籍番号の保存
echo "$STUDENT_ID" > "$ID_FILE"
chflags uchg "$ID_FILE"

# 5. 画面収録権限の案内と誘発
# ステップ1: 最初の案内を表示
osascript -e 'display dialog "【案内】\nこのあと「画面収録」の許可を求めるポップアップが表示されます。\n\n「システム設定を開く」を押して、このアプリを「オン」に設定してください。" buttons {"次へ"} default button "次へ" with icon note'

if [ $? -ne 0 ]; then
    exit 1
fi

# ステップ2: 権限ポップアップを誘発
screencapture -x -t jpg -R0,0,1,1 /tmp/tcc_check.jpg 2>/dev/null
# 5秒待機して、OSのポップアップが前面に出る時間を十分に確保する
sleep 5

# ステップ3: 準備完了を待つ（改行を入れて縦長に調整）
osascript -e 'display dialog "\n\n許可の設定は完了しましたか？\n\n（既に許可済みの場合は、そのまま「準備OK」を押してください）\n\n" buttons {"準備OK", "中止"} default button "準備OK" cancel button "中止" with icon note'

if [ $? -ne 0 ]; then
    exit 1
fi

# 6. キャプチャプロセスの起動
nohup caffeinate -d bash "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

# 7. 最終的な開始通知
osascript -e 'display dialog "画面キャプチャを開始しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note'
sleep 2
