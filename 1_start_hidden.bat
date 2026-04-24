@echo off
cd /d "%~dp0"
echo ==========================================
echo  Starting Background Screen Capture
echo ==========================================
echo.
echo * This window will close automatically in a few seconds.
echo * The capture will continue running in the background.
echo * To stop the capture, run "3_stop.bat".
echo.
timeout /t 3 >nul
powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "capture.ps1"