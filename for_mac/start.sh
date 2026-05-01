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

# 5. 画面収録権限（TCC）の確認と取得ループ
while true; do
    # 権限の簡易チェック: 他のプロセスのウィンドウ名が取得できるか確認
    # (権限がない場合、通常は0または極小の値になる)
    WINDOW_COUNT=$(osascript -e 'tell application "System Events" to count (every window of (every process whose visible is true) whose name is not "")' 2>/dev/null)
    
    # 実際のキャプチャを試行してファイルサイズでも判定
    CHECK_FILE="/tmp/tcc_check.jpg"
    rm -f "$CHECK_FILE"
    screencapture -x -t jpg -R0,0,1,1 "$CHECK_FILE" 2>/dev/null
    
    HAS_PERMISSION=false
    if [ -f "$CHECK_FILE" ]; then
        FILE_SIZE=$(stat -f%z "$CHECK_FILE")
        # 権限がある場合、1x1のキャプチャでも数KB程度になる
        # ウィンドウ名の取得数と合わせて総合的に判断
        if [ "$WINDOW_COUNT" -gt 0 ] && [ "$FILE_SIZE" -gt 0 ]; then
            HAS_PERMISSION=true
        fi
    fi
    rm -f "$CHECK_FILE"

    if [ "$HAS_PERMISSION" = true ]; then
        break
    else
        # 権限がない場合、ユーザーに許可を求めるダイアログを表示
        # ここで「システム設定を開く」を押すと設定画面へ、
        # 「設定した」を押すとループの最初に戻って再チェックする
        RESPONSE=$(osascript -e 'display dialog "【重要】画面収録の権限設定が必要です。\n\n1. 「システム設定を開く」ボタンを押し、一覧にある「1_開始」（またはこのアプリ）のスイッチをオンにしてください。\n2. 設定が完了したら、この画面に戻って「設定した」ボタンを押してください。" buttons {"システム設定を開く", "設定した", "中止"} default button "設定した" with icon caution' -e 'button returned of result')
        
        if [ "$RESPONSE" = "システム設定を開く" ]; then
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            continue
        elif [ "$RESPONSE" = "設定した" ]; then
            continue
        else
            exit 1
        fi
    fi
done

# 6. 保存先フォルダのロック（ディレクトリ全体をロックすると書き込めなくなるため無効化）
# chflags uchg "$SAVE_DIR"

# 7. キャプチャプロセスの起動
# caffeinate -d : ディスプレイのスリープを防止
# & でバックグラウンド実行
nohup caffeinate -d bash "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

# 通知センターに隠されないよう、画面中央にダイアログとして強制表示させる
osascript -e 'display dialog "画面キャプチャを開始しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note'
sleep 2
