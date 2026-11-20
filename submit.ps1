#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$baseDir = Join-Path $env:LOCALAPPDATA 'Microsoft\CaptureSystem'
$todayStr = Get-Date -Format 'yyyy_MM_dd'
$secureCapturePath = Join-Path $baseDir 'system_core.ps1'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "              提出準備                    " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# =========================================================
# 保存先の安全確認
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

# =========================================================
# キャプチャプロセス検索
# =========================================================
function Get-CaptureProcesses {
    param([string]$TargetPath)

    Get-CimInstance -ClassName Win32_Process `
        -Filter "Name = 'powershell.exe'" `
        -ErrorAction Stop |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf(
                $TargetPath,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        }
}

# =========================================================
# キャプチャプロセスの停止
# =========================================================
function Stop-CaptureProcess {
    param(
        [string]$TargetPath,
        [string]$SessionDir
    )

    $running = @(Get-CaptureProcesses -TargetPath $TargetPath)

    # start.ps1が記録したPIDも照合する
    $pidFile = Join-Path $SessionDir 'capture_pid.txt'

    if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
        $rawId = (
            Get-Content -LiteralPath $pidFile -Raw
        ).Trim()

        $captureProcessId = 0

        if ([int]::TryParse($rawId, [ref]$captureProcessId) -and
            $captureProcessId -gt 0) {

            $recordedProcess = Get-CimInstance `
                -ClassName Win32_Process `
                -Filter "ProcessId = $captureProcessId" `
                -ErrorAction Stop

            if ($recordedProcess) {
                if (-not $recordedProcess.CommandLine) {
                    throw 'キャプチャプロセスの識別情報を確認できません。'
                }

                if ($recordedProcess.CommandLine.IndexOf(
                    $TargetPath,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -ge 0) {
                    if (-not @(
                        $running |
                        Where-Object {
                            $_.ProcessId -eq $captureProcessId
                        }
                    ).Count) {
                        $running += $recordedProcess
                    }
                }
            }
        }
    }

    foreach ($process in $running) {
        Write-Host "[処理中] キャプチャを停止しています..." `
            -ForegroundColor Cyan

        $result = Invoke-CimMethod `
            -InputObject $process `
            -MethodName Terminate `
            -ErrorAction Stop

        if ($result.ReturnValue -ne 0) {
            throw "キャプチャの停止に失敗しました。PID: $($process.ProcessId)"
        }
    }

    # 停止を確認してから圧縮する
    for ($i = 0; $i -lt 20; $i++) {
        $remaining = @(
            Get-CaptureProcesses -TargetPath $TargetPath
        )

        if ($remaining.Count -eq 0) {
            return
        }

        Start-Sleep -Milliseconds 250
    }

    throw 'キャプチャプロセスが終了したことを確認できません。'
}

# =========================================================
# ZIPの内容を検査
# =========================================================
function Test-ZipArchive {
    param([string]$ZipPath)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

    try {
        $entries = @(
            $archive.Entries |
            Where-Object { $_.Name }
        )

        if ($entries.Count -eq 0) {
            return $false
        }

        $images = @(
            $entries |
            Where-Object {
                $_.FullName -match '(?i)\.(jpg|jpeg)$'
            }
        )

        return ($images.Count -gt 0)
    } finally {
        $archive.Dispose()
    }
}

# =========================================================
# 当日のキャプチャデータを取得
# =========================================================
if (-not (Test-Path -LiteralPath $baseDir -PathType Container)) {
    Write-Host "[エラー] キャプチャデータがありません。" `
        -ForegroundColor Red
    exit 1
}

$sessionDirs = @(
    Get-ChildItem -LiteralPath $baseDir -Directory -Force |
    Where-Object {
        $_.Name -match "^([0-9]{8})_($todayStr)$"
    }
)

if ($sessionDirs.Count -eq 0) {
    Write-Host "[エラー] 本日の学籍番号フォルダが見つかりません。" `
        -ForegroundColor Red
    exit 1
}

if ($sessionDirs.Count -gt 1) {
    Write-Host "[エラー] 本日の学籍番号フォルダが複数あります。" `
        -ForegroundColor Red
    Write-Host "誤提出を防ぐためTAに確認してください。" `
        -ForegroundColor Yellow
    exit 1
}

$saveDir = $sessionDirs[0].FullName
$studentId = $sessionDirs[0].Name.Substring(0, 8)

Write-Host "[確認] 学籍番号：$studentId" -ForegroundColor Cyan

# =========================================================
# ネットワーク警告状態を確認
# =========================================================
$sessionStatePath = Join-Path $saveDir 'session.dat'

if (Test-Path -LiteralPath $sessionStatePath -PathType Leaf) {
    Write-Host "==================================================" `
        -ForegroundColor Red
    Write-Host "[提出不可] インターネット接続の警告状態です。" `
        -ForegroundColor Red
    Write-Host "TAによる解除・確認が完了するまで提出できません。" `
        -ForegroundColor Yellow
    Write-Host "==================================================" `
        -ForegroundColor Red
    exit 1
}

# =========================================================
# start.ps1で決定した回答用フォルダを取得
# =========================================================
$answerPathFile = Join-Path $saveDir 'answer_dir.txt'

if (-not (Test-Path -LiteralPath $answerPathFile -PathType Leaf)) {
    Write-Host "[エラー] 回答用フォルダの記録がありません。" `
        -ForegroundColor Red
    Write-Host "キャプチャデータは削除しません。TAに申し出てください。" `
        -ForegroundColor Yellow
    exit 1
}

$answerDir = (
    Get-Content -LiteralPath $answerPathFile -Raw
).Trim()

$expectedName = "${studentId}_${todayStr}"
$normalizedAnswer = Normalize-Path $answerDir
$normalizedBase = Normalize-Path $baseDir

$invalidAnswer = $false

if ([string]::IsNullOrWhiteSpace($answerDir)) {
    $invalidAnswer = $true
} elseif (-not [System.IO.Path]::IsPathRooted($answerDir)) {
    $invalidAnswer = $true
} elseif ($answerDir.StartsWith('\\')) {
    $invalidAnswer = $true
} elseif (Test-IsOneDrivePath $answerDir) {
    $invalidAnswer = $true
} elseif ((Split-Path $answerDir -Leaf) -ne $expectedName) {
    $invalidAnswer = $true
} elseif (-not (Test-Path -LiteralPath $answerDir -PathType Container)) {
    $invalidAnswer = $true
} elseif ($normalizedAnswer.StartsWith(
    $normalizedBase + '\',
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    $invalidAnswer = $true
}

if ($invalidAnswer) {
    Write-Host "[エラー] 回答用フォルダの場所を確認できません。" `
        -ForegroundColor Red
    Write-Host "-> $answerDir" -ForegroundColor Yellow
    Write-Host "別の場所にZIPを勝手に保存しません。" `
        -ForegroundColor Yellow
    Write-Host "キャプチャデータを残して終了します。TAを呼んでください。" `
        -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] 回答用フォルダを確認しました。" `
    -ForegroundColor Green
Write-Host "-> $answerDir" -ForegroundColor Yellow

# =========================================================
# ZIP作成・配置（失敗時は古いZIPをロールバック）
# =========================================================
$timestamp = Get-Date -Format 'yyyy_MM_dd_HHmmss'
$zipName = "${studentId}_${timestamp}.zip"

# 一時作業場所は毎回専用フォルダにする（提出ZIP名に乱数は付けない）。
$tempWorkDir = Join-Path $env:TEMP (
    'CaptureSystemZip_' + [guid]::NewGuid().ToString('N')
)
$tempZip = Join-Path $tempWorkDir $zipName

# 作業用ファイルは .zip にしないため、フォルダ内のZIP数に含まれない。
$stageZip = Join-Path $answerDir (
    '.incoming_' + [guid]::NewGuid().ToString('N') + '.partial'
)
$finalZip = Join-Path $answerDir $zipName

$zipReady = $false
$newFinalPlaced = $false
$errorMessage = ''
$rollbackErrors = New-Object 'System.Collections.Generic.List[string]'
$backups = New-Object 'System.Collections.Generic.List[object]'
$oldZipCount = 0
$backupDir = Join-Path $env:LOCALAPPDATA (
    "Microsoft\CaptureSystemZipHistory\${studentId}_${todayStr}"
)

try {
    # 1. キャプチャを停止し、警告状態を再確認
    Stop-CaptureProcess `
        -TargetPath $secureCapturePath `
        -SessionDir $saveDir

    if (Test-Path -LiteralPath $sessionStatePath -PathType Leaf) {
        throw 'ネットワーク警告状態を検出しました。提出できません。'
    }

    # キャプチャ画像が1枚以上あることを確認
    $images = @(
        Get-ChildItem -LiteralPath $saveDir -File -Recurse -Force -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.jpg', '.jpeg') }
    )
    if ($images.Count -eq 0) {
        throw 'キャプチャ画像が1枚も見つかりません。'
    }

    # 2. 元データを専用の一時フォルダへZIP化
    New-Item -ItemType Directory -Path $tempWorkDir -ErrorAction Stop |
        Out-Null

    Write-Host '[処理中] キャプチャデータをZIPに圧縮しています...' `
        -ForegroundColor Cyan

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $saveDir,
        $tempZip,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    if (-not (Test-Path -LiteralPath $tempZip -PathType Leaf)) {
        throw 'ZIPファイルを作成できませんでした。'
    }
    if ((Get-Item -LiteralPath $tempZip -ErrorAction Stop).Length -le 0) {
        throw 'ZIPファイルのサイズが0バイトです。'
    }
    if (-not (Test-ZipArchive -ZipPath $tempZip)) {
        throw 'ZIP内のキャプチャ画像を確認できませんでした。'
    }

    # 3. 新しいZIPを仮ファイル名で配置し、コピー結果を検証
    Write-Host '[処理中] 新しいZIPを検証しています...' `
        -ForegroundColor Cyan

    Copy-Item -LiteralPath $tempZip -Destination $stageZip -ErrorAction Stop

    $sourceSize = (Get-Item -LiteralPath $tempZip -ErrorAction Stop).Length
    $stagedSize = (Get-Item -LiteralPath $stageZip -ErrorAction Stop).Length
    if ($sourceSize -ne $stagedSize) {
        throw 'ZIPコピー前後のファイルサイズが一致しません。'
    }

    $sourceHash = (Get-FileHash -LiteralPath $tempZip -Algorithm SHA256 `
        -ErrorAction Stop).Hash
    $stagedHash = (Get-FileHash -LiteralPath $stageZip -Algorithm SHA256 `
        -ErrorAction Stop).Hash
    if ($sourceHash -ne $stagedHash) {
        throw 'ZIPコピー前後のSHA-256が一致しません。'
    }
    if (-not (Test-ZipArchive -ZipPath $stageZip)) {
        throw 'コピー後のZIP内のキャプチャ画像を確認できませんでした。'
    }

    # 4. 既存ZIPをすべて退避先にコピーし、各ファイルのSHA-256を照合
    #    この段階では、古いZIPを提出用フォルダから消さない。
    $oldZips = @(
        Get-ChildItem -LiteralPath $answerDir -Filter '*.zip' `
            -File -Force -ErrorAction Stop
    )
    $oldZipCount = $oldZips.Count

    if ($oldZipCount -gt 0) {
        Write-Host "[処理中] 以前のZIP ${oldZipCount}個を安全に退避しています..." `
            -ForegroundColor Cyan

        New-Item -ItemType Directory -Path $backupDir -Force `
            -ErrorAction Stop | Out-Null

        foreach ($oldZip in $oldZips) {
            $backupPath = Join-Path $backupDir $oldZip.Name
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($oldZip.Name)
            $index = 1
            while (Test-Path -LiteralPath $backupPath) {
                $backupPath = Join-Path $backupDir (
                    '{0}_old{1:D2}.zip' -f $baseName, $index
                )
                $index++
            }

            # 中途半端なバックアップを完成ZIPとして残さない。
            $pendingBackup = Join-Path $backupDir (
                '.backup_' + [guid]::NewGuid().ToString('N') + '.partial'
            )
            try {
                Copy-Item -LiteralPath $oldZip.FullName `
                    -Destination $pendingBackup -ErrorAction Stop

                $oldSize = (Get-Item -LiteralPath $oldZip.FullName `
                    -ErrorAction Stop).Length
                $backupSize = (Get-Item -LiteralPath $pendingBackup `
                    -ErrorAction Stop).Length
                if ($oldSize -ne $backupSize) {
                    throw "古いZIPのバックアップサイズが一致しません: $($oldZip.Name)"
                }

                $oldHash = (Get-FileHash -LiteralPath $oldZip.FullName `
                    -Algorithm SHA256 -ErrorAction Stop).Hash
                $backupHash = (Get-FileHash -LiteralPath $pendingBackup `
                    -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($oldHash -ne $backupHash) {
                    throw "古いZIPのバックアップ検証に失敗しました: $($oldZip.Name)"
                }

                Move-Item -LiteralPath $pendingBackup `
                    -Destination $backupPath -ErrorAction Stop

                $backups.Add([pscustomobject]@{
                    Original = $oldZip.FullName
                    Backup   = $backupPath
                    Hash     = $oldHash
                })
            } finally {
                Remove-Item -LiteralPath $pendingBackup -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }

    # 5. 全バックアップの照合が済んだ場合だけ古いZIPを取り除く
    #    以降に失敗した場合は、バックアップから元の位置へ復元する。
    foreach ($oldZip in $oldZips) {
        Remove-Item -LiteralPath $oldZip.FullName `
            -Force -ErrorAction Stop
    }

    # 6. 仮ZIPを正式なファイル名で公開する
    Move-Item -LiteralPath $stageZip -Destination $finalZip `
        -ErrorAction Stop
    $newFinalPlaced = $true

    $finalHash = (Get-FileHash -LiteralPath $finalZip -Algorithm SHA256 `
        -ErrorAction Stop).Hash
    if ($finalHash -ne $sourceHash) {
        throw '正式配置後のZIPのSHA-256が一致しません。'
    }
    if (-not (Test-ZipArchive -ZipPath $finalZip)) {
        throw '正式配置後のZIP内のキャプチャ画像を確認できませんでした。'
    }

    # 隠しZIPも含めて、提出用フォルダにZIPが1つだけあることを確認
    $remainingZips = @(
        Get-ChildItem -LiteralPath $answerDir -Filter '*.zip' `
            -File -Force -ErrorAction Stop
    )
    if ($remainingZips.Count -ne 1 -or
        $remainingZips[0].FullName -ne $finalZip) {
        throw '提出用フォルダ内のZIPが1つになっていません。'
    }

    $zipReady = $true
    if ($oldZipCount -gt 0) {
        Write-Host '[OK] 古いZIPを検証済みのバックアップへ退避しました。' `
            -ForegroundColor Green
        Write-Host "-> $backupDir" -ForegroundColor Yellow
    }
    Write-Host '[OK] 提出用フォルダ内のZIPは最新の1つだけです。' `
        -ForegroundColor Green

} catch {
    $errorMessage = $_.Exception.Message

    # 7. 失敗時ロールバック
    #    新しく公開したZIPだけを消し、古いZIPを退避先から復元する。
    if ($newFinalPlaced) {
        try {
            Remove-Item -LiteralPath $finalZip -Force -ErrorAction Stop
        } catch {
            $rollbackErrors.Add(
                "新しいZIPを取り除けません: $($_.Exception.Message)"
            )
        }
    }

    foreach ($entry in $backups) {
        try {
            if (-not (Test-Path -LiteralPath $entry.Original -PathType Leaf)) {
                Copy-Item -LiteralPath $entry.Backup `
                    -Destination $entry.Original -ErrorAction Stop
            }

            $restoredHash = (Get-FileHash -LiteralPath $entry.Original `
                -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($restoredHash -ne $entry.Hash) {
                throw "復元したZIPのSHA-256が一致しません: $($entry.Original)"
            }
        } catch {
            $rollbackErrors.Add(
                "古いZIPを復元できません: $($entry.Original) / $($_.Exception.Message)"
            )
        }
    }

} finally {
    # 使いかけの仮ファイルを提出フォルダに残さない。
    Remove-Item -LiteralPath $stageZip -Force -ErrorAction SilentlyContinue

    # 成功した場合だけ一時ZIPと作業フォルダを削除。
    # 失敗時には診断・手動復旧用に残す。
    if ($zipReady) {
        Remove-Item -LiteralPath $tempWorkDir -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

# =========================================================
# 失敗時：元キャプチャデータを保持する
# =========================================================
if (-not $zipReady) {
    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Red
    Write-Host '[提出失敗] ZIPの作成・配置に失敗しました。' -ForegroundColor Red
    Write-Host "原因: $errorMessage" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '元のキャプチャデータは削除していません。' -ForegroundColor Green
    Write-Host "-> $saveDir" -ForegroundColor Yellow

    if (Test-Path -LiteralPath $tempZip -PathType Leaf) {
        Write-Host '新規作成した一時ZIPも残しています。' -ForegroundColor Yellow
        Write-Host "-> $tempZip" -ForegroundColor Yellow
    }
    if ($backups.Count -gt 0) {
        Write-Host '以前のZIPの検証済みバックアップ:' -ForegroundColor Yellow
        Write-Host "-> $backupDir" -ForegroundColor Yellow
    }
    if ($rollbackErrors.Count -gt 0) {
        Write-Host '[重要] 古いZIPを完全には元に戻せませんでした。' -ForegroundColor Red
        foreach ($detail in $rollbackErrors) {
            Write-Host "  $detail" -ForegroundColor Red
        }
    } else {
        Write-Host '[復旧] 以前のZIPは元の位置に保持・復元しました。' `
            -ForegroundColor Green
    }

    Write-Host 'TAに申し出てください。' -ForegroundColor Yellow
    Write-Host '==================================================' -ForegroundColor Red
    exit 1
}

