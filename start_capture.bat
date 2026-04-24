@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "capture.ps1"
pause
