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
    chflags -R nouchg "$SAVE_DIR"
fi
mkdir -p "$SAVE_DIR"
chflags hidden "$SAVE_DIR"

# 4. 学籍番号の保存
echo "$STUDENT_ID" > "$ID_FILE"
chflags uchg "$ID_FILE"

# 5. 画面収録権限の確認と案内
# OSの許可ポップアップと「開始しました」が重ならないよう、先に案内を表示してユーザーの操作を待ちます。
CHECK_FILE="/tmp/tcc_check.jpg"
rm -f "$CHECK_FILE"
# 1回テスト実行（ここでOSの許可ポップアップがトリガーされる）
screencapture -x -t jpg -R0,0,1,1 "$CHECK_FILE" 2>/dev/null

# 案内ダイアログを表示（これがストッパーになります）
osascript -e 'display dialog "【確認】これより画面キャプチャを開始します。\n\n1. もし「画面収録」の許可を求めるポップアップが出たら、「システム設定を開く」からこのアプリを許可してください。\n2. 許可が完了したら、下の「準備OK」を押してください。" buttons {"準備OK", "中止"} default button "準備OK" with icon note'

if [ $? -ne 0 ]; then
    rm -f "$CHECK_FILE"
    exit 1
fi
rm -f "$CHECK_FILE"

# 6. キャプチャプロセスの起動
# caffeinate -d : ディスプレイのスリープを防止
# & でバックグラウンド実行
nohup caffeinate -d bash "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

# 7. 最終的な開始通知
osascript -e 'display dialog "画面キャプチャを開始しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note'
sleep 2
