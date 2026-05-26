[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$saveDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

if (Test-Path $saveDir) {
    [void](icacls $saveDir /remove:d ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) > $null 2>&1)
    [void](Remove-Item $saveDir -Recurse -Force -ErrorAction SilentlyContinue > $null 2>&1)
}
[void](New-Item -ItemType Directory -Force -Path $saveDir)

$studentId = ""
while ($studentId -notmatch "^[0-9]{8}$") {
    $studentId = Read-Host "学籍番号を入力してください（半角数字8桁）"
    if ($studentId -notmatch "^[0-9]{8}$") {
        Write-Host "エラー：学籍番号は「半角数字8桁」で入力してください。" -ForegroundColor Red
    }
}

[void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
[void](attrib +h $saveDir)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
[void](icacls $saveDir /deny "${currentUser}:(DE,DC)" > $null 2>&1)

$capturePath = "$PSScriptRoot\capture.ps1"
[void](Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$capturePath`"" -WindowStyle Hidden)

Write-Host "画面キャプチャを開始しました..." -ForegroundColor Green
Start-Sleep -Seconds 2

exit