$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

function Test-IsOneDrivePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($env:OneDrive -and $Path.StartsWith($env:OneDrive, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($env:OneDriveCommercial -and $Path.StartsWith($env:OneDriveCommercial, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Path -match '\\OneDrive(\s*-\s*[^\\]+)?\\') { return $true }
    return $false
}

function Get-CandidateAnswerRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $shellDesktop = [Environment]::GetFolderPath('Desktop')
    if (-not (Test-IsOneDrivePath $shellDesktop)) { $roots.Add($shellDesktop) }

    $trueDesktop = Join-Path $env:USERPROFILE 'Desktop'
    if (-not (Test-IsOneDrivePath $trueDesktop)) { $roots.Add($trueDesktop) }

    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-IsOneDrivePath $downloads)) { $roots.Add($downloads) }

    $roots.Add("C:\ExamSystem")

    $seen = @{}
    $result = @()
    foreach ($r in $roots) {
        if (-not $seen.ContainsKey($r)) { $seen[$r] = $true; $result += $r }
    }
    return $result
}

$candidateRoots = Get-CandidateAnswerRoots
$desktopPath = [Environment]::GetFolderPath('Desktop')

Write-Host "=========================================="
Write-Host " 　　　提出準備　　　 "
Write-Host "=========================================="
Write-Host ""

$subDirCheck = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1
if ($subDirCheck) {
    $sessionStatePath = Join-Path $subDirCheck.FullName "session.dat"
    if (Test-Path $sessionStatePath) {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " [提出不可] インターネット接続の警告画面が表示中です．" -ForegroundColor Red
        Write-Host " TAによる解除が完了するまで提出処理は実行できません．" -ForegroundColor Red
        Write-Host " 画面の指示に従い，ただちにTAを呼んでください．" -ForegroundColor Red
        Write-Host "=================================================" -ForegroundColor Red
        exit 1
    }
}

$processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*system_core.ps1*' }
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
    
    $zipName = "${studentId}_${datetime}.zip"
    $tempZip = "$env:TEMP\$zipName"

    Write-Host "キャプチャ画像を圧縮しています... " -ForegroundColor Cyan

    Compress-Archive -Path "$saveDir\*" -DestinationPath $tempZip -Force

    $targetDir = ""
    foreach ($root in $candidateRoots) {
        $candidate = "$root\${studentId}_${savedDate}"
        if (Test-Path $candidate) { $targetDir = $candidate; break }
    }
    if (-not $targetDir) {
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