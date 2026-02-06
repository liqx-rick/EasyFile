# Restore UnRAR include files that are required by unity build
$unrarDir = "C:\dev\flutter\easyfile\native\src\unrar"
$unusedDir = "C:\dev\flutter\easyfile\native\src\unrar_unused"

# Files that are included by other cpp files (not compiled directly)
$includeFiles = @(
    "arccmt.cpp",
    "blake2s_sse.cpp",
    "cmdfilter.cpp",
    "coder.cpp",
    "crypt1.cpp",
    "crypt2.cpp",
    "crypt3.cpp",
    "hardlinks.cpp",
    "log.cpp",
    "model.cpp",
    "uicommon.cpp",
    "uiconsole.cpp",
    "uisilent.cpp",
    "ulinks.cpp",
    "unpack15.cpp",
    "unpack20.cpp",
    "unpack30.cpp",
    "unpackinline.cpp",
    "uowners.cpp",
    "win32acl.cpp",
    "win32lnk.cpp",
    "win32stm.cpp"
)

Write-Host "Restoring UnRAR include files..."
$restored = 0

foreach ($file in $includeFiles) {
    $sourcePath = Join-Path $unusedDir $file
    $destPath = Join-Path $unrarDir $file

    if (Test-Path $sourcePath) {
        Move-Item -Path $sourcePath -Destination $destPath -Force
        Write-Host "✓ Restored: $file"
        $restored++
    } else {
        Write-Host "✗ Not found: $file"
    }
}

Write-Host "`nRestored $restored files."
