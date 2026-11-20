#requires -Version 5.1
$ErrorActionPreference = 'Stop'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       画面キャプチャ システム起動       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$baseDir = Join-Path $env:LOCALAPPDATA 'Microsoft\CaptureSystem'
$todayStr = Get-Date -Format 'yyyy_MM_dd'

$studentId = ''
$saveDir = ''
$answerDir = ''
$pendingRestoreZip = ''
$answerPathProblem = $false

# =========================================================
# インターネット接続確認
# =========================================================
function Test-InternetConnectivity {
    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        return $false
    }

    try {
        $profile = Get-NetConnectionProfile -ErrorAction Stop |
            Where-Object {
                $_.IPv4Connectivity -eq 'Internet' -or
                $_.IPv6Connectivity -eq 'Internet'
            }
        if ($profile) { return $true }
    } catch {}

    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($route -and $route.NextHop) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            try {
                $reply = $ping.Send($route.NextHop, 1000)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    return $true
                }
            } finally {
                $ping.Dispose()
            }
        }
    } catch {}

    return $false
}

# =========================================================
# OneDrive判定
# =========================================================
function Normalize-Path {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Test-IsOneDrivePath {
    param([string]$Path)

    $candidate = Normalize-Path $Path
    if (-not $candidate) { return $false }

    foreach ($od in @(
        $env:OneDrive,
        $env:OneDriveCommercial,
        $env:OneDriveConsumer
    )) {
        $root = Normalize-Path $od
        if (-not $root) { continue }

        if ($candidate.Equals(
            $root,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }

        if ($candidate.StartsWith(
            $root + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }

    return ($candidate -match '(?i)(^|\\)OneDrive(?:\s*-\s*[^\\]+)?(\\|$)')
}

function Test-SafeLocalPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        return $false
    }

    if ($Path.StartsWith('\\')) {
        return $false
    }

    if (Test-IsOneDrivePath $Path) {
        return $false
    }

    return $true
}

# =========================================================
# 回答用フォルダの候補
# =========================================================
function Get-CandidateAnswerRoots {
    $roots = @()

    $shellDesktop = [Environment]::GetFolderPath('Desktop')
    $shellDesktopIsOneDrive = Test-IsOneDrivePath $shellDesktop

    if (Test-SafeLocalPath $shellDesktop) {
        $roots += $shellDesktop
    }

    # DesktopがOneDriveに移動している場合は、
    # USERPROFILE\Desktopも使用しない。
    if (-not $shellDesktopIsOneDrive) {
        $trueDesktop = Join-Path $env:USERPROFILE 'Desktop'

        if (Test-SafeLocalPath $trueDesktop) {
            $roots += $trueDesktop
        }
    }

    # Windowsに登録された実際のダウンロードフォルダを取得
    $downloads = Join-Path $env:USERPROFILE 'Downloads'

    try {
        $reg = Get-ItemProperty -Path `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' `
            -Name '{374DE290-123F-4565-9164-39C4925E467B}' `
            -ErrorAction Stop

        $registeredDownloads = [string]$reg.'{374DE290-123F-4565-9164-39C4925E467B}'

        if ($registeredDownloads) {
            $downloads = [Environment]::ExpandEnvironmentVariables(
                $registeredDownloads
            )
        }
    } catch {}

    if (Test-SafeLocalPath $downloads) {
        $roots += $downloads
    }

    $roots += 'C:\ExamSystem'

    # 標準ユーザー権限でも利用しやすい最終候補
    $roots += (Join-Path $env:LOCALAPPDATA 'Microsoft\CaptureAnswers')

    $roots |
        Where-Object { Test-SafeLocalPath $_ } |
        Select-Object -Unique
}

function Test-WritableFolder {
    param([string]$Path)

    if (-not (Test-SafeLocalPath $Path)) {
        return $false
    }

    $probe = Join-Path $Path (
        '.wtest_' + [guid]::NewGuid().ToString('N')
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop |
                Out-Null
        }

        [System.IO.File]::WriteAllText($probe, 'OK')
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}

# =========================================================
# 以前作成された当日ZIPの検索
# =========================================================
function Find-ResumeZips {
    param(
        [string[]]$Roots,
        [string]$TodayStr
    )

    foreach ($root in $Roots) {
        try {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                continue
            }

            $dirs = Get-ChildItem -LiteralPath $root `
                -Directory -Force -ErrorAction Stop |
                Where-Object {
                    $_.Name -match "^([0-9]{8})_($TodayStr)$"
                }

            foreach ($dir in $dirs) {
                $sid = $dir.Name.Substring(0, 8)

                $zips = Get-ChildItem -LiteralPath $dir.FullName `
                    -Filter "${sid}_${TodayStr}_*.zip" `
                    -File -Force -ErrorAction SilentlyContinue

                foreach ($zip in $zips) {
                    [pscustomobject]@{
                        StudentId = $sid
                        ZipPath   = $zip.FullName
                        AnswerDir = $dir.FullName
                        Updated   = $zip.LastWriteTime
                    }
                }
            }
        } catch {
            continue
        }
    }
}

# =========================================================
# キャプチャプロセス検索
# =========================================================
function Get-CaptureProcesses {
    param([string]$TargetPath)

    Get-CimInstance -ClassName Win32_Process `
        -Filter "Name = 'powershell.exe'" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf(
                $TargetPath,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        }
}

# =========================================================
# オフライン確認
# =========================================================
Write-Host "`n[準備] ネットワーク接続状態を確認しています..." `
    -ForegroundColor Cyan

while ($true) {
    if (Test-InternetConnectivity) {
        Write-Host "`n==========================================" `
            -ForegroundColor Red
        Write-Host "【警告】インターネット接続が検出されました！" `
            -ForegroundColor Red
        Write-Host "==========================================" `
            -ForegroundColor Red
        Write-Host "PCを完全にオフラインにしてください。" `
            -ForegroundColor Yellow
        Write-Host "Wi-Fiを切断し、Enterキーを押してください。" `
            -ForegroundColor Cyan

        Read-Host | Out-Null
    } else {
        Write-Host "[OK] オフライン環境を確認しました。`n" `
            -ForegroundColor Green
        break
    }
}

$candidateRoots = @(Get-CandidateAnswerRoots)

# =========================================================
# 当日のキャプチャデータを確認
# 過去日付のデータは削除しない
# =========================================================
$todaySessions = @()

if (Test-Path -LiteralPath $baseDir -PathType Container) {
    $todaySessions = @(
        Get-ChildItem -LiteralPath $baseDir -Directory -Force `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match "^([0-9]{8})_($todayStr)$"
        }
    )
}

if ($todaySessions.Count -gt 1) {
    Write-Host "[エラー] 本日の学籍番号フォルダが複数あります。" `
        -ForegroundColor Red
    Write-Host "誤った学生のデータを使用しないため、TAに確認してください。" `
        -ForegroundColor Yellow
    exit 1
}

if ($todaySessions.Count -eq 1) {
    $studentId = $todaySessions[0].Name.Substring(0, 8)
    $saveDir = $todaySessions[0].FullName

    Write-Host "[検知] 本日のキャプチャデータが見つかりました。" `
        -ForegroundColor Green
    Write-Host "既存データを引き継いで再開します。" `
        -ForegroundColor Green

    if (Test-Path -LiteralPath (Join-Path $saveDir 'session.dat')) {
        Write-Host "[開始不可] ネットワーク警告状態が残っています。" `
            -ForegroundColor Red
        Write-Host "TAによる解除・確認を受けてください。" `
            -ForegroundColor Yellow
        exit 1
    }
}

# =========================================================
# ローカルデータがなければ当日のZIPを検索
# =========================================================
if (-not $studentId) {
    Write-Host "[処理中] 当日の未復元ZIPを確認しています..." `
        -ForegroundColor Cyan

    $resumeCandidates = @(
        Find-ResumeZips -Roots $candidateRoots -TodayStr $todayStr
    )

    if ($resumeCandidates.Count -gt 0) {
        $uniqueIds = @(
            $resumeCandidates |
                Select-Object -ExpandProperty StudentId -Unique
        )

        if ($uniqueIds.Count -gt 1) {
            Write-Host "[エラー] 複数の学籍番号のZIPが見つかりました。" `
                -ForegroundColor Red
            Write-Host "誤復元を防ぐためTAに確認してください。" `
                -ForegroundColor Yellow
            exit 1
        }

        $found = $resumeCandidates |
            Sort-Object Updated -Descending |
            Select-Object -First 1

        $studentId = $found.StudentId
        $pendingRestoreZip = $found.ZipPath
        $answerDir = $found.AnswerDir

        Write-Host "[検知] ZIPを発見しました。画像を復元します。" `
            -ForegroundColor Green
    }
}

# =========================================================
# 学籍番号入力
# =========================================================
if (-not $studentId) {
    while ($studentId -notmatch '^[0-9]{8}$') {
        $studentId = Read-Host '学籍番号を入力してください（半角数字8桁）'

        if ($studentId -notmatch '^[0-9]{8}$') {
            Write-Host "エラー：学籍番号は半角数字8桁です。" `
                -ForegroundColor Red
        }
    }
}

if (-not $saveDir) {
    $saveDir = Join-Path $baseDir "${studentId}_${todayStr}"
}

if (-not (Test-Path -LiteralPath $saveDir -PathType Container)) {
    New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
}

# =========================================================
# 回答用フォルダの決定
# =========================================================
$answerPathFile = Join-Path $saveDir 'answer_dir.txt'
$expectedFolderName = "${studentId}_${todayStr}"

# 再開時は前回の保存先を優先
if (-not $answerDir -and
    (Test-Path -LiteralPath $answerPathFile -PathType Leaf)) {

    $recordedPath = (
        Get-Content -LiteralPath $answerPathFile -Raw
    ).Trim()

    if ($recordedPath -and
        (Test-SafeLocalPath $recordedPath) -and
        ((Split-Path $recordedPath -Leaf) -eq $expectedFolderName) -and
        (Test-Path -LiteralPath $recordedPath -PathType Container) -and
        (Test-WritableFolder $recordedPath)) {

        $answerDir = $recordedPath
    } else {
        $answerPathProblem = $true

        Write-Host "[警告] 前回の回答用フォルダを利用できません。" `
            -ForegroundColor Red
        Write-Host "保存先を勝手に変更しないため、TAに確認してください。" `
            -ForegroundColor Yellow
    }
}

# 既存の回答用フォルダを優先して探す
if (-not $answerDir -and -not $answerPathProblem) {
    foreach ($root in $candidateRoots) {
        $candidate = Join-Path $root $expectedFolderName

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            if (Test-WritableFolder $candidate) {
                $answerDir = $candidate
            } else {
                $answerPathProblem = $true

                Write-Host "[警告] 既存の回答用フォルダに書き込めません。" `
                    -ForegroundColor Red
                Write-Host "-> $candidate" -ForegroundColor Yellow
            }

            break
        }
    }
}

# 新規作成
if (-not $answerDir -and -not $answerPathProblem) {
    foreach ($root in $candidateRoots) {
        $candidate = Join-Path $root $expectedFolderName

        if (Test-WritableFolder $candidate) {
            $answerDir = $candidate
            break
        }
    }
}

# ZIPから復元する場合も、提出先は元のフォルダを使用
if ($answerDir -and -not (Test-WritableFolder $answerDir)) {
    Write-Host "[警告] 回答用フォルダに書き込めません。" `
        -ForegroundColor Red
    $answerDir = ''
}

if ($answerDir) {
    Set-Content -LiteralPath $answerPathFile `
        -Value $answerDir -Encoding UTF8

    Write-Host "`n==========================================" `
        -ForegroundColor Cyan
    Write-Host "回答用フォルダを準備しました。" -ForegroundColor Green
    Write-Host "-> $answerDir" -ForegroundColor Yellow
    Write-Host "CPPファイルはこのフォルダに保存してください。" `
        -ForegroundColor Yellow
    Write-Host "提出時にZIPもこのフォルダへ自動配置されます。" `
        -ForegroundColor Yellow
    Write-Host "==========================================" `
        -ForegroundColor Cyan
} else {
    Write-Host "[警告] 回答用フォルダを準備できませんでした。" `
        -ForegroundColor Red
    Write-Host "試験は続行できますが、提出前にTAへ申し出てください。" `
        -ForegroundColor Yellow
}

# =========================================================
# ZIPからのキャプチャデータ復元
# 成功・失敗にかかわらず元ZIPは消さない
# =========================================================
if ($pendingRestoreZip) {
    Write-Host "[処理中] 過去のZIPから画像を復元しています..." `
        -ForegroundColor Cyan

    $tempExtract = Join-Path $env:TEMP (
        'CaptureRestore_' + [guid]::NewGuid().ToString('N')
    )

    try {
        New-Item -ItemType Directory -Path $tempExtract -Force |
            Out-Null

        Expand-Archive -LiteralPath $pendingRestoreZip `
            -DestinationPath $tempExtract -Force -ErrorAction Stop

        Get-ChildItem -LiteralPath $tempExtract -Force |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName `
                    -Destination $saveDir `
                    -Recurse -Force -ErrorAction Stop
            }

        Write-Host "[復元] ZIPからデータを復元しました。" `
            -ForegroundColor Green
        Write-Host "安全のため、元のZIPも残しています。" `
            -ForegroundColor Yellow
    } catch {
        Write-Host "[警告] ZIPからの復元に失敗しました。" `
            -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "元ZIPは削除していません。TAに報告してください。" `
            -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $tempExtract `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ZIPから復元した古い情報よりも、今回決定した保存先を優先
Set-Content -LiteralPath (Join-Path $saveDir 'student_id.txt') `
    -Value $studentId -Encoding UTF8

if ($answerDir) {
    Set-Content -LiteralPath $answerPathFile `
        -Value $answerDir -Encoding UTF8
}

# =========================================================
# キャプチャプログラムの起動
# 必ずローカルにコピーしたsystem_core.ps1を起動する
# =========================================================
$originCapturePath = Join-Path $PSScriptRoot 'capture.ps1'
$secureCapturePath = Join-Path $baseDir 'system_core.ps1'
$pidFile = Join-Path $saveDir 'capture_pid.txt'

$running = @(
    Get-CaptureProcesses -TargetPath $secureCapturePath
)

if ($running.Count -gt 0) {
    Write-Host "[検知] キャプチャはすでに動作しています。" `
        -ForegroundColor Green

    Set-Content -LiteralPath $pidFile `
        -Value $running[0].ProcessId -Encoding ASCII
} else {
    if (-not (Test-Path -LiteralPath $originCapturePath -PathType Leaf)) {
        Write-Host "[エラー] capture.ps1が見つかりません。" `
            -ForegroundColor Red
        Write-Host "-> $originCapturePath" -ForegroundColor Yellow
        exit 1
    }

    try {
        Copy-Item -LiteralPath $originCapturePath `
            -Destination $secureCapturePath `
            -Force -ErrorAction Stop

        $arguments = '-NoProfile -ExecutionPolicy Bypass ' +
                     '-WindowStyle Hidden -File "' +
                     $secureCapturePath + '"'

        $captureProcess = Start-Process `
            -FilePath (Join-Path $PSHOME 'powershell.exe') `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -PassThru -ErrorAction Stop

        Set-Content -LiteralPath $pidFile `
            -Value $captureProcess.Id -Encoding ASCII

        Write-Host "[OK] キャプチャを開始しました。" `
            -ForegroundColor Green
    } catch {
        Write-Host "[エラー] キャプチャの起動に失敗しました。" `
            -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 1
    }
}

try {
    attrib +h $baseDir | Out-Null
} catch {}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "画面キャプチャシステムを起動しました。" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

Start-Sleep -Seconds 3
exit 0