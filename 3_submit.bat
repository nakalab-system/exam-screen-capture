@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = [System.IO.File]::ReadAllText('%~dp0submit.ps1', [System.Text.Encoding]::UTF8); Invoke-Expression $c"
pause