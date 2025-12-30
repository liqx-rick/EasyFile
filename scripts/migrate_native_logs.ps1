# 批量迁移原生日志到 LogHelper
# 用法：在 easyfile 项目根目录运行此脚本

Write-Host "开始批量迁移原生日志..." -ForegroundColor Green

$targetDir = "android\app\src\main\kotlin\com\guangqi\easyfile"
$excludeFile = "LogHelper.kt"

# 需要迁移的文件列表（高优先级）
$filesToMigrate = @(
    "MainActivity.kt",
    "MediaStoreTrashHelper.kt",
    "NewFilesNativeScanner.kt",
    "StorageStatsHelper.kt",
    "AppFileScanner.kt"
)

$totalFiles = 0
$successFiles = 0
$failedFiles = 0

foreach ($fileName in $filesToMigrate) {
    $filePath = Join-Path $targetDir $fileName
    
    if (Test-Path $filePath) {
        Write-Host "`n正在处理: $fileName" -ForegroundColor Cyan
        $totalFiles++
        
        try {
            # 读取文件内容
            $content = Get-Content $filePath -Raw -Encoding UTF8
            $originalContent = $content
            
            # 执行替换
            $content = $content -replace 'Log\.d\(', 'LogHelper.d('
            $content = $content -replace 'Log\.i\(', 'LogHelper.i('
            $content = $content -replace 'Log\.w\(', 'LogHelper.w('
            $content = $content -replace 'Log\.e\(', 'LogHelper.e('
            
            # 统计替换数量
            $changesCount = 0
            if ($content -ne $originalContent) {
                # 统计每种日志的替换次数
                $dCount = ([regex]::Matches($originalContent, 'Log\.d\(')).Count
                $iCount = ([regex]::Matches($originalContent, 'Log\.i\(')).Count
                $wCount = ([regex]::Matches($originalContent, 'Log\.w\(')).Count
                $eCount = ([regex]::Matches($originalContent, 'Log\.e\(')).Count
                $changesCount = $dCount + $iCount + $wCount + $eCount
                
                # 写回文件
                Set-Content $filePath $content -Encoding UTF8 -NoNewline
                
                Write-Host "  ✓ 替换完成: $changesCount 处" -ForegroundColor Green
                Write-Host "    - Log.d: $dCount 处" -ForegroundColor Gray
                Write-Host "    - Log.i: $iCount 处" -ForegroundColor Gray
                Write-Host "    - Log.w: $wCount 处" -ForegroundColor Gray
                Write-Host "    - Log.e: $eCount 处" -ForegroundColor Gray
                $successFiles++
            } else {
                Write-Host "  - 无需替换（已经使用 LogHelper 或无日志）" -ForegroundColor Yellow
                $successFiles++
            }
        } catch {
            Write-Host "  ✗ 处理失败: $_" -ForegroundColor Red
            $failedFiles++
        }
    } else {
        Write-Host "`n跳过: $fileName (文件不存在)" -ForegroundColor Yellow
    }
}

Write-Host "`n" + "="*60 -ForegroundColor Green
Write-Host "迁移完成！" -ForegroundColor Green
Write-Host "总计: $totalFiles 个文件" -ForegroundColor Cyan
Write-Host "成功: $successFiles 个" -ForegroundColor Green
Write-Host "失败: $failedFiles 个" -ForegroundColor $(if ($failedFiles -gt 0) { "Red" } else { "Green" })
Write-Host "="*60 -ForegroundColor Green

Write-Host "`n下一步操作：" -ForegroundColor Yellow
Write-Host "1. 运行命令验证编译: flutter build apk --profile" -ForegroundColor White
Write-Host "2. 运行应用测试: flutter run --profile" -ForegroundColor White
Write-Host "3. 检查日志输出: adb logcat -s LogHelper:* MainActivity:* MediaStore*:*" -ForegroundColor White
