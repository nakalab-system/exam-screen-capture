@echo off
echo ==========================================
echo  Stopping Screen Capture Tool...
echo ==========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object {$_.CommandLine -match 'capture.ps1'} | Invoke-CimMethod -MethodName Terminate | Out-Null"

echo.
echo [STOPPED] The capture has been terminated.
echo.
pause