import 'dart:async';

import 'package:easyfile/analytics/analytics_helper.dart';
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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final filePresenter = GetIt.I<FilePresenter>();
    _apkManagerService = ApkManagerService(filePresenter: filePresenter);
    _loadApkFiles(); // 首次加载优先使用缓存

    // 启动定时器，每60秒后台刷新（不阻塞UI）
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        _loadApkFilesInBackground(); // 后台静默刷新
      }
    });

    // 启动包管理器监听（页面级）
    _apkManagerService.startPackageListener(_onPackageChanged);

    // 埋点：进入APK管理页面
    AnalyticsHelper.logApkManagementEnter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _apkManagerService.stopPackageListener(); // 停止包监听
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用从后台返回前台时（如从设置页卸载后返回），自动刷新
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _loadApkFilesInBackground(); // 后台刷新，不阻塞UI
      }
    }
  }

  /// 应用包变化回调（安装/卸载/更新）
  void _onPackageChanged(String packageName, String action) {
    if (!mounted) return;

    // 实时更新安装状态
    _loadApkFilesInBackground();
  }

  /// 后台加载APK文件（不显示loading，静默更新）
  Future<void> _loadApkFilesInBackground() async {
    try {
      final apkList = await _apkManagerService.scanApkFiles(forceRefresh: true);
      if (mounted) {
        setState(() {
          _apkList = apkList; // 只更新数据，不设置loading状态
        });
      }
    } catch (e) {
      // 后台刷新失败不影响UI，静默处理
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      body: _buildBody(),
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
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.inbox, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('未发现APK文件', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
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
