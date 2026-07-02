$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
$desktopPath = [Environment]::GetFolderPath('Desktop')
$downloadsPath = "$([Environment]::GetFolderPath('UserProfile'))\Downloads"

Write-Host "=========================================="
Write-Host " 　　　提出準備　　　 "
Write-Host "=========================================="
Write-Host ""

$subDirCheck = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1
if ($subDirCheck) {
    $lockFlagPath = Join-Path $subDirCheck.FullName "LOCK_ACTIVE.flag"
    if (Test-Path $lockFlagPath) {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " [提出不可] インターネット接続の警告画面が表示中です．" -ForegroundColor Red
        Write-Host " TAによる解除が完了するまで提出処理は実行できません．" -ForegroundColor Red
        Write-Host " 画面の指示に従い，ただちにTAを呼んでください．" -ForegroundColor Red
        Write-Host "=================================================" -ForegroundColor Red
        exit 1
    }
}

# 偽装したプロセス名（WinSysMonitor.exe）を狙って停止する
$processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'WinSysMonitor.exe' }
if ($processes) {
    foreach ($p in $processes) {
        $p | Invoke-CimMethod -MethodName Terminate | Out-Null
    }
    Start-Sleep -Seconds 2
}

$subDir = Get-ChildItem -Path $baseDir -Directory -Force | Select-Object -First 1

if ($subDir -and $subDir.Name -match "^([0-9]{8})_([0-9]{8})$") {
    $saveDir = $subDir.FullName
    $studentId = $matches[1]
    $savedDate = $matches[2]
    $datetime = Get-Date -Format "yyyyMMdd_HHmmss"
    
    $answerDirDesktop = "$desktopPath\${studentId}_${savedDate}"
    $answerDirDownloads = "$downloadsPath\${studentId}_${savedDate}"
    
    $zipName = "${studentId}_${datetime}.zip"
    $tempZip = "$env:TEMP\$zipName"
    
    Write-Host "キャプチャ画像を圧縮しています... " -ForegroundColor Cyan
    
    Compress-Archive -Path "$saveDir\*" -DestinationPath $tempZip -Force

    $targetDir = ""
    if (Test-Path $answerDirDesktop) {
        $targetDir = $answerDirDesktop
    } elseif (Test-Path $answerDirDownloads) {
        $targetDir = $answerDirDownloads
    } else {
        $targetDir = $desktopPath
        Write-Host "[警告] 解答用フォルダが見つからないため，デスクトップ直下に保存します．" -ForegroundColor Yellow
    }

    $finalDest = "$targetDir\$zipName"

    try {
        Move-Item -Path $tempZip -Destination $finalDest -Force -ErrorAction Stop
        
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host " 処理完了：回答用フォルダ内にZIPファイルを格納しました！ " -ForegroundColor Green
        Write-Host " -> $finalDest " -ForegroundColor Yellow
        Write-Host " 提出するCPPファイルを回答用フォルダに入れ， " -ForegroundColor Yellow
        Write-Host " USBメモリでTAに提出してください． " -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Green
    } catch {
        Write-Host "[エラー] ZIPファイルの作成・移動に失敗しました．" -ForegroundColor Red
    }
    
} else {
    Write-Host "[エラー] 学籍番号データが見つかりません．" -ForegroundColor Red
}

if (Test-Path $baseDir) {
    Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue
}