# =========================================================
# ZIP正常配置後：今回のキャプチャデータのみ削除
# =========================================================
Write-Host "[OK] ZIPの正常配置を確認しました。" `
    -ForegroundColor Green

$cleanupSucceeded = $true

try {
    Remove-Item -LiteralPath $saveDir `
        -Recurse -Force -ErrorAction Stop

    Write-Host "[OK] 今回のキャプチャデータを整理しました。" `
        -ForegroundColor Green
} catch {
    $cleanupSucceeded = $false

    Write-Host "[注意] 元データの一部または全部が残っています。" `
        -ForegroundColor Yellow
    Write-Host "ZIPは配置済みです。残存データはTAに確認してください。" `
        -ForegroundColor Yellow
}

# =========================================================
# 最終案内
# =========================================================
Write-Host ""
Write-Host "==========================================" `
    -ForegroundColor Green
Write-Host "          提出用ZIP作成完了              " `
    -ForegroundColor Green
Write-Host "==========================================" `
    -ForegroundColor Green
Write-Host ""
Write-Host "ZIPファイル：" -ForegroundColor Cyan
Write-Host "-> $finalZip" -ForegroundColor Yellow
Write-Host ""
Write-Host "【提出方法】" -ForegroundColor Cyan
Write-Host "1. 回答用フォルダに提出するファイルを保存してください。"
Write-Host "2. ZIPと提出するファイルが入っていることを確認してください。"
Write-Host "3. 回答用フォルダごとUSBメモリにコピーしてください。"
Write-Host "4. USBメモリをTAに提出してください。"
Write-Host ""

if (-not $cleanupSucceeded) {
    Write-Host "[注意] 元キャプチャデータの整理は未完了です。" `
        -ForegroundColor Yellow
}

Write-Host "==========================================" `
    -ForegroundColor Green

exit 0