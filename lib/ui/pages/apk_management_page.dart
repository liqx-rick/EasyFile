import 'dart:async';

import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/apk_manager_service.dart';
import '../../data/models/apk_info.dart';
import '../../presenter/file_presenter.dart';
import '../widgets/apk_list_item_widget.dart';
import 'apk_detail_page.dart';

/// APK管理页面
///
/// 功能：
/// - 扫描并显示设备上所有APK文件
/// - 显示APK信息（应用名、包名、版本、安装状态）
/// - 支持未安装APK跳转系统安装页面
/// - 支持已安装APK跳转应用详情
/// - 支持删除APK文件
class ApkManagementPage extends StatefulWidget {
  const ApkManagementPage({super.key});

  @override
  State<ApkManagementPage> createState() => _ApkManagementPageState();
}

class _ApkManagementPageState extends State<ApkManagementPage> with WidgetsBindingObserver {
  late final ApkManagerService _apkManagerService;
  List<ApkInfo> _apkList = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  // 扫描状态显示
  bool _isScanning = false;
  String? _scanResultMessage;
  Timer? _scanResultTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final filePresenter = GetIt.I<FilePresenter>();
    _apkManagerService = ApkManagerService(filePresenter: filePresenter);
    _loadApkFilesWithCache(); // 优先显示缓存，3秒后后台全量扫描

    // 启动包管理器监听（页面级）
    _apkManagerService.startPackageListener(_onPackageChanged);

