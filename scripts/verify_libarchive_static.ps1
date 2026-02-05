# Verify libarchive Static Linking
# Checks if libarchive.so is properly statically linked

$ErrorActionPreference = "Stop"

$NDK = $env:ANDROID_NDK_HOME
if (-not $NDK) {
    $NDK = "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk\ndk\27.0.12077973"
}

if (-not (Test-Path $NDK)) {
    Write-Host "ERROR: Android NDK not found at $NDK" -ForegroundColor Red
    exit 1
}

$READELF = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"
$NM = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"

Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     libarchive Static Linking Verification              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$allGood = $true

foreach ($abi in @("arm64-v8a")) {
    $lib = "android\src\main\jniLibs\$abi\libarchive.so"
    
    Write-Host "`n" -NoNewline
    Write-Host "="*60 -ForegroundColor Yellow
    Write-Host "  Checking $abi" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Yellow
    
    if (-not (Test-Path $lib)) {
        Write-Host "  ✗ File not found: $lib" -ForegroundColor Red
        $allGood = $false
        continue
    }
    
    # Check size
    $size = [math]::Round((Get-Item $lib).Length / 1MB, 2)
    Write-Host "`n  File Size: $size MB" -ForegroundColor White
    
    if ($size -lt 5.0) {
        Write-Host "  ⚠️  Warning: Size seems small for static linking (expected 5-8 MB)" -ForegroundColor Yellow
    }
    
    # Check dynamic dependencies
    Write-Host "`n  Dynamic Dependencies:" -ForegroundColor White
    $deps = & $READELF -d $lib 2>$null | Select-String "NEEDED"
    
    if (-not $deps) {
        Write-Host "    ✗ Could not read dependencies" -ForegroundColor Red
        $allGood = $false
        continue
    }
    
    $hasBadDeps = $false
    foreach ($dep in $deps) {
        $depName = ($dep -replace '.*\[(.*?)\].*', '$1').Trim()
        
        if ($depName -match "bz2|lzma|lz4|zstd") {
            Write-Host "    ✗ $depName (should be statically linked!)" -ForegroundColor Red
            $hasBadDeps = $true
        } else {
            Write-Host "    ✓ $depName" -ForegroundColor Green
        }
    }
    
    # Check symbols
    Write-Host "`n  Symbol Verification:" -ForegroundColor White
    
    $checkSymbols = @(
        "archive_write_disk_new",
        "archive_write_disk_set_options",
        "archive_read_extract",
        "archive_read_new"
    )
    
    foreach ($sym in $checkSymbols) {
        $found = & $NM $lib 2>$null | Select-String $sym
        if ($found) {
            Write-Host "    ✓ $sym" -ForegroundColor Green
        } else {
            Write-Host "    ✗ $sym (missing)" -ForegroundColor Red
            $allGood = $false
        }
    }
    
    # Final verdict for this ABI
    Write-Host "`n  Result:" -ForegroundColor White
    if ($hasBadDeps) {
        Write-Host "    ✗ NOT statically linked - has external dependencies" -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host "    ✓ Properly statically linked" -ForegroundColor Green
    }
}

Write-Host "`n" -NoNewline
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "  Final Result" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

if ($allGood) {
    Write-Host "`n  🎉 All checks passed!" -ForegroundColor Green
    Write-Host "  libarchive is properly statically linked for all ABIs." -ForegroundColor Green
    Write-Host "`n  You can now build and test the app:" -ForegroundColor White
    Write-Host "    flutter build apk --debug" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "`n  ⚠️  Issues detected!" -ForegroundColor Red
    Write-Host "  Please recompile libarchive with static linking." -ForegroundColor Red
    Write-Host "`n  See: docs\LIBARCHIVE_STATIC_BUILD_GUIDE.md" -ForegroundColor Yellow
    exit 1
}
