@echo off
echo ==========================================
echo 画面キャプチャを実行中です...
echo ※試験中は、この黒い画面を閉じないでください。
echo ※試験が終了したら、右上の「×」ボタンで閉じてください。
echo ==========================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture.ps1"