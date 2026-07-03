#!/bin/sh

# =================================================================
# 試験開始スクリプト (macOS版)
# =================================================================

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="/tmp/CaptureSystem_capture.pid"
SAVE_DIR_FILE="/tmp/CaptureSystem_save_dir.txt"
ANSWER_DIR_FILE="/tmp/CaptureSystem_answer_dir.txt"
CAPTURE_SCRIPT="$ROOT_DIR/bin/capture.sh"
TODAY_STR=$(date +%Y%m%d)
DESKTOP_DIR="$HOME/Desktop"
DOWNLOADS_DIR="$HOME/Downloads"
START_MODE="new"
RESUME_DIR=""
RESUME_ID=""
RESTORE_ZIP=""

xattr -cr "$ROOT_DIR/Check.app" # com.apple.quarantineの回避

test_internet_connectivity() {
    ok_ping=0
    ok_dns=0
    ok_http=0

    if ping -c 1 -W 1000 8.8.8.8 >/dev/null 2>&1; then
        ok_ping=1
    fi

    if dscacheutil -q host -a name www.google.com >/dev/null 2>&1; then
        ok_dns=1
    fi

    if curl -s -o /dev/null --max-time 3 http://clients3.google.com/generate_204; then
        ok_http=1
    fi

    score=$((ok_ping + ok_dns + ok_http))
    [ "$score" -ge 2 ]
}

# 二重起動チェック
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        osascript -e 'display dialog "試験はすでに開始されています。" buttons {"試験に戻る"} default button "試験に戻る" with icon caution' >/dev/null 2>&1
        exit 0
    fi
fi

# 開始前のオフライン確認
while true; do
    if test_internet_connectivity; then
        osascript -e 'display dialog "【警告】インターネット接続が検出されました。\n\n試験を開始するには、PCを完全にオフラインにしてください。\nWi-Fiをオフにした後で「再確認」を押してください。" buttons {"中止", "再確認"} default button "再確認" cancel button "中止" with icon caution' >/dev/null 2>&1

        if [ $? -ne 0 ]; then
            exit 0
        fi
    else
        break
    fi
done

