import 'dart:io';
import 'dart:ui' as ui;

import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// 二维码生成与扫描工具页面
///
/// 功能：
/// - 生成二维码：输入文本/链接，生成二维码，保存/分享
/// - 扫描二维码：启动摄像头，识别二维码，显示结果，复制/打开链接
class QrCodeToolPage extends StatefulWidget {
  const QrCodeToolPage({super.key});

  @override
  State<QrCodeToolPage> createState() => _QrCodeToolPageState();
}

class _QrCodeToolPageState extends State<QrCodeToolPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 生成二维码相关
  final TextEditingController _inputController = TextEditingController();
  String _qrData = '';
  final GlobalKey _qrKey = GlobalKey();
  bool _isGenerating = false;

  // 扫描二维码相关
  MobileScannerController? _scannerController;
  String _scanResult = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 埋点：进入二维码工具页面
    AnalyticsHelper.logQrCodeToolEnter();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  /// 生成二维码
  void _generateQrCode() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请输入要生成二维码的内容');
      return;
    }

    setState(() {
      _qrData = text;
      _isGenerating = true;
    });

    // 埋点：生成二维码
    AnalyticsHelper.logQrCodeGenerate(contentLength: text.length);

    // 模拟生成过程
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        _showSnackBar('二维码生成成功');
      }
    });
  }

  /// 保存二维码到相册
  Future<void> _saveQrCode() async {
    if (_qrData.isEmpty) {
      _showSnackBar('请先生成二维码');
      return;
    }

    try {
      logger.d('开始保存二维码...');

      // 获取二维码 widget 的渲染对象
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('无法获取二维码渲染对象');
      }

      // 转换为图片
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('无法转换图片数据');
      }

      // 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${tempDir.path}/qrcode_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      logger.d('二维码已保存到临时文件: $filePath');

      // 保存到相册
      await Gal.putImage(filePath);

      logger.d('二维码已保存到相册');
      _showSnackBar('二维码已保存到相册');

      // 埋点：保存二维码
      AnalyticsHelper.logQrCodeSave();
    } catch (e, stackTrace) {
      logger.e('保存二维码失败: $e\nStackTrace: $stackTrace');
      _showSnackBar('保存失败: $e');
    }
  }

  /// 处理扫描结果
  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final result = barcode.rawValue ?? '';

    if (result.isEmpty || result == _scanResult) return;

    setState(() {
      _scanResult = result;
    });

    logger.d('扫描到二维码: $result');

    // 埋点：扫描二维码
    AnalyticsHelper.logQrCodeScan(contentLength: result.length);

    // 震动反馈
    HapticFeedback.mediumImpact();

    _showSnackBar('扫描成功');
  }

  /// 复制扫描结果
  Future<void> _copyScanResult() async {
    if (_scanResult.isEmpty) {
      _showSnackBar('暂无扫描结果');
      return;
    }

    await Clipboard.setData(ClipboardData(text: _scanResult));
    _showSnackBar('已复制到剪贴板');

    // 埋点：复制扫描结果
    AnalyticsHelper.logQrCodeCopyScanResult();
  }

  /// 打开链接
  Future<void> _openUrl() async {
    if (_scanResult.isEmpty) {
      _showSnackBar('暂无扫描结果');
      return;
    }

    if (!_isUrl(_scanResult)) {
      _showSnackBar('扫描结果不是有效的链接');
      return;
    }

    try {
      final uri = Uri.parse(_scanResult);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // 埋点：打开链接
        AnalyticsHelper.logQrCodeOpenUrl();
      } else {
        _showSnackBar('无法打开链接');
      }
    } catch (e) {
      logger.e('打开链接失败: $e');
      _showSnackBar('打开链接失败: $e');
    }
  }

  /// 判断是否是URL
  bool _isUrl(String text) {
    return text.startsWith('http://') || text.startsWith('https://');
  }

  /// 从图片识别二维码
  Future<void> _pickImageAndScan() async {
    try {
      logger.d('打开图片选择器...');

      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (pickerResult == null || pickerResult.files.isEmpty) {
        logger.d('用户取消选择图片');
        return;
      }

      final filePath = pickerResult.files.first.path;
      if (filePath == null) {
        _showSnackBar('无法获取图片路径');
        return;
      }

      logger.d('选择的图片: $filePath');

      // 显示加载提示
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在识别二维码...'),
                ],
              ),
            ),
          ),
        ),
      );

      // 确保扫描器已初始化
      _scannerController ??= MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );

      // 分析图片中的二维码
      final capture = await _scannerController!.analyzeImage(filePath);

      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (capture == null || capture.barcodes.isEmpty) {
        logger.d('图片中未识别到二维码');
        _showSnackBar('未识别到二维码，请选择包含二维码的图片');
        return;
      }

      final barcode = capture.barcodes.first;
      final qrContent = barcode.rawValue ?? '';

      if (qrContent.isEmpty) {
        _showSnackBar('二维码内容为空');
        return;
      }

      setState(() {
        _scanResult = qrContent;
      });

      logger.d('从图片识别到二维码: $qrContent');

      // 埋点：扫描图片二维码
      AnalyticsHelper.logQrCodeScanFromImage(contentLength: qrContent.length);

      // 震动反馈
      HapticFeedback.mediumImpact();

      _showSnackBar('识别成功');
    } catch (e, stackTrace) {
      logger.e('从图片识别二维码失败: $e\nStackTrace: $stackTrace');

      // 关闭加载对话框（如果还在显示）
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      _showSnackBar('识别失败: $e');
    }
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
        title: const Text('二维码工具'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: '生成'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: '扫描'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGenerateTab(theme),
          _buildScanTab(theme),
        ],
      ),
    );
  }

  /// 构建生成二维码页面
  Widget _buildGenerateTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 输入提示
          Text(
            '输入文本或链接',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // 输入框
          TextField(
            controller: _inputController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '例如：https://www.example.com\n或任意文本内容',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
            ),
          ),
          const SizedBox(height: 16),

          // 生成按钮
          ElevatedButton.icon(
            onPressed: _isGenerating ? null : _generateQrCode,
            icon: _isGenerating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code),
            label: Text(_isGenerating ? '生成中...' : '生成二维码'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 二维码显示区域
          if (_qrData.isNotEmpty) ...[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // 二维码
                    RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: QrImageView(
                          data: _qrData,
                          version: QrVersions.auto,
                          size: 250,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 内容预览
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _qrData,
                        style: theme.textTheme.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 操作按钮
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saveQrCode,
                            icon: const Icon(Icons.save),
                            label: const Text('保存到相册'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 使用提示
          if (_qrData.isEmpty) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.blue.shade700),
                    const SizedBox(height: 12),
                    Text(
                      '使用提示',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('1. 在输入框中输入文本或链接'),
                    const SizedBox(height: 4),
                    const Text('2. 点击"生成二维码"按钮'),
                    const SizedBox(height: 4),
                    const Text('3. 保存二维码到相册'),
                    const SizedBox(height: 12),
                    Text(
                      '💡 提示',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '切换到"扫描"页面可以扫描二维码或从相册选择图片识别',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建扫描二维码页面
  Widget _buildScanTab(ThemeData theme) {
    // 延迟初始化扫描器
    _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );

    return Column(
      children: [
        // 扫描器预览
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController!,
                onDetect: _onDetect,
              ),
              // 扫描框
              Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.green,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              // 提示文字
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  '将二维码放入框内',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
              // 从相册选择按钮
              Positioned(
                bottom: 50,
                right: 10,
                child: FloatingActionButton(
                  mini: true,
                  onPressed: _pickImageAndScan,
                  backgroundColor: Colors.white,
                  tooltip: '从相册选择',
                  child: const Icon(Icons.photo_library, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),

        // 扫描结果显示区域
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '扫描结果',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // 结果显示
                Expanded(
                  child: _scanResult.isEmpty
                      ? Center(
                          child: Text(
                            '暂无扫描结果',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SelectableText(
                              _scanResult,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // 操作按钮
                if (_scanResult.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyScanResult,
                          icon: const Icon(Icons.copy, size: 20),
                          label: const Text('复制'),
                        ),
                      ),
                      if (_isUrl(_scanResult)) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openUrl,
                            icon: const Icon(Icons.open_in_browser, size: 20),
                            label: const Text('打开链接'),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
