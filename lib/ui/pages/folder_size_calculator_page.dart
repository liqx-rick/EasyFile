import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/folder_size_calculator_service.dart';
import 'package:easyfile/ui/widgets/scan_path_picker_dialog.dart';
import 'package:flutter/material.dart';

/// 文件夹大小计算工具页面
///
/// 功能：
/// - 选择文件夹并计算总大小
/// - 显示文件夹信息（名称、路径、大小、文件数、子文件夹数）
/// - 支持刷新重新计算
/// - 异步计算，显示进度指示器
class FolderSizeCalculatorPage extends StatefulWidget {
  const FolderSizeCalculatorPage({super.key});

  @override
  State<FolderSizeCalculatorPage> createState() => _FolderSizeCalculatorPageState();
}

class _FolderSizeCalculatorPageState extends State<FolderSizeCalculatorPage> {
  final FolderSizeCalculatorService _calculatorService = FolderSizeCalculatorService();

  // 计算结果
  FolderSizeResult? _result;

  // UI 状态
  bool _isCalculating = false;
  int _processedFiles = 0;
  String _currentPath = '';

  @override
  void initState() {
    super.initState();
    // 埋点：进入文件夹大小计算工具页面
    AnalyticsHelper.logFolderSizeCalculatorEnter();
  }

  /// 选择文件夹
  Future<void> _pickFolder() async {
    try {
      logger.d('打开文件夹选择器...');

      final result = await ScanPathPickerDialog.show(
        context,
        initialPath: '/storage/emulated/0',
      );

      if (result == null) {
        logger.d('用户取消选择文件夹');
        return;
      }

      logger.d('用户选择文件夹: $result');

      setState(() {
        _result = null; // 清空之前的结果
        _processedFiles = 0;
        _currentPath = '';
      });

      // 开始计算
      await _calculateSize(result);
    } catch (e, stackTrace) {
      logger.e('选择文件夹失败: $e\nStackTrace: $stackTrace');
      _showSnackBar('选择文件夹失败: $e');
    }
  }

  /// 计算文件夹大小
  Future<void> _calculateSize(String folderPath) async {
    setState(() {
      _isCalculating = true;
      _processedFiles = 0;
      _currentPath = '';
    });

    try {
      logger.d('开始计算文件夹大小...');

      final result = await _calculatorService.calculateFolderSize(
        folderPath,
        onProgress: (processedFiles, currentPath) {
          setState(() {
            _processedFiles = processedFiles;
            _currentPath = _getShortPath(currentPath);
          });
        },
      );

      setState(() {
        _result = result;
        _isCalculating = false;
      });

      logger.d('文件夹大小计算完成');

      // 埋点：计算完成
      AnalyticsHelper.logFolderSizeCalculateFinish(
        folderSizeBytes: result.totalBytes,
        fileCount: result.fileCount,
        durationMs: result.calculationTime.inMilliseconds,
      );

      _showSnackBar('计算完成，耗时 ${result.calculationTime.inSeconds} 秒');
    } catch (e, stackTrace) {
      logger.e('计算文件夹大小失败: $e\nStackTrace: $stackTrace');
      setState(() {
        _isCalculating = false;
      });
      _showSnackBar('计算失败: $e');
    }
  }

  /// 刷新计算
  Future<void> _refresh() async {
    if (_result == null || _isCalculating) return;
    await _calculateSize(_result!.folderPath);
  }

  /// 获取简短路径（仅显示最后两级）
  String _getShortPath(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    if (parts.length <= 2) return path;
    return '.../${parts[parts.length - 2]}/${parts.last}';
  }

  /// 显示提示消息
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹大小计算'),
        actions: [
          if (_result != null && !_isCalculating)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: '刷新',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选择文件夹按钮
            _buildSelectFolderButton(theme),
            const SizedBox(height: 24),

            // 计算进度指示器
            if (_isCalculating) ...[
              _buildProgressIndicator(theme),
              const SizedBox(height: 24),
            ],

            // 结果卡片
            if (_result != null && !_isCalculating) ...[
              _buildResultCard(theme),
              const SizedBox(height: 16),
            ],

            // 使用说明
            if (_result == null && !_isCalculating) ...[
              _buildInstructions(theme),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建选择文件夹按钮
  Widget _buildSelectFolderButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: _isCalculating ? null : _pickFolder,
      icon: const Icon(Icons.folder_open, size: 28),
      label: Text(
        _result == null ? '选择文件夹' : '重新选择文件夹',
        style: const TextStyle(fontSize: 18),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// 构建进度指示器
  Widget _buildProgressIndicator(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在计算文件夹大小...',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '已处理 $_processedFiles 个文件',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            if (_currentPath.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _currentPath,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建结果卡片
  Widget _buildResultCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.folder, color: Colors.blue[700], size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _result!.folderName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 路径
            _buildInfoRow(
              icon: Icons.location_on,
              label: '路径',
              value: _result!.folderPath,
              valueStyle: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),

            // 总大小（突出显示）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    '总大小',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result!.formattedSize,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),

            // 文件数量
            _buildInfoRow(
              icon: Icons.insert_drive_file,
              label: '文件总数',
              value: '${_result!.fileCount} 个',
            ),
            const SizedBox(height: 12),

            // 子文件夹数量
            _buildInfoRow(
              icon: Icons.folder_open,
              label: '子文件夹',
              value: '${_result!.folderCount} 个',
            ),
            const SizedBox(height: 12),

            // 计算耗时
            _buildInfoRow(
              icon: Icons.timer,
              label: '计算耗时',
              value: '${_result!.calculationTime.inSeconds} 秒',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  /// 构建使用说明
  Widget _buildInstructions(ThemeData theme) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  '使用说明',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInstructionItem('1. 点击"选择文件夹"按钮选择要计算的文件夹'),
            const SizedBox(height: 6),
            _buildInstructionItem('2. 等待计算完成（大文件夹可能需要一些时间）'),
            const SizedBox(height: 6),
            _buildInstructionItem('3. 查看文件夹的详细信息和总大小'),
            const SizedBox(height: 6),
            _buildInstructionItem('4. 点击右上角刷新按钮可重新计算'),
          ],
        ),
      ),
    );
  }

  /// 构建说明项
  Widget _buildInstructionItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
