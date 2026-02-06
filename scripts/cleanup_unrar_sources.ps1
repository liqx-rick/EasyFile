# UnRAR Source File Cleanup Script
# Remove unnecessary source files for Android to speed up compilation

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  UnRAR Source File Cleanup - Build Optimization" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$sourceDir = "native\src\unrar"
$backupDir = "native\src\unrar_unused"

# 确保备份目录存在
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
}

# 定义不需要的文件列表
$unnecessaryFiles = @(
    # Windows 专用文件（4个）
    "isnt.cpp",
    "win32acl.cpp",
    "win32lnk.cpp",
    "win32stm.cpp",

    # 控制台 UI 文件（3个）
    "uiconsole.cpp",
    "uisilent.cpp",
    "uicommon.cpp",

    # 旧版解压支持（5个）
    "unpack15.cpp",
    "unpack20.cpp",
    "unpack30.cpp",
    "unpackinline.cpp",

    # 恢复卷功能（3个 - NOVOLUME 已禁用）
    "recvol.cpp",
    "recvol3.cpp",
    "recvol5.cpp",

    # 冗余加密实现（保留 crypt5.cpp）
    "crypt1.cpp",
    "crypt2.cpp",
    "crypt3.cpp",

    # SSE 优化版本（移动设备不需要）
    "blake2s_sse.cpp",

    # 其他可选功能
    "cmdfilter.cpp",
    "hardlinks.cpp",
    "log.cpp",
    "arccmt.cpp",
    "model.cpp",
    "ulinks.cpp",
    "uowners.cpp",
    "coder.cpp",
    "rarpch.cpp",

    # Split volume (分卷) 相关
    "rs.cpp"
)

Write-Host "Moving unnecessary files to backup directory..." -ForegroundColor Yellow
Write-Host ""

$movedCount = 0
$notFoundCount = 0

foreach ($file in $unnecessaryFiles) {
    $sourcePath = Join-Path $sourceDir $file
    $backupPath = Join-Path $backupDir $file

    if (Test-Path $sourcePath) {
        try {
            Move-Item -Path $sourcePath -Destination $backupPath -Force
            Write-Host "  [OK] Moved: $file" -ForegroundColor Green
            $movedCount++
        } catch {
            Write-Host "  [ERROR] Failed: $file - $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [SKIP] Not found: $file" -ForegroundColor Gray
        $notFoundCount++
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete!" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Files moved: $movedCount" -ForegroundColor Green
Write-Host "Files not found: $notFoundCount" -ForegroundColor Gray

# Count remaining files
$remainingFiles = (Get-ChildItem "$sourceDir\*.cpp" | Measure-Object).Count
Write-Host "Remaining .cpp files: $remainingFiles" -ForegroundColor Yellow

Write-Host ""

# Show remaining core files
Write-Host "Remaining core files:" -ForegroundColor Cyan
$remaining = Get-ChildItem "$sourceDir\*.cpp" | Select-Object -ExpandProperty Name | Sort-Object
foreach ($file in $remaining) {
    Write-Host "  - $file" -ForegroundColor Gray
}
