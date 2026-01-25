# Run All Archive FFI Tests
# Comprehensive test suite runner for FFI migration verification

param(
    [switch]$CreateArchives,
    [switch]$UnitTests,
    [switch]$DeviceTests,
    [switch]$SkipBuild,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$TestsPassed = 0
$TestsFailed = 0

function Write-Section {
    param([string]$Title)
    Write-Host "`n" -NoNewline
    Write-Host "="*60 -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host "="*60 -ForegroundColor Magenta
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n>> $Message" -ForegroundColor Cyan
}

function Test-Prerequisites {
    Write-Section "Checking Prerequisites"
    
    # Flutter
    Write-Step "Checking Flutter..."
    $flutterVersion = flutter --version 2>&1 | Select-String "Flutter"
    if ($flutterVersion) {
        Write-Host "  ✓ Flutter installed: $flutterVersion" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Flutter not found" -ForegroundColor Red
        exit 1
    }
    
    # Android SDK
    if ($DeviceTests) {
        Write-Step "Checking Android SDK..."
        $adbVersion = adb version 2>&1 | Select-String "Version"
        if ($adbVersion) {
            Write-Host "  ✓ ADB found: $adbVersion" -ForegroundColor Green
        } else {
            Write-Host "  ✗ ADB not found" -ForegroundColor Red
            exit 1
        }
    }
    
    # Native libraries
    Write-Step "Checking native libraries..."
    $libCount = (Get-ChildItem "android\src\main\jniLibs\*\libarchive.so" -Recurse).Count
    if ($libCount -eq 4) {
        Write-Host "  ✓ All 4 ABIs present" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing libraries (found $libCount, expected 4)" -ForegroundColor Red
        exit 1
    }
}

function Invoke-CreateArchives {
    Write-Section "Creating Test Archives"
    
    .\scripts\create_test_archives.ps1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Test archives created" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "`n✗ Failed to create test archives" -ForegroundColor Red
        $script:TestsFailed++
    }
}

function Invoke-UnitTests {
    Write-Section "Running Unit Tests"
    
    Write-Step "Executing Dart tests..."
    
    if ($Verbose) {
        flutter test test/services/archive_service_ffi_test.dart --reporter expanded
    } else {
        flutter test test/services/archive_service_ffi_test.dart
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Unit tests passed" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "`n✗ Unit tests failed" -ForegroundColor Red
        $script:TestsFailed++
    }
}

function Invoke-BuildTest {
    Write-Section "Build Verification"
    
    Write-Step "Building debug APK..."
    
    $buildOutput = flutter build apk --debug 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Build successful" -ForegroundColor Green
        
        $apkPath = "build\app\outputs\flutter-apk\app-debug.apk"
        if (Test-Path $apkPath) {
            $apkSize = [math]::Round((Get-Item $apkPath).Length / 1MB, 2)
            Write-Host "  APK: $apkPath ($apkSize MB)" -ForegroundColor Gray
        }
        
        $script:TestsPassed++
    } else {
        Write-Host "`n✗ Build failed" -ForegroundColor Red
        if ($Verbose) {
            Write-Host $buildOutput -ForegroundColor Yellow
        }
        $script:TestsFailed++
    }
}

function Invoke-DeviceTests {
    Write-Section "Device Tests"
    
    # Check device connected
    $devices = adb devices | Select-String "device$"
    if ($devices.Count -eq 0) {
        Write-Host "✗ No device connected, skipping device tests" -ForegroundColor Yellow
        return
    }
    
    Write-Step "Installing APK..."
    adb install -r "build\app\outputs\flutter-apk\app-debug.apk" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ APK installed" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Installation failed" -ForegroundColor Red
        $script:TestsFailed++
        return
    }
    
    Write-Step "Running device tests..."
    .\scripts\test_archive_on_device.ps1 -Verbose:$Verbose
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Device tests passed" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "`n✗ Device tests failed" -ForegroundColor Red
        $script:TestsFailed++
    }
}

function Show-TestSummary {
    Write-Section "Test Summary"
    
    $total = $TestsPassed + $TestsFailed
    $passRate = if ($total -gt 0) { [math]::Round(($TestsPassed / $total) * 100, 1) } else { 0 }
    
    Write-Host "`nTotal Test Suites: $total" -ForegroundColor White
    Write-Host "Passed:            $TestsPassed" -ForegroundColor Green
    Write-Host "Failed:            $TestsFailed" -ForegroundColor Red
    Write-Host "Pass Rate:         $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } else { "Yellow" })
    
    if ($TestsFailed -eq 0) {
        Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
        Write-Host "FFI migration verification complete." -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Some tests failed" -ForegroundColor Yellow
        Write-Host "Review the output above for details." -ForegroundColor Yellow
    }
}

function New-HTMLReport {
    Write-Step "Generating HTML report..."
    
    $reportPath = "test_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Archive FFI Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .passed { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .metric { display: inline-block; margin: 10px 20px; }
        .metric-value { font-size: 24px; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Archive FFI Migration Test Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <div class="metric">
            <div class="metric-value passed">$TestsPassed</div>
            <div>Passed</div>
        </div>
        <div class="metric">
            <div class="metric-value failed">$TestsFailed</div>
            <div>Failed</div>
        </div>
        <div class="metric">
            <div class="metric-value">$([math]::Round(($TestsPassed / ($TestsPassed + $TestsFailed)) * 100, 1))%</div>
            <div>Pass Rate</div>
        </div>
    </div>
    <div class="summary">
        <h2>Details</h2>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Project: EasyFile Archive FFI</p>
        <p>Platform: Android</p>
    </div>
</body>
</html>
"@
    
    $html | Out-File $reportPath -Encoding UTF8
    Write-Host "  Report: $reportPath" -ForegroundColor Gray
}

# Main execution
try {
    $startTime = Get-Date
    
    Write-Host @"
╔══════════════════════════════════════════════════════════╗
║        Archive FFI Test Suite                            ║
║        EasyFile - Complete Verification                  ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta
    
    Test-Prerequisites
    
    if ($CreateArchives) {
        Invoke-CreateArchives
    }
    
    if (-not $SkipBuild) {
        Invoke-BuildTest
    }
    
    if ($UnitTests) {
        Invoke-UnitTests
    }
    
    if ($DeviceTests) {
        Invoke-DeviceTests
    }
    
    Show-TestSummary
    New-HTMLReport
    
    $duration = (Get-Date) - $startTime
    Write-Host "`nTotal duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Gray
    
    if ($TestsFailed -eq 0) {
        exit 0
    } else {
        exit 1
    }
    
} catch {
    Write-Host "`nCRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
}