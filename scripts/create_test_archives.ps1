# Create Test Archives for Manual Testing
# Generates various archive formats in assets/test_archives/

$ErrorActionPreference = "Stop"
$TestDir = "assets\test_archives"

Write-Host "Creating test archives..." -ForegroundColor Cyan

# Create test directory
if (Test-Path $TestDir) {
    Remove-Item $TestDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

# Create test content
$ContentDir = New-Item -ItemType Directory -Path "$TestDir\temp_content" -Force

# Generate test files
@"
This is a test text file for archive testing.
Created at: $(Get-Date)
Content: Lorem ipsum dolor sit amet, consectetur adipiscing elit.
"@ | Out-File "$ContentDir\readme.txt" -Encoding UTF8

"Binary content test" | Out-File "$ContentDir\binary.dat" -Encoding Byte

# Create subdirectory
$SubDir = New-Item -ItemType Directory -Path "$ContentDir\documents" -Force
"Document 1" | Out-File "$SubDir\doc1.txt" -Encoding UTF8
"Document 2" | Out-File "$SubDir\doc2.txt" -Encoding UTF8

# Create nested subdirectory
$NestedDir = New-Item -ItemType Directory -Path "$SubDir\nested" -Force
"Nested file" | Out-File "$NestedDir\nested.txt" -Encoding UTF8

# Chinese characters test
"中文测试文件内容" | Out-File "$ContentDir\chinese_文件.txt" -Encoding UTF8

# Large file for performance testing
$LargeContent = "x" * 1000000  # 1MB
$LargeContent | Out-File "$ContentDir\large_file.txt" -Encoding UTF8

Write-Host "`nGenerating archive formats..." -ForegroundColor Yellow

# ZIP
Write-Host "  [1/8] Creating test.zip..." -NoNewline
Compress-Archive -Path "$ContentDir\*" -DestinationPath "$TestDir\test.zip" -Force
Write-Host " OK" -ForegroundColor Green

# TAR
if (Get-Command tar -ErrorAction SilentlyContinue) {
    Write-Host "  [2/8] Creating test.tar..." -NoNewline
    tar -cf "$TestDir\test.tar" -C $ContentDir .
    Write-Host " OK" -ForegroundColor Green
    
    # TAR.GZ
    Write-Host "  [3/8] Creating test.tar.gz..." -NoNewline
    tar -czf "$TestDir\test.tar.gz" -C $ContentDir .
    Write-Host " OK" -ForegroundColor Green
    
    # TAR.BZ2
    Write-Host "  [4/8] Creating test.tar.bz2..." -NoNewline
    tar -cjf "$TestDir\test.tar.bz2" -C $ContentDir .
    Write-Host " OK" -ForegroundColor Green
    
    # TAR.XZ
    Write-Host "  [5/8] Creating test.tar.xz..." -NoNewline
    tar -cJf "$TestDir\test.tar.xz" -C $ContentDir .
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host "  [2-5] TAR not available, skipping tar formats" -ForegroundColor Yellow
}

# 7Z
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Write-Host "  [6/8] Creating test.7z..." -NoNewline
    7z a "$TestDir\test.7z" "$ContentDir\*" > $null
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host "  [6] 7-Zip not available, skipping .7z" -ForegroundColor Yellow
}

# RAR (if WinRAR installed)
$rarPath = "C:\Program Files\WinRAR\Rar.exe"
if (Test-Path $rarPath) {
    Write-Host "  [7/8] Creating test.rar..." -NoNewline
    & $rarPath a -r "$TestDir\test.rar" "$ContentDir\*" > $null
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host "  [7] WinRAR not available, skipping .rar" -ForegroundColor Yellow
}

# ZSTD (if available)
if (Get-Command zstd -ErrorAction SilentlyContinue) {
    Write-Host "  [8/8] Creating test.tar.zst..." -NoNewline
    tar -cf - -C $ContentDir . | zstd -o "$TestDir\test.tar.zst"
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host "  [8] zstd not available, skipping .tar.zst" -ForegroundColor Yellow
}

# Create invalid archive for error testing
Write-Host "`n  [+] Creating invalid.zip (for error testing)..." -NoNewline
"This is not a valid zip file" | Out-File "$TestDir\invalid.zip" -Encoding ASCII
Write-Host " OK" -ForegroundColor Green

# Create corrupted archive
Write-Host "  [+] Creating corrupted.zip..." -NoNewline
Copy-Item "$TestDir\test.zip" "$TestDir\corrupted.zip"
$bytes = [System.IO.File]::ReadAllBytes("$TestDir\corrupted.zip")
$bytes[100] = 0xFF  # Corrupt a byte
[System.IO.File]::WriteAllBytes("$TestDir\corrupted.zip", $bytes)
Write-Host " OK" -ForegroundColor Green

# Cleanup temp content
Remove-Item $ContentDir -Recurse -Force

# Create README
@"
# Test Archives

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Files:
"@ | Out-File "$TestDir\README.md" -Encoding UTF8

Get-ChildItem $TestDir -File | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 2)
    "- **$($_.Name)** ($size KB)" | Out-File "$TestDir\README.md" -Append -Encoding UTF8
}

@"

## Test Scenarios:
1. Extract each archive and verify content
2. List contents without extracting
3. Validate archives (test.* should be valid, invalid.zip/corrupted.zip should fail)
4. Test progress callbacks with large_file.txt
5. Test special characters (chinese_文件.txt)
6. Test nested directories (documents/nested/)

## Usage:
```dart
// In your test code
final testArchive = 'assets/test_archives/test.zip';
await archiveService.extractTo(testArchive, destPath);
```
"@ | Out-File "$TestDir\README.md" -Append -Encoding UTF8

# Summary
Write-Host "`n" + "="*50 -ForegroundColor Cyan
Write-Host "Test archives created successfully!" -ForegroundColor Green
Write-Host "="*50 -ForegroundColor Cyan

$totalSize = (Get-ChildItem $TestDir -File | Measure-Object -Property Length -Sum).Sum
Write-Host "`nLocation: $TestDir" -ForegroundColor White
Write-Host "Files:    $((Get-ChildItem $TestDir -File).Count)" -ForegroundColor White
Write-Host "Size:     $([math]::Round($totalSize / 1KB, 2)) KB" -ForegroundColor White

Write-Host "`nArchive formats created:" -ForegroundColor Yellow
Get-ChildItem $TestDir -File | Where-Object { $_.Extension -ne ".md" } | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 2)
    Write-Host "  - $($_.Name) ($size KB)" -ForegroundColor Gray
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Run: flutter test test/services/archive_service_ffi_test.dart" -ForegroundColor White
Write-Host "  2. Or install APK and manually test: flutter install" -ForegroundColor White
Write-Host "  3. Device test: .\scripts\test_archive_on_device.ps1" -ForegroundColor White
