#!/bin/sh

# =================================================================
# 試験開始スクリプト (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="/tmp/CaptureSystem_capture.pid"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
CAPTURE_SCRIPT="$ROOT_DIR/bin/capture.sh"
TODAY_STR=$(date +%Y%m%d)

xattr -cr "$ROOT_DIR/Check.app" # com.apple.quarantineの回避

# 二重起動チェック
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        osascript -e 'display dialog "試験はすでに開始されています。" buttons {"試験に戻る"} default button "試験に戻る" with icon caution' >/dev/null 2>&1
        exit 0
    fi
fi

# 学籍番号の入力
STUDENT_ID=$(osascript -e 'display dialog "学籍番号を入力してください:" default answer "" buttons {"キャンセル", "次へ"} default button "次へ" cancel button "キャンセル"' -e 'text returned of result' 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$STUDENT_ID" ]; then # キャンセルボタン押下 or 何も入力されなかった場合
    exit 0
fi

SAVE_DIR="$ROOT_DIR/${STUDENT_ID}_${TODAY_STR}"
ID_FILE="$SAVE_DIR/student_id.txt"

if [ -d "$SAVE_DIR" ]; then
    chflags -R nouchg "$SAVE_DIR"
fi
mkdir -p "$SAVE_DIR"

chflags hidden "$SAVE_DIR"

if [ -f "$ID_FILE" ]; then
    chflags nouchg "$ID_FILE" # 解除
fi
echo "$STUDENT_ID" > "$ID_FILE" # >>は追記，>は上書き
chflags uchg "$ID_FILE" # ロック
echo "$SAVE_DIR" > "$SAVE_DIR_FILE"

osascript -e 'display dialog "【案内】\nこのあと「画面収録」の許可を求めるポップアップが表示される場合があります。\n\n「システム設定を開く」を押して、お使いのターミナルアプリを一時的に「オン」に設定してください。" buttons {"次へ"} default button "次へ" with icon note' >/dev/null 2>&1

while true; do
    screencapture -x -t jpg -R0,0,1,1 "/tmp/CaptureSystem_tcc_check.jpg" 2>/dev/null
    TCC_CHECK_STATUS=$?
    if [ "$TCC_CHECK_STATUS" -eq 0 ]; then
        TCC_CHECK_RESULT="成功"
        break
    fi

    sleep 5

    TCC_CHECK_RESULT="失敗 (exit=$TCC_CHECK_STATUS)"
    APP_NAME="※ 実行環境：${TERM_PROGRAM:-不明}.app"
    osascript -e "display dialog \"事前撮影チェック: $TCC_CHECK_RESULT\n\n$APP_NAME\" buttons {\"再度チェックする\",\"最初からやり直す\"} default button \"再度チェックする\" cancel button \"最初からやり直す\"" >/dev/null 2>&1

    if [ $? -ne 0 ]; then # neはnot equalの意味 << キャンセルボタンが押されたら..
        exit 0
    fi
done

osascript -e "display dialog \"【事前準備完了】\n学籍番号: $STUDENT_ID\n\n撮影を開始します。\n\n※ 画面撮影はバックグラウンドで実行されます。\n\n\" buttons {\"撮影を開始する\", \"最初からやり直す\"} cancel button \"撮影を開始する\" default button \"最初からやり直す\" with icon note" >/dev/null 2>&1
if [ $? -ne 1 ]; then
    exit 1
fi

nohup caffeinate -d sh "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

osascript -e 'display dialog "撮影を開始しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note' >/dev/null 2>&1
