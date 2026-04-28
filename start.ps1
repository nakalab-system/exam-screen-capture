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

# 画像は保存できるが、削除だけを不可能にする
icacls $saveDir /deny "$($env:USERNAME):(OI)(CI)(DE,DC)" | Out-Null

Write-Host "準備が完了しました。数秒後にこの画面は自動で閉じます。" -ForegroundColor Green
Write-Host "※バックグラウンドで監視が始まります。"
Start-Sleep -Seconds 3

# 画面を完全に隠して起動
$currentDir = (Get-Location).Path
$capturePath = Join-Path $currentDir "capture.ps1"
$wshell = New-Object -ComObject WScript.Shell
$wshell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$capturePath`"", 0, $false)