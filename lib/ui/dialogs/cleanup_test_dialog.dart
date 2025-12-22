import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/utils/cleanup_test_data_generator.dart';

/// 清理规则测试对话框
/// 
/// 用于验证三条清理规则：
/// 1. 移除不存在的文件夹
/// 2. 移除type==other但实际是系统文件夹的记录
/// 3. 移除type==other且!isAddedToQuickAccess但不再满足扫描条件的记录
class CleanupTestDialog extends StatefulWidget {
  final QuickAccessPresenter presenter;

  const CleanupTestDialog({
    super.key,
    required this.presenter,
  });

  @override
  State<CleanupTestDialog> createState() => _CleanupTestDialogState();
}

class _CleanupTestDialogState extends State<CleanupTestDialog> {
  bool _isAnalyzing = false;
  bool _isCleaning = false;
  bool _isGeneratingTestData = false;
  bool _isCleaningTestData = false;
  List<_FolderAnalysis> _analysis = [];
  CleanupResult? _cleanupResult;
  CleanupTestDataGenerator? _testDataGenerator;

  @override
  void initState() {
    super.initState();
    _testDataGenerator = CleanupTestDataGenerator(widget.presenter.localSource);
    _performAnalysis();
  }

  /// 分析所有文件夹，找出需要清理的记录
  Future<void> _performAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _analysis.clear();
    });

    try {
      final allFolders = await widget.presenter.localSource.getAllFolders();
      logger.i('CleanupTest: Analyzing ${allFolders.length} folders');

      final List<_FolderAnalysis> results = [];

      for (final folder in allFolders) {
        // 规则1：检查文件夹是否存在
        final dir = Directory(folder.path);
        final exists = await dir.exists();

        // 规则2：检查type==other但实际是系统文件夹
        final isMisclassified = folder.type == QuickAccessFolderType.other &&
            SystemFoldersConfig.isSystemFolder(folder.path);

        // 规则3：检查type==other且!isAddedToQuickAccess但不再满足扫描条件
        bool isUnqualified = false;
        if (folder.type == QuickAccessFolderType.other &&
            !folder.isAddedToQuickAccess &&
            exists) {
          isUnqualified = !await _shouldKeepOtherFolder(folder.path);
        }

        // 确定清理原因
        String? cleanupReason;
        if (!exists) {
          cleanupReason = '规则1：文件夹不存在';
        } else if (isMisclassified) {
          cleanupReason = '规则2：错误分类的系统文件夹';
        } else if (isUnqualified) {
          cleanupReason = '规则3：不再满足扫描条件';
        }

        results.add(_FolderAnalysis(
          folder: folder,
          exists: exists,
          isMisclassified: isMisclassified,
          isUnqualified: isUnqualified,
          cleanupReason: cleanupReason,
        ));
      }

      setState(() {
        _analysis = results;
      });

      logger.i('CleanupTest: Analysis complete. Found ${results.where((a) => a.shouldCleanup).length} folders to clean');
    } catch (e, stackTrace) {
      logger.e('CleanupTest: Error during analysis: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  /// 判断一个other类型的文件夹是否应该保留
  Future<bool> _shouldKeepOtherFolder(String path) async {
    try {
      final dir = Directory(path);

      // 检查是否是隐藏文件夹
      final name = path.split('/').last;
      if (name.startsWith('.')) {
        return false;
      }

      // 检查文件夹是否有内容
      final entities = await dir.list().toList();
      if (entities.isEmpty) {
        return false;
      }

      // 需要至少有5个文件或2个子文件夹
      final files = entities.whereType<File>().length;
      final subDirs = entities.whereType<Directory>().length;

      return files >= 5 || subDirs >= 2;
    } catch (e) {
      logger.e('CleanupTest: Error checking folder: $e');
      return false;
    }
  }

  /// 执行清理测试（调用Presenter的performDeepScan）
  Future<void> _performCleanupTest() async {
    setState(() {
      _isCleaning = true;
      _cleanupResult = null;
    });

    try {
      logger.i('CleanupTest: Starting deep scan with cleanup');
      final scanResult = await widget.presenter.performDeepScan();
      
      setState(() {
        _cleanupResult = CleanupResult(
          removedNonExistent: scanResult.removedNonExistent,
          removedMisclassified: scanResult.removedMisclassified,
          removedUnqualified: scanResult.removedUnqualified,
        );
      });

      logger.i('CleanupTest: Cleanup completed: $_cleanupResult');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '清理完成！移除 ${_cleanupResult!.totalRemoved} 个记录',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 重新分析
      await _performAnalysis();
    } catch (e, stackTrace) {
      logger.e('CleanupTest: Error during cleanup: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isCleaning = false;
      });
    }
  }

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
            // 标题栏
            Row(
              children: [
                const Icon(Icons.science, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '清理规则测试',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '验证三条清理规则的执行情况',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // 统计信息
            _buildStatistics(),
            const SizedBox(height: 16),

            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _performAnalysis,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新分析'),
                ),
                ElevatedButton.icon(
                  onPressed: _isCleaning || _analysis.isEmpty
                      ? null
                      : _performCleanupTest,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('执行清理'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isGeneratingTestData ? null : _generateTestData,
                  icon: const Icon(Icons.science),
                  label: const Text('生成测试数据'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isCleaningTestData ? null : _cleanupTestData,
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('清除测试数据'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 清理结果显示
            if (_cleanupResult != null) _buildCleanupResult(),

            // 文件夹列表
            Expanded(
              child: _buildFolderList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    final totalFolders = _analysis.length;
    final toClean = _analysis.where((a) => a.shouldCleanup).length;
    final nonExistent = _analysis.where((a) => !a.exists).length;
    final misclassified = _analysis.where((a) => a.isMisclassified).length;
    final unqualified = _analysis.where((a) => a.isUnqualified).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分析统计',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatChip('总计', totalFolders, Colors.blue),
                _buildStatChip('需清理', toClean, Colors.orange),
                _buildStatChip('不存在', nonExistent, Colors.red),
                _buildStatChip('错误分类', misclassified, Colors.purple),
                _buildStatChip('不合格', unqualified, Colors.brown),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          count.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      label: Text(label),
    );
  }

  Widget _buildCleanupResult() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '清理结果',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('不存在的文件夹: ${_cleanupResult!.removedNonExistent}'),
            Text('错误分类的系统文件夹: ${_cleanupResult!.removedMisclassified}'),
            Text('不合格的其他文件夹: ${_cleanupResult!.removedUnqualified}'),
            Text(
              '总计移除: ${_cleanupResult!.totalRemoved}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderList() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在分析文件夹...'),
          ],
        ),
      );
    }

    if (_analysis.isEmpty) {
      return const Center(
        child: Text('没有文件夹数据'),
      );
    }

    return ListView.builder(
      itemCount: _analysis.length,
      itemBuilder: (context, index) {
        final analysis = _analysis[index];
        return _buildFolderItem(analysis);
      },
    );
  }

  Widget _buildFolderItem(_FolderAnalysis analysis) {
    final folder = analysis.folder;
    final shouldCleanup = analysis.shouldCleanup;

    return Card(
      color: shouldCleanup ? Colors.red.shade50 : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          shouldCleanup ? Icons.warning : Icons.folder,
          color: shouldCleanup ? Colors.red : Colors.grey,
        ),
        title: Text(
          folder.displayName,
          style: TextStyle(
            fontWeight: shouldCleanup ? FontWeight.bold : FontWeight.normal,
            color: shouldCleanup ? Colors.red.shade900 : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.path,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (analysis.cleanupReason != null)
              Text(
                analysis.cleanupReason!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              folder.type == QuickAccessFolderType.system ? '系统' : '其他',
              style: TextStyle(
                fontSize: 11,
                color: folder.type == QuickAccessFolderType.system
                    ? Colors.blue
                    : Colors.green,
              ),
            ),
            if (folder.isAddedToQuickAccess)
              const Text(
                '已加入',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  /// 生成测试数据
  Future<void> _generateTestData() async {
    if (_testDataGenerator == null) {
      logger.e('CleanupTest: Test data generator not initialized');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('测试数据生成器未初始化')),
        );
      }
      return;
    }

    setState(() {
      _isGeneratingTestData = true;
    });

    try {
      logger.i('CleanupTest: Generating test data');
      final result = await _testDataGenerator!.generateTestData();
      
      logger.i('CleanupTest: Test data generation result: $result');

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '测试数据生成成功！\n'
                '创建文件夹: ${result.foldersCreated}\n'
                '数据库记录: ${result.dbRecordsCreated}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('测试数据生成失败: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      // 重新加载数据并分析
      await widget.presenter.loadQuickAccessFolders();
      await _performAnalysis();

    } catch (e, stackTrace) {
      logger.e('CleanupTest: Error generating test data: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成测试数据失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isGeneratingTestData = false;
      });
    }
  }

  /// 清除测试数据
  Future<void> _cleanupTestData() async {
    if (_testDataGenerator == null) {
      logger.e('CleanupTest: Test data generator not initialized');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('测试数据生成器未初始化')),
        );
      }
      return;
    }

    // 先确认
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除测试数据'),
        content: const Text(
          '这将删除所有以 ef_ 开头的测试文件夹及其数据库记录。\n'
          '此操作不可撤销，确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isCleaningTestData = true;
    });

    try {
      logger.i('CleanupTest: Cleaning up test data');
      final result = await _testDataGenerator!.cleanupTestData();
      
      logger.i('CleanupTest: Test data cleanup result: $result');

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '测试数据清除成功！\n'
                '删除文件夹: ${result.foldersDeleted}\n'
                '删除数据库记录: ${result.dbRecordsDeleted}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('测试数据清除失败: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      // 重新加载数据并分析
      await widget.presenter.loadQuickAccessFolders();
      await _performAnalysis();

    } catch (e, stackTrace) {
      logger.e('CleanupTest: Error cleaning up test data: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除测试数据失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isCleaningTestData = false;
      });
    }
  }
}

/// 文件夹分析结果
class _FolderAnalysis {
  final QuickAccessFolder folder;
  final bool exists;
  final bool isMisclassified;
  final bool isUnqualified;
  final String? cleanupReason;

  _FolderAnalysis({
    required this.folder,
    required this.exists,
    required this.isMisclassified,
    required this.isUnqualified,
    required this.cleanupReason,
  });

  bool get shouldCleanup => cleanupReason != null;
}
