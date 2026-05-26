[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 【改善】Local AppData に変更
$saveDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

Write-Host "=========================================="
Write-Host " キャプチャ停止と証拠データ作成 (USB提出用) "
Write-Host "=========================================="
Write-Host ""

$processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'capture\.ps1' }
if ($processes) {
    foreach ($p in $processes) {
        $p | Invoke-CimMethod -MethodName Terminate | Out-Null
    }
    Start-Sleep -Seconds 2
}

if (Test-Path $saveDir) {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    icacls $saveDir /remove:d "$currentUser" > $null 2>&1
}

if (Test-Path "$saveDir\student_id.txt") {
    $studentId = (Get-Content "$saveDir\student_id.txt").Trim()
    $datetime = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # 保存先候補
    $desktopPath = "$([Environment]::GetFolderPath('Desktop'))\${studentId}_${datetime}.zip"
    $downloadsPath = "$([Environment]::GetFolderPath('UserProfile'))\Downloads\${studentId}_${datetime}.zip"
    $tempZip = "$env:TEMP\${studentId}_${datetime}.zip"
    
    Write-Host "データを圧縮しています... " -ForegroundColor Cyan
    Compress-Archive -Path "$saveDir\*" -DestinationPath $tempZip -Force

    # 作成したZIPをデスクトップへ移動。OneDriveエラーが出た場合はダウンロードフォルダへ逃がす
    try {
        Move-Item -Path $tempZip -Destination $desktopPath -Force -ErrorAction Stop
        $finalPath = $desktopPath
        
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host " 処理完了：デスクトップに ZIP を作成しました！ " -ForegroundColor Green
        Write-Host " -> $finalPath " -ForegroundColor Yellow
        Write-Host " このファイルをTAのUSBメモリに提出してください。 " -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Green
    } catch {
        Write-Host "[警告] OneDrive等の影響でデスクトップへの保存がブロックされました。" -ForegroundColor Yellow
        Write-Host "       代わりに「ダウンロード」フォルダへ保存します..." -ForegroundColor Yellow
        
        Move-Item -Path $tempZip -Destination $downloadsPath -Force
        $finalPath = $downloadsPath
        
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host " 処理完了：ダウンロードフォルダに ZIP を作成しました！ " -ForegroundColor Green
        Write-Host " -> $finalPath " -ForegroundColor Yellow
        Write-Host " このファイルをTAのUSBメモリに提出してください。 " -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Green
    }
} else {
    Write-Host "[エラー] 学籍番号データが見つかりません。" -ForegroundColor Red
}

if (Test-Path $saveDir) {
    Remove-Item $saveDir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "一時データを安全に削除しました。"
Start-Sleep -Seconds 5