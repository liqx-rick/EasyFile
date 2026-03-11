import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/hash_calculator_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Hash 校验工具页面
///
/// 功能：
/// - 选择文件并计算 MD5、SHA1、SHA256 哈希值
/// - 显示文件信息（名称、大小）
/// - 支持复制哈希值到剪贴板
/// - 异步计算，显示进度指示器
class HashCheckerPage extends StatefulWidget {
  const HashCheckerPage({super.key});

  @override
  State<HashCheckerPage> createState() => _HashCheckerPageState();
}

class _HashCheckerPageState extends State<HashCheckerPage> {
  final HashCalculatorService _hashService = HashCalculatorService();

  // 文件信息
  String? _filePath;
  String? _fileName;
  int? _fileSize;

  // Hash 结果
  HashResult? _hashResult;

  // UI 状态
  bool _isCalculating = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    // 埋点：进入 Hash 校验工具页面
    AnalyticsHelper.logHashCheckerEnter();
  }

  /// 选择文件
  Future<void> _pickFile() async {
    try {
      logger.d('打开文件选择器...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        logger.d('用户取消选择文件');
        return;
      }

      final file = result.files.first;
      final filePath = file.path;

      if (filePath == null) {
        _showSnackBar('无法获取文件路径');
        return;
      }

      logger.d('用户选择文件: $filePath');

      setState(() {
        _filePath = filePath;
        _fileName = path.basename(filePath);
        _fileSize = file.size;
        _hashResult = null; // 清空之前的结果
        _progress = 0.0;
      });

      // 开始计算 Hash
      await _calculateHash();
    } catch (e, stackTrace) {
      logger.e('选择文件失败: $e\nStackTrace: $stackTrace');
      _showSnackBar('选择文件失败: $e');
    }
  }

  /// 计算文件 Hash
  Future<void> _calculateHash() async {
    if (_filePath == null) return;

    setState(() {
      _isCalculating = true;
      _progress = 0.0;
    });

    try {
      logger.d('开始计算 Hash...');

      final result = await _hashService.calculateFileHash(
        _filePath!,
        onProgress: (bytesRead, totalBytes) {
          setState(() {
            _progress = bytesRead / totalBytes;
          });
        },
      );

      setState(() {
        _hashResult = result;
        _isCalculating = false;
      });

      logger.d('Hash 计算完成');

      // 埋点：Hash 计算完成
      AnalyticsHelper.logHashCalculateFinish(
        fileSizeBytes: _fileSize ?? 0,
        durationMs: result.calculationTime.inMilliseconds,
      );

      _showSnackBar('计算完成，耗时 ${result.calculationTime.inMilliseconds} 毫秒');
    } catch (e, stackTrace) {
      logger.e('计算 Hash 失败: $e\nStackTrace: $stackTrace');
      setState(() {
        _isCalculating = false;
      });
      _showSnackBar('计算失败: $e');
    }
  }

  /// 复制 Hash 到剪贴板
  Future<void> _copyToClipboard(String text, String hashType) async {
    await Clipboard.setData(ClipboardData(text: text));

    // 埋点：Hash 值复制
    AnalyticsHelper.logHashCopy(hashType);

    _showSnackBar('$hashType 已复制到剪贴板');
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

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hash 校验工具'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选择文件按钮
            _buildSelectFileButton(theme),
            const SizedBox(height: 24),

            // 文件信息卡片
            if (_fileName != null) ...[
              _buildFileInfoCard(theme),
              const SizedBox(height: 24),
            ],

            // 计算进度指示器
            if (_isCalculating) ...[
              _buildProgressIndicator(theme),
              const SizedBox(height: 24),
            ],

            // Hash 结果列表
            if (_hashResult != null && !_isCalculating) ...[
              _buildHashResultsCard(theme),
              const SizedBox(height: 16),
            ],

            // 使用说明
            if (_fileName == null) ...[
              _buildInstructions(theme),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建选择文件按钮
  Widget _buildSelectFileButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: _isCalculating ? null : _pickFile,
      icon: const Icon(Icons.folder_open, size: 28),
      label: Text(
        _fileName == null ? '选择文件' : '重新选择文件',
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

  /// 构建文件信息卡片
  Widget _buildFileInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文件信息',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.insert_drive_file,
              label: '文件名',
              value: _fileName!,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.storage,
              label: '文件大小',
              value: _formatFileSize(_fileSize ?? 0),
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
  }) {
    return Row(
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
            style: const TextStyle(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 构建进度指示器
  Widget _buildProgressIndicator(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              '正在计算 Hash...',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 Hash 结果卡片
  Widget _buildHashResultsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hash 校验值',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildHashItem(
              type: 'MD5',
              hash: _hashResult!.md5,
              color: Colors.blue,
            ),
            const Divider(height: 24),
            _buildHashItem(
              type: 'SHA1',
              hash: _hashResult!.sha1,
              color: Colors.green,
            ),
            const Divider(height: 24),
            _buildHashItem(
              type: 'SHA256',
              hash: _hashResult!.sha256,
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 Hash 项
  Widget _buildHashItem({
    required String type,
    required String hash,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              type,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => _copyToClipboard(hash, type),
              tooltip: '复制 $type',
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: SelectableText(
            hash,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 0.3,
            ),
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  /// 构建使用说明
  Widget _buildInstructions(ThemeData theme) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  '使用说明',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInstructionItem('1. 点击"选择文件"按钮选择要校验的文件'),
            const SizedBox(height: 6),
            _buildInstructionItem('2. 等待 Hash 计算完成'),
            const SizedBox(height: 6),
            _buildInstructionItem('3. 点击复制按钮可复制对应的 Hash 值'),
            const SizedBox(height: 6),
            _buildInstructionItem('4. 支持 MD5、SHA1、SHA256 三种算法'),
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
