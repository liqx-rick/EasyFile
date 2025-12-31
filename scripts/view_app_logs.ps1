# 查看应用日志（过滤系统日志）
# 只显示 Flutter 和应用自己的日志

param(
    [string]$LogFile = "",
    [switch]$Live = $false
)

# 定义应用相关的日志标签
$appTags = @(
    "flutter",
    "MainActivity",
    "MediaStoreScanner",
    "MediaStoreRecording",
    "AppFileScanner",
    "NewFilesNativeScanner",
    "StorageStatsHelper",
    "LogHelper"
)

# 构建过滤模式
$pattern = "(" + ($appTags -join "|") + ")"

if ($Live) {
    Write-Host "🔍 实时查看应用日志（过滤系统日志）..." -ForegroundColor Cyan
    Write-Host "标签: $($appTags -join ', ')" -ForegroundColor Gray
    Write-Host ""
    
    adb logcat -v time | Select-String -Pattern $pattern
} elseif ($LogFile -ne "") {
    Write-Host "📄 分析日志文件: $LogFile" -ForegroundColor Cyan
    Write-Host ""
    
    Get-Content $LogFile | Select-String -Pattern $pattern
} else {
    Write-Host "用法:" -ForegroundColor Yellow
    Write-Host "  .\view_app_logs.ps1 -Live                    # 实时查看" -ForegroundColor Gray
    Write-Host "  .\view_app_logs.ps1 -LogFile consolelog.txt  # 分析日志文件" -ForegroundColor Gray
}
