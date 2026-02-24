#!/usr/bin/env pwsh
# 设备硬件信息统计测试脚本
# 测试硬件信息获取功能

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   设备硬件信息统计测试" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查设备连接
Write-Host "1. 检查设备连接..." -ForegroundColor Yellow
$devices = adb devices | Select-String 'device$'
if ($devices.Count -eq 0) {
   Write-Host "❌ 未检测到Android设备" -ForegroundColor Red
   Write-Host "   请连接设备并启用USB调试" -ForegroundColor Gray
   exit 1
}
Write-Host "✓ 设备已连接: $($devices[0])" -ForegroundColor Green
Write-Host ""

# 运行应用
Write-Host "2. 启动应用..." -ForegroundColor Yellow
flutter run --release 2>&1 | Tee-Object -Variable output

# 等待应用启动
Start-Sleep -Seconds 5

# 过滤设备信息日志
Write-Host ""
Write-Host "3. 提取设备硬件信息日志..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# 获取最近的日志
$logs = adb logcat -d -s flutter:I | Select-String -Pattern '设备硬件环境统计|设备信息|系统信息|处理器信息|内存信息|存储信息|屏幕信息' -Context 0, 5

if ($logs) {
   foreach ($log in $logs) {
      Write-Host $log -ForegroundColor White
   }
}
else {
   Write-Host "⚠️ 未找到设备信息日志" -ForegroundColor Yellow
   Write-Host "   尝试手动查看日志: adb logcat -s flutter:I" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "测试说明:" -ForegroundColor Cyan
Write-Host "1. 应用启动时会自动打印硬件信息到日志" -ForegroundColor Gray
Write-Host "2. 在设置页面可以查看详细的硬件信息" -ForegroundColor Gray
Write-Host "3. 导航路径: 设置 -> 开发者选项 -> 设备硬件信息" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
