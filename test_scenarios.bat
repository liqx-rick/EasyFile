@echo off
REM 简易测试脚本 - 三个启动场景测试

echo.
echo ===================================
echo 🧪 EasyFile 启动场景测试工具
echo ===================================
echo.

:menu
echo.
echo 选择测试场景:
echo 1. 清理并准备首次安装 (freshInstall)
echo 2. 验证缓存重装 (reinstall)
echo 3. 验证正常打开 (normalOpen)
echo 4. 启动日志监控
echo 5. 启动应用
echo 6. 卸载应用
echo 7. 查看设备
echo 0. 退出
echo.
set /p choice="请输入选择 (0-7): "

if "%choice%"=="1" goto freshinstall
if "%choice%"=="2" goto reinstall
if "%choice%"=="3" goto normalopen
if "%choice%"=="4" goto logs
if "%choice%"=="5" goto run
if "%choice%"=="6" goto uninstall
if "%choice%"=="7" goto devices
if "%choice%"=="0" goto exit
echo 无效的选择，请重试
goto menu

:freshinstall
echo.
echo [1/4] 卸载应用...
adb uninstall com.example.easyfile
echo.
echo [2/4] 清理应用数据...
adb shell pm clear com.example.easyfile
echo.
echo [3/4] 验证应用已卸载...
adb shell pm list packages | find "easyfile"
echo.
echo [4/4] 构建并安装应用...
call flutter install
echo.
echo ✅ freshInstall 场景已准备好！
echo 现在：
echo   1. 在另一个终端运行: flutter logs (监控日志)
echo   2. 再在另一个终端运行: flutter run (启动应用)
echo   3. 观察进度 UI 和初始化过程（约 37 秒）
goto menu

:reinstall
echo.
echo ⚠️  在执行此步骤前，请确保:
echo   1. 应用已完成 freshInstall 测试
echo   2. 你看到了"Full initialization completed"消息
echo.
set /p ready="已准备好？(Y/N): "
if /i "%ready%"=="Y" goto do_reinstall
goto menu

:do_reinstall
echo.
echo [1/3] 卸载应用（保留数据）...
adb uninstall com.example.easyfile
echo.
echo [2/3] 重新安装应用...
call flutter install
echo.
echo [3/3] 启动应用...
call flutter run
echo.
echo ✅ 观察:
echo   - 应该 **没有** 进度 UI
echo   - 应该在 ~3 秒内加载
echo   - 快速访问菜单应已恢复
goto menu

:normalopen
echo.
echo ⚠️  在执行此步骤前，请确保:
echo   1. 应用已完成 freshInstall 测试
echo   2. 应用已完成 reinstall 测试
echo   3. 应用当前未运行
echo.
set /p ready="已准备好？(Y/N): "
if /i "%ready%"=="Y" goto do_normalopen
goto menu

:do_normalopen
echo.
echo 关闭应用进程...
adb shell am force-stop com.example.easyfile
timeout /t 2 /nobreak
echo.
echo 重新打开应用...
call flutter run
echo.
echo ✅ 观察:
echo   - 应该 **没有** 进度 UI
echo   - 应该在 ~2 秒内加载
echo   - 所有数据应完整可用
goto menu

:logs
echo.
echo 启动日志监控（Ctrl+C 停止）...
echo.
call flutter logs
goto menu

:run
echo.
echo 启动应用...
call flutter run
goto menu

:uninstall
echo.
echo 卸载应用...
adb uninstall com.example.easyfile
echo ✅ 已卸载
goto menu

:devices
echo.
echo 可用设备:
adb devices -l
echo.
goto menu

:exit
echo 再见！
pause
