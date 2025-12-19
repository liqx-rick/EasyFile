import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/app_file_scanner_channel.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

/// 应用文件扫描方案对比测试页面
class AppFileScanTestPage extends StatefulWidget {
  const AppFileScanTestPage({super.key});

  @override
  State<AppFileScanTestPage> createState() => _AppFileScanTestPageState();
}

class _AppFileScanTestPageState extends State<AppFileScanTestPage> {
  bool _isScanning = false;
  bool _isAndroid11Supported = false;
  
  // 方案1: 路径扫描结果
  List<FileItem>? _pathScanResults;
  int? _pathScanDuration;
  
  // 方案2: MediaStore OWNER_PACKAGE_NAME 结果
  List<FileItem>? _ownerPackageResults;
  int? _ownerPackageDuration;
  
  // 测试应用列表
  final List<Map<String, String>> _testApps = [
    {'key': 'wechat', 'name': '微信', 'package': 'com.tencent.mm'},
    {'key': 'weixin', 'name': 'WeiXin', 'package': 'com.tencent.mm'},
    {'key': 'qq', 'name': 'QQ', 'package': 'com.tencent.mobileqq'},
    {'key': 'telegram', 'name': 'Telegram', 'package': 'org.telegram.messenger'},
    {'key': 'wps', 'name': 'WPS', 'package': 'cn.wps.moffice_eng'},
  ];
  
  String _selectedAppKey = 'wechat';
  String _selectedPackageName = 'com.tencent.mm';

  @override
  void initState() {
    super.initState();
    _checkAndroid11Support();
  }

  /// 检查 Android 11 支持
  Future<void> _checkAndroid11Support() async {
    final supported = await AppFileScannerChannel.isOwnerPackageSupported();
    setState(() {
      _isAndroid11Supported = supported;
    });
  }

