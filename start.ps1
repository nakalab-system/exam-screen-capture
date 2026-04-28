$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$studentId = Read-Host "学籍番号を入力してください "
if ([string]::IsNullOrWhiteSpace($studentId)) { exit }

if (-not (Test-Path $saveDir)) {
    New-Item -ItemType Directory -Force -Path $saveDir | Out-Null
}

# 学籍番号を保存してフォルダを隠す
Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8
attrib +h $saveDir

Write-Host "準備が完了しました。数秒後にこの画面は自動で閉じます。" -ForegroundColor Green
Write-Host "※バックグラウンドで監視が始まります。"
Start-Sleep -Seconds 3

$currentDir = (Get-Location).Path
$capturePath = Join-Path $currentDir "capture.ps1"
$wshell = New-Object -ComObject WScript.Shell
# 第2引数の「0」が完全非表示（Stealth）の命令です
$wshell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$capturePath`"", 0, $false)