# 当日の未提出データがあれば再開
for candidate_dir in "$ROOT_DIR"/*_"$TODAY_STR"; do
    if [ ! -d "$candidate_dir" ]; then
        continue
    fi

    candidate_name=$(basename "$candidate_dir")
    candidate_id=${candidate_name%_"$TODAY_STR"}
    candidate_id_file="$candidate_dir/student_id.txt"

    if [ -f "$candidate_id_file" ] && [ -n "$candidate_id" ]; then
        RESUME_DIR="$candidate_dir"
        RESUME_ID=$(tr -d '[:space:]' < "$candidate_id_file")
        START_MODE="resume"
        break
    fi
done

if [ "$START_MODE" = "resume" ]; then
    STUDENT_ID="$RESUME_ID"
    SAVE_DIR="$RESUME_DIR"
    osascript -e "display dialog \"【再開】\n本日の未提出データが見つかりました。\n\n学籍番号: $STUDENT_ID\n\nキャプチャを再開します。\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null 2>&1
else
    for answer_base in "$DESKTOP_DIR" "$DOWNLOADS_DIR"; do
        if [ ! -d "$answer_base" ]; then
            continue
        fi

        for answer_dir in "$answer_base"/*_"$TODAY_STR"; do
            if [ ! -d "$answer_dir" ]; then
                continue
            fi

            answer_name=$(basename "$answer_dir")
            candidate_id=${answer_name%_"$TODAY_STR"}

            case "$candidate_id" in
                ''|*[!0-9]*)
                    continue
                    ;;
            esac

            latest_zip=$(find "$answer_dir" -maxdepth 1 -type f -name "${candidate_id}_${TODAY_STR}_*.zip" | sort | tail -n 1)
            if [ -n "$latest_zip" ]; then
                STUDENT_ID="$candidate_id"
                SAVE_DIR="$ROOT_DIR/${STUDENT_ID}_${TODAY_STR}"
                RESUME_DIR="$answer_dir"
                RESTORE_ZIP="$latest_zip"
                START_MODE="restore"
                break 2
            fi
        done
    done

    if [ "$START_MODE" = "restore" ]; then
        TEMP_EXTRACT="/tmp/CaptureSystem_restore_${STUDENT_ID}"

        if [ -d "$SAVE_DIR" ]; then
            chflags -R nouchg "$SAVE_DIR"
            rm -rf "$SAVE_DIR"
        fi
        mkdir -p "$SAVE_DIR"

        rm -rf "$TEMP_EXTRACT"
        mkdir -p "$TEMP_EXTRACT"

        if unzip -oq "$RESTORE_ZIP" -d "$TEMP_EXTRACT" >/dev/null 2>&1; then
            cp -R "$TEMP_EXTRACT"/. "$SAVE_DIR"/
            rm -rf "$TEMP_EXTRACT"
            rm -f "$RESTORE_ZIP"
            osascript -e "display dialog \"【復元再開】\n提出済みZIPが見つかりました。\n\n学籍番号: $STUDENT_ID\n\n証拠データを復元してキャプチャを再開します。\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null 2>&1
        else
            rm -rf "$TEMP_EXTRACT"
            rm -rf "$SAVE_DIR"
            osascript -e 'display dialog "【エラー】\n提出済みZIPの復元に失敗しました。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
            exit 1
        fi
    else
        # 学籍番号の入力
        STUDENT_ID=$(osascript -e 'display dialog "学籍番号を入力してください:" default answer "" buttons {"キャンセル", "次へ"} default button "次へ" cancel button "キャンセル"' -e 'text returned of result' 2>/dev/null)

        if [ $? -ne 0 ] || [ -z "$STUDENT_ID" ]; then # キャンセルボタン押下 or 何も入力されなかった場合
            exit 0
        fi

        SAVE_DIR="$ROOT_DIR/${STUDENT_ID}_${TODAY_STR}"
    fi
fi

ID_FILE="$SAVE_DIR/student_id.txt"
ANSWER_DIR_NAME="${STUDENT_ID}_${TODAY_STR}"
ANSWER_DIR_DESKTOP="$DESKTOP_DIR/$ANSWER_DIR_NAME"
ANSWER_DIR_DOWNLOADS="$DOWNLOADS_DIR/$ANSWER_DIR_NAME"
ANSWER_DIR=""

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

if mkdir -p "$ANSWER_DIR_DESKTOP" 2>/dev/null; then
    ANSWER_DIR="$ANSWER_DIR_DESKTOP"
elif mkdir -p "$ANSWER_DIR_DOWNLOADS" 2>/dev/null; then
    ANSWER_DIR="$ANSWER_DIR_DOWNLOADS"
else
    osascript -e 'display dialog "【エラー】\n解答用フォルダを作成できませんでした。" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
    exit 1
fi

echo "$ANSWER_DIR" > "$ANSWER_DIR_FILE"

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

if [ "$START_MODE" = "resume" ]; then
    READY_MSG="【再開準備完了】\n学籍番号: $STUDENT_ID\n\n撮影を再開します。\n\n※ 画面撮影はバックグラウンドで実行されます。\n\n"
elif [ "$START_MODE" = "restore" ]; then
    READY_MSG="【復元再開準備完了】\n学籍番号: $STUDENT_ID\n\n提出済みZIPから復元し、撮影を再開します。\n\n※ 画面撮影はバックグラウンドで実行されます。\n\n"
else
    READY_MSG="【事前準備完了】\n学籍番号: $STUDENT_ID\n\n撮影を開始します。\n\n※ 画面撮影はバックグラウンドで実行されます。\n\n"
fi

osascript -e "display dialog \"$READY_MSG\" buttons {\"撮影を開始する\", \"最初からやり直す\"} cancel button \"撮影を開始する\" default button \"最初からやり直す\" with icon note" >/dev/null 2>&1
if [ $? -ne 1 ]; then
    exit 1
fi

nohup caffeinate -d sh "$CAPTURE_SCRIPT" > /dev/null 2>&1 &

if [ "$START_MODE" = "resume" ] || [ "$START_MODE" = "restore" ]; then
    osascript -e 'display dialog "撮影を再開しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note' >/dev/null 2>&1
else
    osascript -e 'display dialog "撮影を開始しました。\nバックグラウンドで記録中です。" buttons {"OK"} default button "OK" with icon note' >/dev/null 2>&1
fi
