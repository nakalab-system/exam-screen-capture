#!/bin/zsh

# 保存先の設定（MacはCドライブがないため、デスクトップに作成します）
SAVE_DIR="$HOME/Desktop/capture"
mkdir -p "$SAVE_DIR"

# 画面のクリアと案内表示
clear
echo "=========================================="
echo " Mac用 画面キャプチャツール 実行中"
echo "=========================================="
echo "※この黒い画面（ターミナル）を開いたまま試験を受けてください。"
echo "※終了時はこの画面を閉じるか、「Ctrl + C」を押してください。"
echo ""

while true; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    FILE_PATH="$SAVE_DIR/screen_$TIMESTAMP.jpg"

    # Mac標準のキャプチャコマンド (-x を付けることでシャッター音を完全に無音化)
    # 複数ディスプレイがある場合はメインディスプレイが保存されます
    screencapture -x "$FILE_PATH"

    echo "[$TIMESTAMP] 画面を保存しました。(保存先: デスクトップ/capture)"

    # ランダム待機（30秒〜90秒）
    # RANDOMは0〜32767を返すため、61で割った余り(0〜60)に30を足す
    SLEEP_TIME=$((RANDOM % 61 + 30))
    echo "次のキャプチャまで $SLEEP_TIME 秒待機しています..."
    sleep $SLEEP_TIME
done