    // 埋点：进入APK管理页面
    AnalyticsHelper.logApkManagementEnter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanResultTimer?.cancel();
    _apkManagerService.stopPackageListener(); // 停止包监听
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用从后台返回前台时（如从安装页面返回），快速更新安装状态
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _quickUpdateInstallStatus(); // 快速更新安装状态，不重新扫描
      }
    }
  }

  /// 应用包变化回调（安装/卸载/更新）
  void _onPackageChanged(String packageName, String action) {
    if (!mounted) return;

    // 实时更新安装状态
    _quickUpdateInstallStatus();
  }

  /// 快速更新安装状态（不重新扫描文件）
  Future<void> _quickUpdateInstallStatus() async {
    if (_apkList.isEmpty) return;

    try {
      final updatedList = await _apkManagerService.updateInstallStatus(_apkList);
      if (mounted) {
        setState(() {
          _apkList = updatedList;
        });
      }
    } catch (e) {
      logger.e('[ApkManagementPage] 快速更新状态失败: $e');
    }
  }

  /// 后台加载APK文件（不显示loading，静默更新）
  Future<void> _loadApkFilesInBackground() async {
    // 取消之前的扫描结果定时器
    _scanResultTimer?.cancel();

    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanResultMessage = null;
      });
    }

    try {
      final apkList = await _apkManagerService.scanApkFiles(forceRefresh: true);
      if (mounted) {
        setState(() {
          _apkList = apkList;
          _isScanning = false;
          _scanResultMessage = '扫描完成，发现 ${apkList.length} 个APK';
        });

        // 5秒后隐藏扫描结果
        _scanResultTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _scanResultMessage = null;
            });
          }
        });
      }
    } catch (e) {
      // 记录错误但不影响UI
      logger.e('[ApkManagementPage] 后台刷新失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanResultMessage =
              '扫描失败: ${e.toString().length > 30 ? '${e.toString().substring(0, 30)}...' : e.toString()}';
        });

        // 5秒后隐藏错误消息
        _scanResultTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _scanResultMessage = null;
            });
          }
        });
      }
    }
  }

  /// 优先加载缓存，然后后台全量扫描
  Future<void> _loadApkFilesWithCache() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // 尝试从缓存加载
      final apkList = await _apkManagerService.scanApkFiles(forceRefresh: false);

      if (mounted) {
        setState(() {
          _apkList = apkList;
          _isLoading = false;
        });

        // 如果有缓存数据，3秒后后台触发全量扫描
        if (apkList.isNotEmpty) {
          Timer(const Duration(seconds: 3), () {
            if (mounted) {
              _loadApkFilesInBackground(); // 后台全量扫描
            }
          });
        } else {
          // 如果没有缓存，立即触发全量扫描
          _loadApkFiles(forceRefresh: true);
        }
      }
    } catch (e) {
      logger.e('[ApkManagementPage] 加载缓存失败: $e');
      // 缓存加载失败，立即触发全量扫描
      if (mounted) {
        _loadApkFiles(forceRefresh: true);
      }
    }
  }

  /// 加载APK文件
  ///
  /// [forceRefresh] 强制刷新，忽略缓存
  Future<void> _loadApkFiles({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final apkList = await _apkManagerService.scanApkFiles(
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _apkList = apkList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// 显示APK详情页
  void _showApkDetail(ApkInfo apkInfo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ApkDetailPage(
          apkInfo: apkInfo,
          onInstall: () => _handleInstall(apkInfo),
          onOpenSettings: () => _handleOpenSettings(apkInfo),
          onDelete: () => _deleteApk(apkInfo),
        ),
      ),
    );
  }

  /// 处理安装操作
  Future<void> _handleInstall(ApkInfo apkInfo) async {
    final success = await _apkManagerService.launchInstall(apkInfo);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('安装跳转失败')),
      );
    }
  }

  /// 处理打开应用设置
  Future<void> _handleOpenSettings(ApkInfo apkInfo) async {
    final success = await _apkManagerService.launchAppSettings(apkInfo);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打开应用设置失败')),
      );
    }
  }

  /// 处理状态按钮点击（安装或打开设置）
  Future<void> _handleStatusAction(ApkInfo apkInfo) async {
    if (apkInfo.status == ApkInstallStatus.notInstalled) {
      await _handleInstall(apkInfo);
    } else if (apkInfo.status == ApkInstallStatus.installed ||
        apkInfo.status == ApkInstallStatus.upgradable ||
        apkInfo.status == ApkInstallStatus.signatureMismatch) {
      // 禁止访问易览文件自身的应用信息页面
      if (apkInfo.packageName == 'com.guangqi.easyfile') {
        return;
      }
      await _handleOpenSettings(apkInfo);
    }
  }

  /// 删除APK
  Future<void> _deleteApk(ApkInfo apkInfo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${apkInfo.appName} (${apkInfo.versionName}) 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _apkManagerService.deleteApk(apkInfo);
      if (mounted) {
        if (success) {
          setState(() {
            _apkList.remove(apkInfo);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
          // 删除成功后后台刷新以更新缓存
          _loadApkFilesInBackground();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败')),
          );
        }
      }
    }
  }

  /// 显示APK操作菜单
  void _showApkOptionsMenu(ApkInfo apkInfo) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      apkInfo.appName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 查看详情
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看详情'),
              onTap: () {
                Navigator.pop(context);
                _showApkDetail(apkInfo);
              },
            ),
            // 安装或打开设置
            if (apkInfo.status == ApkInstallStatus.notInstalled)
              ListTile(
                leading: const Icon(Icons.install_mobile),
                title: const Text('安装应用'),
                onTap: () {
                  Navigator.pop(context);
                  _handleInstall(apkInfo);
                },
              )
            else if (apkInfo.packageName != 'com.guangqi.easyfile')
              // 禁止易览文件自身打开应用设置
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('应用设置'),
                onTap: () {
                  Navigator.pop(context);
                  _handleOpenSettings(apkInfo);
                },
              ),
            // 删除
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除APK', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteApk(apkInfo);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0978FE),
        foregroundColor: Colors.white,
        title: const Text('安装包管理'),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadApkFilesInBackground(),
            tooltip: '强制刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadApkFilesInBackground,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在扫描APK文件...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('扫描失败: $_errorMessage'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadApkFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_apkList.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 100),
          Icon(Icons.inbox, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Center(
            child: Text('未发现APK文件', style: TextStyle(color: Colors.grey)),
          ),
          SizedBox(height: 16),
          Center(
            child: Text(
              '下拉刷新',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // 扫描状态显示区域
        if (_isScanning || _scanResultMessage != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _isScanning
                ? Colors.blue.shade50
                : (_scanResultMessage?.contains('失败') ?? false)
                    ? Colors.red.shade50
                    : Colors.green.shade50,
            child: Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    (_scanResultMessage?.contains('失败') ?? false) ? Icons.error_outline : Icons.check_circle_outline,
                    size: 16,
                    color: (_scanResultMessage?.contains('失败') ?? false) ? Colors.red : Colors.green,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isScanning ? '正在扫描APK文件...' : _scanResultMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isScanning
                          ? Colors.blue.shade700
                          : (_scanResultMessage?.contains('失败') ?? false)
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 统计信息
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '共 ${_apkList.length} 个APK',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                _formatTotalSize(_apkList),
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        // APK列表
        Expanded(
          child: ListView.separated(
            itemCount: _apkList.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final apkInfo = _apkList[index];
              return ApkListItemWidget(
                apkInfo: apkInfo,
                onTap: () => _showApkDetail(apkInfo),
                onLongPress: () => _showApkOptionsMenu(apkInfo),
                onStatusTap: () => _handleStatusAction(apkInfo),
                onDelete: () => _deleteApk(apkInfo),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 格式化总大小
  String _formatTotalSize(List<ApkInfo> apkList) {
    final totalBytes = apkList.fold<int>(0, (sum, apk) => sum + apk.fileSize);
    if (totalBytes < 1024) {
      return '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
