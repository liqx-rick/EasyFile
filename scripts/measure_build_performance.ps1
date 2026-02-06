# Build Performance Monitor Script
# Measure and compare Flutter build times

param(
   [switch]$Clean,
   [switch]$ProfileMode,
   [int]$Runs = 1
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Flutter Build Performance Monitor" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Function to format time
function Format-Duration {
   param($Seconds)

   $minutes = [math]::Floor($Seconds / 60)
   $secs = [math]::Round($Seconds % 60, 1)

   if ($minutes -gt 0) {
      return "${minutes}m ${secs}s"
   }
   else {
      return "${secs}s"
   }
}

# Function to run build and measure time
function Measure-Build {
   param(
      [string]$BuildType,
      [bool]$DoClean
   )

   Write-Host "[$BuildType] Starting build..." -ForegroundColor Yellow

   if ($DoClean) {
      Write-Host "  - Cleaning build cache..." -ForegroundColor Gray
      flutter clean | Out-Null
      Remove-Item -Recurse -Force "android\build" -ErrorAction SilentlyContinue
      Remove-Item -Recurse -Force "android\.gradle" -ErrorAction SilentlyContinue
      Remove-Item -Recurse -Force "android\app\build" -ErrorAction SilentlyContinue
   }

   $startTime = Get-Date

   Write-Host "  - Building APK..." -ForegroundColor Gray

   if ($BuildType -eq "Debug") {
      $output = flutter build apk --debug 2>&1
   }
   elseif ($BuildType -eq "Profile") {
      $output = flutter build apk --profile 2>&1
   }
   else {
      $output = flutter build apk --release 2>&1
   }

   $endTime = Get-Date
   $duration = ($endTime - $startTime).TotalSeconds

   # Check if build succeeded
   $success = $output -match "Built build"

   if ($success) {
      Write-Host "  [SUCCESS] Build completed in $(Format-Duration $duration)" -ForegroundColor Green
   }
   else {
      Write-Host "  [FAILED] Build failed after $(Format-Duration $duration)" -ForegroundColor Red
      $errorLines = $output | Select-Object -Last 5
      $errorText = ($errorLines | Out-String).Trim()
      Write-Host "  Last error:" -ForegroundColor Red
      Write-Host "  $errorText" -ForegroundColor Red
   }

   return @{
      Success  = $success
      Duration = $duration
      Output   = $output
   }
}

# Main execution
$results = @()

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  - Clean build: $(if($Clean){'Yes'}else{'No'})" -ForegroundColor White
Write-Host "  - Build mode: $(if($ProfileMode){'Profile'}else{'Debug'})" -ForegroundColor White
Write-Host "  - Number of runs: $Runs" -ForegroundColor White
Write-Host ""

$buildType = if ($ProfileMode) { "Profile" } else { "Debug" }

for ($i = 1; $i -le $Runs; $i++) {
   if ($Runs -gt 1) {
      Write-Host "================================================" -ForegroundColor Cyan
      Write-Host "  Run $i of $Runs" -ForegroundColor Cyan
      Write-Host "================================================" -ForegroundColor Cyan
   }

   # Clean only on first run if requested
   $doClean = $Clean -and ($i -eq 1)

   $result = Measure-Build -BuildType $buildType -DoClean $doClean
   $results += $result

   if ($i -lt $Runs) {
      Write-Host ""
      Start-Sleep -Seconds 2
   }
}

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Build Performance Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if ($results.Count -gt 1) {
   $successfulBuilds = $results | Where-Object { $_.Success }
   if ($successfulBuilds.Count -gt 0) {
      $avgDuration = ($successfulBuilds | Measure-Object -Property Duration -Average).Average
      $minDuration = ($successfulBuilds | Measure-Object -Property Duration -Minimum).Minimum
      $maxDuration = ($successfulBuilds | Measure-Object -Property Duration -Maximum).Maximum

      Write-Host "Successful builds: $($successfulBuilds.Count) of $($results.Count)" -ForegroundColor Green
      Write-Host "Average time: $(Format-Duration $avgDuration)" -ForegroundColor Yellow
      Write-Host "Fastest: $(Format-Duration $minDuration)" -ForegroundColor Green
      Write-Host "Slowest: $(Format-Duration $maxDuration)" -ForegroundColor Red
   }
   else {
      Write-Host "No successful builds" -ForegroundColor Red
   }
}
else {
   if ($results[0].Success) {
      Write-Host "Build time: $(Format-Duration $results[0].Duration)" -ForegroundColor Green
   }
   else {
      Write-Host "Build failed" -ForegroundColor Red
   }
}

Write-Host ""
Write-Host "Tips for faster builds:" -ForegroundColor Cyan
Write-Host "  1. Use incremental builds (avoid 'flutter clean')" -ForegroundColor White
Write-Host "  2. Use 'flutter run --profile' for testing" -ForegroundColor White
Write-Host "  3. Enable Gradle daemon and caching (already configured)" -ForegroundColor White
Write-Host "  4. Close other resource-intensive applications" -ForegroundColor White
Write-Host ""

# Create timestamp log file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "build_performance_$timestamp.log"

$logContent = @"
Build Performance Report
========================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Build Mode: $buildType
Clean Build: $(if($Clean){'Yes'}else{'No'})
Number of Runs: $Runs

Results:
--------
"@

for ($i = 0; $i -lt $results.Count; $i++) {
   $runNum = $i + 1
   $logContent += [System.Environment]::NewLine + "Run ${runNum}: "
   if ($results[$i].Success) {
      $duration = Format-Duration $results[$i].Duration
      $logContent += "SUCCESS - $duration"
   }
   else {
      $duration = Format-Duration $results[$i].Duration
      $logContent += "FAILED - $duration"
   }
}

$logContent | Out-File -FilePath $logFile -Encoding UTF8
Write-Host "Performance log saved to: $logFile" -ForegroundColor Gray
