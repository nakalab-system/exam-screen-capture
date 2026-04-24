@echo off
echo ==========================================
echo  Status Check: Screen Capture Tool
echo ==========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Get-CimInstance Win32_Process | Where-Object {$_.CommandLine -match 'capture.ps1'}; if($p){ Write-Host '[RUNNING] The tool is currently active.' -ForegroundColor Green; $f=Get-ChildItem 'C:\capture\*.jpg' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if($f){ Write-Host (' -> Latest capture time: ' + $f.LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Cyan } else { Write-Host ' -> (No images captured yet)' -ForegroundColor Yellow } } else { Write-Host '[STOPPED] The tool is not running.' -ForegroundColor Red }; Write-Host ''; Read-Host 'Press Enter to close this window...'"