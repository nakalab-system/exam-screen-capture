Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

$isResume = $false
$studentId = ""
$todayStr = Get-Date -Format "yyyyMMdd"
$date = ""

function Test-InternetConnectivity {
    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        return $false
    }

    $okGw  = $false
    $okDns = $false

    try {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
               Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gw) {
            $ping  = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($gw, 1000)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $okGw = $true
            }
        }
    } catch {}

    try {
        $profile = Get-NetConnectionProfile -ErrorAction Stop |
                   Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }
        if ($profile) { $okDns = $true }
    } catch {}

    return ($okGw -or $okDns)
}

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

Write-Host "`n[準備] ネットワーク接続状態を確認しています..." -ForegroundColor Cyan
while ($true) {
    $isConnected = $false
    try { $isConnected = Test-InternetConnectivity } catch { $isConnected = $false }

    if ($isConnected) {
        Write-Host "`n==========================================" -ForegroundColor Red
        Write-Host " 【警告】インターネット接続が検出されました！" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host " 試験を開始するためには，PCを完全にオフラインにする必要があります．" -ForegroundColor Yellow
        Write-Host " PCの Wi-Fi を「オフ（切断）」にしてください．" -ForegroundColor White
        Write-Host " ------------------------------------------" -ForegroundColor DarkGray
        Write-Host " Wi-Fiを切断したら，Enterキーを押して再確認してください．" -ForegroundColor Cyan
        Read-Host
    } else {
        Write-Host " -> [OK] オフライン環境を確認しました．`n" -ForegroundColor Green
        break
    }
}

if (Test-Path $baseDir) {
    $oldSubDir = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^([0-9]{8})_($todayStr)$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($oldSubDir) {
        [void]($oldSubDir.Name -match "^([0-9]{8})_($todayStr)$")
        $studentId = $matches[1]; $date = $matches[2]; $isResume = $true
        Write-Host "[検知] 本日の未提出データが見つかりました．キャプチャを再開します．" -ForegroundColor Green
    } else {
        Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue > $null 2>&1
    }
}

if (-not $isResume) {
    $potentialDirs = @()
    foreach ($root in $candidateRoots) {
        if (Test-Path $root) {
            $potentialDirs += @(Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^([0-9]{8})_($todayStr)$" })
        }
    }

    foreach ($dir in $potentialDirs) {
        $sid = $dir.Name.Split('_')[0]
        $zips = @(Get-ChildItem -Path $dir.FullName -Filter "${sid}_${todayStr}_*.zip" -Force -ErrorAction SilentlyContinue)
        if ($zips) {
            $latestZip = $zips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $studentId = $sid; $date = $todayStr; $isResume = $true
            
            Write-Host "[検知] 本日の誤って終了された画像ZIPからデータを復元し，再開します．" -ForegroundColor Green
            
            if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
            $saveDir = "$baseDir\${studentId}_${date}"
            if (-not (Test-Path $saveDir)) { [void](New-Item -ItemType Directory -Force -Path $saveDir) }
            
            $tempExtract = "$env:TEMP\ExtractStage_${studentId}"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
            [void](New-Item -ItemType Directory -Force -Path $tempExtract)
            
            Expand-Archive -Path $latestZip.FullName -DestinationPath $tempExtract -Force
            Copy-Item -Path "$tempExtract\*" -Destination $saveDir -Recurse -Force
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $latestZip.FullName -Force -ErrorAction SilentlyContinue
            
            [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
            break
        }
    }
}

if (-not $isResume) {
    if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
    while ($studentId -notmatch "^[0-9]{8}$") {
        $studentId = Read-Host "学籍番号を入力してください（半角数字8桁）"
        if ($studentId -notmatch "^[0-9]{8}$") { Write-Host "エラー：学籍番号は「半角数字8桁」で入力してください．" -ForegroundColor Red }
    }
    $date = $todayStr
    $saveDir = "$baseDir\${studentId}_${date}"
    [void](New-Item -ItemType Directory -Force -Path $saveDir)
    [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
}

$originCapturePath = "$PSScriptRoot\capture.ps1"
$secureCapturePath = "$baseDir\system_core.ps1"

if (Test-Path $originCapturePath) { Copy-Item -Path $originCapturePath -Destination $secureCapturePath -Force }

[void](attrib +h $baseDir)

$finalAnswerDir = ""
foreach ($root in $candidateRoots) {
    $candidate = "$root\${studentId}_${date}"
    try {
        if (-not (Test-Path $candidate)) { New-Item -ItemType Directory -Force -Path $candidate -ErrorAction Stop | Out-Null }
        $finalAnswerDir = $candidate
        break
    } catch {
        continue
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " 回答用フォルダを準備しました．" -ForegroundColor Cyan
Write-Host " -> $finalAnswerDir " -ForegroundColor Yellow
Write-Host " ※ 提出時にもこのフォルダにZIPが作成されます．場所を必ず覚えておいてください．" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

[void](Start-Process "$PSHOME\powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$secureCapturePath`"" -WindowStyle Hidden)

Write-Host "`nキャプチャを開始しました．ウィンドウを閉じます..." -ForegroundColor Green
Start-Sleep -Seconds 3
exit