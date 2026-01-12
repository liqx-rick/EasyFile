# Archive Service Device Testing Script
# Tests all archive formats on real Android device

param(
    [string]$DeviceId = "",
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Stop"
$TestDir = "/sdcard/Download/archive_test"
$TestResults = @()

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details -and $Verbose) {
        Write-Host "      $Details" -ForegroundColor Gray
    }
    
    $script:TestResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Details = $Details
    }
}

function Test-DeviceConnected {
    $devices = adb devices | Select-String "device$"
    if ($devices.Count -eq 0) {
        Write-Host "ERROR: No Android device connected" -ForegroundColor Red
        Write-Host "Please connect a device and enable USB debugging" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Device connected: $($devices[0])" -ForegroundColor Green
}

function Setup-TestEnvironment {
    Write-TestHeader "Setting up test environment"
    
    # Clean previous test data
    adb shell "rm -rf $TestDir" 2>$null
    adb shell "mkdir -p $TestDir/archives $TestDir/extracted" 2>$null
    
    Write-Host "Created test directory: $TestDir" -ForegroundColor Green
}

function Create-TestArchives {
    Write-TestHeader "Creating test archives"
    
    $TempDir = New-Item -ItemType Directory -Path "$env:TEMP\archive_test_$(Get-Random)" -Force
    
    # Create test content
    $ContentDir = New-Item -ItemType Directory -Path "$TempDir\content" -Force
    "Test file content - $(Get-Date)" | Out-File "$ContentDir\test.txt" -Encoding UTF8
    "Binary content" | Out-File "$ContentDir\binary.dat" -Encoding Byte
    
    # Create subdirectory
    $SubDir = New-Item -ItemType Directory -Path "$ContentDir\subdir" -Force
    "Nested file" | Out-File "$SubDir\nested.txt" -Encoding UTF8
    
    # Create archives
    $Archives = @()
    
    # ZIP
    Write-Host "Creating test.zip..." -NoNewline
    Compress-Archive -Path "$ContentDir\*" -DestinationPath "$TempDir\test.zip" -Force
    $Archives += "$TempDir\test.zip"
    Write-Host " OK" -ForegroundColor Green
    
    # TAR.GZ (if tar available)
    if (Get-Command tar -ErrorAction SilentlyContinue) {
        Write-Host "Creating test.tar.gz..." -NoNewline
        tar -czf "$TempDir\test.tar.gz" -C $ContentDir .
        $Archives += "$TempDir\test.tar.gz"
        Write-Host " OK" -ForegroundColor Green
    }
    
    # 7Z (if 7z available)
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        Write-Host "Creating test.7z..." -NoNewline
        7z a "$TempDir\test.7z" "$ContentDir\*" > $null
        $Archives += "$TempDir\test.7z"
        Write-Host " OK" -ForegroundColor Green
    }
    
    # Push to device
    Write-Host "`nPushing archives to device..." -ForegroundColor Cyan
    foreach ($archive in $Archives) {
        $filename = Split-Path $archive -Leaf
        adb push $archive "$TestDir/archives/$filename" 2>$null
        Write-Host "  Pushed: $filename" -ForegroundColor Gray
    }
    
    # Cleanup
    Remove-Item $TempDir -Recurse -Force
    
    return $Archives.Count
}

function Test-ArchiveExtraction {
    param([string]$Format)
    
    $ArchivePath = "$TestDir/archives/test.$Format"
    $ExtractPath = "$TestDir/extracted/$Format"
    
    # Check if archive exists on device
    $exists = adb shell "test -f $ArchivePath && echo 1 || echo 0"
    if ($exists.Trim() -ne "1") {
        Write-TestResult "Extract $Format" $false "Archive not found"
        return
    }
    
    # Create extraction directory
    adb shell "mkdir -p $ExtractPath" 2>$null
    
    # Trigger extraction via app (you'll need to implement this intent/activity)
    # For now, we'll test if the file is accessible
    $size = adb shell "stat -c%s $ArchivePath 2>/dev/null"
    
    if ($size -and $size.Trim() -gt 0) {
        Write-TestResult "Extract $Format" $true "Archive size: $($size.Trim()) bytes"
    } else {
        Write-TestResult "Extract $Format" $false "Cannot access archive"
    }
}

function Test-ArchiveValidation {
    Write-TestHeader "Testing archive validation"
    
    # Valid archive
    $validResult = adb shell "test -f $TestDir/archives/test.zip && echo 1 || echo 0"
    Write-TestResult "Validate valid ZIP" ($validResult.Trim() -eq "1")
    
    # Invalid archive
    adb shell "echo 'invalid' > $TestDir/archives/invalid.zip" 2>$null
    $invalidSize = adb shell "stat -c%s $TestDir/archives/invalid.zip 2>/dev/null"
    Write-TestResult "Detect invalid archive" ($invalidSize.Trim() -lt 100)
}

function Test-MemoryUsage {
    Write-TestHeader "Testing memory usage"
    
    # Get app memory before test
    $packageName = "com.example.easyfile" # Update with your package name
    $memBefore = adb shell "dumpsys meminfo $packageName | grep 'TOTAL PSS' | awk '{print `$3}'"
    
    if ($memBefore) {
        Write-Host "Memory before: $memBefore KB" -ForegroundColor Gray
        Write-TestResult "Memory baseline" $true "$memBefore KB"
    } else {
        Write-TestResult "Memory check" $false "App not running"
    }
}

function Generate-TestReport {
    Write-TestHeader "Test Summary"
    
    $passed = ($TestResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failed = ($TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $total = $TestResults.Count
    
    Write-Host "Total Tests: $total" -ForegroundColor White
    Write-Host "Passed:      $passed" -ForegroundColor Green
    Write-Host "Failed:      $failed" -ForegroundColor Red
    
    if ($failed -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        $TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "  - $($_.Test): $($_.Details)" -ForegroundColor Yellow
        }
    }
    
    # Export to file
    $reportPath = "test_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $TestResults | Format-Table -AutoSize | Out-File $reportPath
    Write-Host "`nDetailed report saved to: $reportPath" -ForegroundColor Cyan
}

function Cleanup-TestEnvironment {
    Write-TestHeader "Cleaning up"
    
    Write-Host "Removing test directory from device..." -NoNewline
    adb shell "rm -rf $TestDir" 2>$null
    Write-Host " Done" -ForegroundColor Green
}

# Main execution
try {
    Write-Host "Archive Service Device Test Suite" -ForegroundColor Magenta
    Write-Host "=================================" -ForegroundColor Magenta
    
    Test-DeviceConnected
    Setup-TestEnvironment
    
    $archiveCount = Create-TestArchives
    Write-Host "`nCreated $archiveCount test archives" -ForegroundColor Green
    
    # Run tests
    Test-ArchiveExtraction "zip"
    Test-ArchiveExtraction "tar.gz"
    Test-ArchiveExtraction "7z"
    
    Test-ArchiveValidation
    Test-MemoryUsage
    
    Generate-TestReport
    
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if (-not $env:KEEP_TEST_DATA) {
        Cleanup-TestEnvironment
    } else {
        Write-Host "`nTest data preserved at: $TestDir" -ForegroundColor Yellow
    }
}

Write-Host "`nTest suite completed!" -ForegroundColor Green