  /// 方案1: 路径扫描 + 文件名模式匹配
  Future<void> _scanByPath() async {
    logger.i('开始路径扫描测试');
    
    final startTime = DateTime.now();
    
    try {
      final files = <FileItem>[];
      final pathSet = <String>{}; // 用于去重
      
      // 1. 获取要扫描的路径
      List<String> paths = [];
      
      // 对于 WeiXin、QQ、Telegram、WPS，动态查找匹配关键字的文件夹
      if (_selectedAppKey == 'weixin' || _selectedAppKey == 'qq' || 
          _selectedAppKey == 'telegram' || _selectedAppKey == 'wps') {
        final basePaths = [
          '/storage/emulated/0/Download/',
          '/storage/emulated/0/Pictures/',
          '/storage/emulated/0/DCIM/',
          '/storage/emulated/0/Music/',
          '/storage/emulated/0/Movies/',
          '/storage/emulated/0/Documents/',
        ];
        
        final keywordMap = {
          'weixin': 'WeiXin',
          'qq': 'QQ',
          'telegram': 'Telegram',
          'wps': 'WPS',
        };
        final keyword = keywordMap[_selectedAppKey]!;
        logger.i('动态查找严格匹配 "$keyword" 的文件夹...');
        
        paths = await AppFileScannerChannel.findFoldersContaining(basePaths, keyword);
        logger.i('找到 ${paths.length} 个匹配的文件夹: $paths');
      } else {
        // 微信使用固定路径
        paths = await AppFileScannerChannel.getKnownAppPaths(_selectedAppKey);
      }
      
      // 2. 扫描这些路径
      for (final path in paths) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                final fileItem = FileItem.fromEntity(entity);
                if (!pathSet.contains(fileItem.path)) {
                  files.add(fileItem);
                  pathSet.add(fileItem.path);
                }
              } catch (e) {
                // 忽略错误
              }
            }
          }
        }
      }
      
      // 3. 通过文件名模式查找（例如微信相机文件：wx_camera_*.mp4, mmexport*.jpg）
      final patterns = await AppFileScannerChannel.getAppFileNamePatterns(_selectedAppKey);
      if (patterns.isNotEmpty) {
        logger.i('查找文件名模式: $patterns');
        final patternFiles = await AppFileScannerChannel.scanByFileNamePattern(patterns);
        
        int addedCount = 0;
        // 合并结果并去重
        for (final file in patternFiles) {
          if (!pathSet.contains(file.path)) {
            files.add(file);
            pathSet.add(file.path);
            addedCount++;
          }
        }
        
        logger.i('文件名模式匹配找到 ${patternFiles.length} 个文件，去重后新增 $addedCount 个');
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      setState(() {
        _pathScanResults = files;
        _pathScanDuration = duration.inMilliseconds;
      });
      
      logger.i('路径扫描完成: ${files.length} 个文件, 耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      logger.e('路径扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('路径扫描失败: $e')),
        );
      }
    }
  }

  /// 方案2: MediaStore OWNER_PACKAGE_NAME
  Future<void> _scanByOwnerPackage() async {
    if (!_isAndroid11Supported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要 Android 11+ 才支持 OWNER_PACKAGE_NAME')),
        );
      }
      return;
    }
    
    logger.i('开始 OWNER_PACKAGE_NAME 扫描测试');
    
    final startTime = DateTime.now();
    
    try {
      final results = await AppFileScannerChannel.scanByOwnerPackage(_selectedPackageName);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      setState(() {
        _ownerPackageResults = results;
        _ownerPackageDuration = duration.inMilliseconds;
      });
      
      logger.i('OWNER_PACKAGE_NAME 扫描完成: ${results.length} 个文件, 耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      logger.e('OWNER_PACKAGE_NAME 扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OWNER_PACKAGE_NAME 扫描失败: $e')),
        );
      }
    }
  }

  /// 执行对比测试
  Future<void> _runComparisonTest() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _pathScanResults = null;
      _pathScanDuration = null;
      _ownerPackageResults = null;
      _ownerPackageDuration = null;
    });

    // 先执行路径扫描
    await _scanByPath();
    
    // 等待1秒
    await Future.delayed(const Duration(seconds: 1));
    
    // 再执行 OWNER_PACKAGE_NAME 扫描
    await _scanByOwnerPackage();
    
    setState(() {
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用文件扫描方案对比'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 应用选择
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '选择测试应用',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      value: _selectedAppKey,
                      isExpanded: true,
                      items: _testApps.map((app) {
                        return DropdownMenuItem(
                          value: app['key'],
                          child: Text('${app['name']} (${app['package']})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          final app = _testApps.firstWhere((a) => a['key'] == value);
                          setState(() {
                            _selectedAppKey = value;
                            _selectedPackageName = app['package']!;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Android 11+ 支持: ${_isAndroid11Supported ? "✅ 是" : "❌ 否"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isAndroid11Supported ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 测试按钮
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _runComparisonTest,
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isScanning ? '扫描中...' : '开始对比测试'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 结果对比
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 方案1: 路径扫描 + 文件名模式
                        Expanded(
                          child: _buildResultCard(
                            title: '方案1: 路径+文件名',
                            icon: Icons.folder_special,
                            color: Colors.blue,
                            results: _pathScanResults,
                            duration: _pathScanDuration,
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        // 方案2: OWNER_PACKAGE_NAME
                        Expanded(
                          child: _buildResultCard(
                            title: '方案2: MediaStore',
                            icon: Icons.storage,
                            color: Colors.orange,
                            results: _ownerPackageResults,
                            duration: _ownerPackageDuration,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 对比分析
                    if (_pathScanResults != null && _ownerPackageResults != null)
                      _buildComparisonAnalysis(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<FileItem>? results,
    required int? duration,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            if (results == null && duration == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('等待扫描...', style: TextStyle(color: Colors.grey)),
                ),
              )
            else if (results != null) ...[
              _buildStatRow('文件数量', '${results.length} 个'),
              const SizedBox(height: 8),
              _buildStatRow(
                '总大小',
                FileSizeFormatter.formatBytes(
                  results.fold<int>(0, (sum, file) => sum + file.size),
                ),
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '扫描耗时',
                duration != null 
                    ? '${(duration / 1000).toStringAsFixed(2)}s'
                    : '-',
                highlight: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.green : Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonAnalysis() {
    final pathCount = _pathScanResults!.length;
    final ownerCount = _ownerPackageResults!.length;
    final pathDuration = _pathScanDuration!;
    final ownerDuration = _ownerPackageDuration!;
    
    final countDiff = pathCount - ownerCount;
    final speedDiff = pathDuration - ownerDuration;
    
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '对比分析',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              '📊 文件数量: 方案1 找到 $pathCount 个，方案2 找到 $ownerCount 个',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            
            Text(
              '⚡ 性能对比: ${speedDiff > 0 ? "方案2 快 ${(speedDiff / 1000).toStringAsFixed(2)}s" : "方案1 快 ${(-speedDiff / 1000).toStringAsFixed(2)}s"}',
              style: TextStyle(
                fontSize: 14,
                color: speedDiff > 0 ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            if (countDiff != 0) ...[
              const SizedBox(height: 12),
              Text(
                countDiff > 0
                    ? '⚠️ 方案1 多找到了 $countDiff 个文件\n可能原因: \n  • 包含未被 MediaStore 索引的文件\n  • 通过文件名模式找到的微信相机文件（wx_camera_*, mmexport*）'
                    : '⚠️ 方案2 多找到了 ${-countDiff} 个文件\n可能原因: 索引了非应用目录的文件',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            const Text(
              '💡 结论建议:\n'
              '• 方案1 结合路径扫描和文件名模式匹配，更全面\n'
              '• 方案1 能找到被用户移动的微信文件（wx_camera_*, mmexport*）\n'
              '• 方案2 仅在 Android 11+ 可用，且依赖系统索引\n'
              '• 推荐使用方案1 作为主要方式',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _showDifferenceFiles(),
              icon: const Icon(Icons.compare_arrows),
              label: const Text('查看差异文件'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示差异文件列表
  void _showDifferenceFiles() {
    if (_pathScanResults == null || _ownerPackageResults == null) return;

    // 创建路径集合
    final pathScanPaths = _pathScanResults!.map((f) => f.path).toSet();
    final ownerPackagePaths = _ownerPackageResults!.map((f) => f.path).toSet();

    // 找出只在路径扫描中存在的文件
    final onlyInPathScan = _pathScanResults!
        .where((f) => !ownerPackagePaths.contains(f.path))
        .toList();

    // 找出只在 MediaStore 中存在的文件
    final onlyInMediaStore = _ownerPackageResults!
        .where((f) => !pathScanPaths.contains(f.path))
        .toList();

    showDialog(
      context: context,
      builder: (context) => _DifferenceFilesDialog(
        onlyInPathScan: onlyInPathScan,
        onlyInMediaStore: onlyInMediaStore,
      ),
    );
  }
}

/// 差异文件对话框
class _DifferenceFilesDialog extends StatelessWidget {
  final List<FileItem> onlyInPathScan;
  final List<FileItem> onlyInMediaStore;

  const _DifferenceFilesDialog({
    required this.onlyInPathScan,
    required this.onlyInMediaStore,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '差异文件分析',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 统计信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 仅在路径扫描中: ${onlyInPathScan.length} 个',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '📊 仅在 MediaStore 中: ${onlyInMediaStore.length} 个',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // 文件列表
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '仅路径扫描'),
                        Tab(text: '仅MediaStore'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFileList(onlyInPathScan, '路径扫描'),
                          _buildFileList(onlyInMediaStore, 'MediaStore'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(List<FileItem> files, String source) {
    if (files.isEmpty) {
      return const Center(
        child: Text('没有独有文件'),
      );
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  file.path,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  FileSizeFormatter.formatBytes(file.size),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
