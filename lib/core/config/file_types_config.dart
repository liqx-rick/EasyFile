import 'package:easyfile/core/config/storage/config_storage.dart';
import 'package:easyfile/data/models/file_category.dart';

/// 文件类型配置类
///
/// 职责：
/// 1. 定义 EasyFile 支持的文件扩展名列表
/// 2. 支持远程动态添加新文件类型
/// 3. 支持会员解锁专业文件格式
///
/// 可扩展场景：
/// - 会员功能：解锁 PSD/AI/SKETCH 等专业格式
/// - 远程更新：添加新文件格式支持（AVIF/WEBP2/JPEG-XL）
/// - AB 测试：测试新文件类型的用户接受度
class FileTypesConfig {
  final ConfigStorage? _storage;

  FileTypesConfig({ConfigStorage? storage}) : _storage = storage;

  // ==================== 基础文件类型（免费用户可用）====================

  /// 图片文件扩展名
  List<String> get imageExtensions =>
      _getStringList('image_extensions', defaultValue: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'svg',
        'ico',
        'heic',
        'heif',
        'tiff',
        'tif',
      ]);

  /// 视频文件扩展名
  List<String> get videoExtensions =>
      _getStringList('video_extensions', defaultValue: [
        'mp4',
        'avi',
        'mkv',
        'mov',
        'wmv',
        'flv',
        'webm',
        '3gp',
        'm4v',
        'mpg',
        'mpeg',
        'rmvb',
        'rm',
        'asf',
      ]);

  /// 音频文件扩展名
  List<String> get audioExtensions =>
      _getStringList('audio_extensions', defaultValue: [
        'mp3',
        'flac',
        'wav',
        'aac',
        'm4a',
        'ogg',
        'wma',
        'ape',
        'alac',
        'opus',
        'amr',
      ]);

  /// 文档文件扩展名
  List<String> get documentExtensions =>
      _getStringList('document_extensions', defaultValue: [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
        'rtf',
        'odt',
        'ods',
        'odp',
        'csv',
        'md',
        'log', // 日志文件（与 getTextExtensions() 保持一致）
        'json', // JSON 配置文件
        'xml', // XML 配置文件
      ]);

  /// 办公文档文件扩展名（Office套件文档）
  /// 包含：Word, Excel, PowerPoint, PDF, OpenOffice/LibreOffice
  /// 用于推荐页面等需要专注办公文档的场景
  List<String> get officeDocumentExtensions =>
      _getStringList('office_document_extensions', defaultValue: [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'odt', // OpenDocument Text
        'ods', // OpenDocument Spreadsheet
        'odp', // OpenDocument Presentation
      ]);

  /// 压缩包文件扩展名
  /// 
  /// 支持的主流格式：
  /// - zip: 最常见的压缩格式
  /// - rar: Windows 流行格式
  /// - 7z: 高压缩率格式
  /// - tar/gz/bz2/xz: Linux/Unix 常见格式
  /// - tgz/tbz2: tar 的压缩组合格式
  /// 
  /// 不支持的老旧格式（已移除）：
  /// - cab: Windows 安装包专用，用户场景极少
  /// - arj/lzh: 90年代格式，已过时
  /// - z/lz/lzma: 被 xz 替代
  List<String> get archiveExtensions =>
      _getStringList('archive_extensions', defaultValue: [
        'zip',
        'rar',
        '7z',
        'tar',
        'gz',
        'bz2',
        'xz',
        'tgz',
        'tbz2',
      ]);

  /// APK 文件扩展名
  List<String> get apkExtensions =>
      _getStringList('apk_extensions', defaultValue: ['apk']);

  /// 安装包文件扩展名（支持多平台）
  /// APK (Android), EXE/MSI (Windows), DMG/PKG (macOS), DEB/RPM (Linux)
  List<String> get installerExtensions =>
      _getStringList('installer_extensions', defaultValue: [
        'apk', // Android
        'exe', // Windows executable
        'msi', // Windows installer
        'dmg', // macOS disk image
        'pkg', // macOS package
        'deb', // Debian/Ubuntu package
        'rpm', // RedHat/Fedora package
        'appimage', // Linux AppImage
        'snap', // Ubuntu Snap
        'flatpak', // Linux Flatpak
      ]);

  // ==================== 会员专享文件类型（未来扩展）====================

  /// 专业图片格式（会员可用）
  /// 例如：Photoshop/Illustrator/Sketch 源文件
  List<String> get premiumImageExtensions =>
      _getStringList('premium_image_extensions', defaultValue: [
        // 'psd',  // Photoshop
        // 'ai',   // Illustrator
        // 'sketch', // Sketch
        // 'fig',  // Figma
        // 'xd',   // Adobe XD
      ]);

  /// 专业视频格式（会员可用）
  /// 例如：RAW 视频/专业编解码器
  List<String> get premiumVideoExtensions =>
      _getStringList('premium_video_extensions', defaultValue: [
        // 'mxf',  // Material Exchange Format
        // 'prores', // Apple ProRes
        // 'dnxhd', // Avid DNxHD
        // 'r3d',  // RED Raw
      ]);

  /// 专业音频格式（会员可用）
  /// 例如：无损音频/专业编解码器
  List<String> get premiumAudioExtensions =>
      _getStringList('premium_audio_extensions', defaultValue: [
        // 'dsd',  // Direct Stream Digital
        // 'dsf',  // DSD Stream File
        // 'dff',  // DSDIFF
      ]);

  // ==================== 核心方法 ====================

  /// 根据扩展名获取文件类型分类
  FileCategory getCategoryByExtension(String extension) {
    final ext = extension.toLowerCase();

    // 基础类型检查
    if (imageExtensions.contains(ext) || premiumImageExtensions.contains(ext)) {
      return FileCategory.image;
    }
    if (videoExtensions.contains(ext) || premiumVideoExtensions.contains(ext)) {
      return FileCategory.video;
    }
    if (audioExtensions.contains(ext) || premiumAudioExtensions.contains(ext)) {
      return FileCategory.audio;
    }
    if (documentExtensions.contains(ext)) {
      return FileCategory.document;
    }
    if (archiveExtensions.contains(ext)) {
      return FileCategory.archive;
    }
    if (apkExtensions.contains(ext)) {
      return FileCategory.apk;
    }

    return FileCategory.other;
  }

  /// 获取所有支持的扩展名（包括会员格式）
  List<String> getAllSupportedExtensions({bool includePremium = false}) {
    final extensions = <String>[
      ...imageExtensions,
      ...videoExtensions,
      ...audioExtensions,
      ...documentExtensions,
      ...archiveExtensions,
      ...apkExtensions,
    ];

    if (includePremium) {
      extensions.addAll(premiumImageExtensions);
      extensions.addAll(premiumVideoExtensions);
      extensions.addAll(premiumAudioExtensions);
    }

    return extensions;
  }

  /// 检查扩展名是否需要会员权限
  bool requiresPremium(String extension) {
    final ext = extension.toLowerCase();
    return premiumImageExtensions.contains(ext) ||
        premiumVideoExtensions.contains(ext) ||
        premiumAudioExtensions.contains(ext);
  }

  // ==================== 扩展名类型判断方法 ====================

  /// 检查扩展名是否属于图片类型
  bool isImageExtension(String extension) {
    final ext = extension.toLowerCase();
    return imageExtensions.contains(ext) ||
        premiumImageExtensions.contains(ext);
  }

  /// 检查扩展名是否属于视频类型
  bool isVideoExtension(String extension) {
    final ext = extension.toLowerCase();
    return videoExtensions.contains(ext) ||
        premiumVideoExtensions.contains(ext);
  }

  /// 检查扩展名是否属于音频类型
  bool isAudioExtension(String extension) {
    final ext = extension.toLowerCase();
    return audioExtensions.contains(ext) ||
        premiumAudioExtensions.contains(ext);
  }

  /// 检查扩展名是否属于文档类型
  bool isDocumentExtension(String extension) {
    final ext = extension.toLowerCase();
    return documentExtensions.contains(ext);
  }

  /// 检查扩展名是否属于压缩包类型
  bool isArchiveExtension(String extension) {
    final ext = extension.toLowerCase();
    return archiveExtensions.contains(ext);
  }

  /// 检查扩展名是否属于 APK 类型
  bool isApkExtension(String extension) {
    final ext = extension.toLowerCase();
    return apkExtensions.contains(ext);
  }

  /// 检查扩展名是否属于安装包类型
  bool isInstallerExtension(String extension) {
    final ext = extension.toLowerCase();
    return installerExtensions.contains(ext);
  }

  // ==================== 文件名类型判断方法 ====================

  /// 检查文件是否为图片类型
  bool isImageFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isImageExtension(ext);
  }

  /// 检查文件是否为视频类型
  bool isVideoFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isVideoExtension(ext);
  }

  /// 检查文件是否为音频类型
  bool isAudioFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isAudioExtension(ext);
  }

  /// 检查文件是否为文档类型
  bool isDocumentFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isDocumentExtension(ext);
  }

  /// 检查文件是否为压缩包类型
  bool isArchiveFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isArchiveExtension(ext);
  }

  /// 检查文件是否为 APK 类型
  bool isApkFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isApkExtension(ext);
  }

  /// 检查文件是否为安装包类型
  bool isInstallerFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext.isNotEmpty && isInstallerExtension(ext);
  }

  /// 检查文件是否为 PDF 类型
  bool isPdfFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'pdf';
  }

  // ==================== 文档子类型扩展名获取 ====================

  /// 获取 PDF 文档扩展名
  List<String> getPdfExtensions() => ['pdf'];

  /// 获取 Word 文档扩展名
  List<String> getWordExtensions() => ['doc', 'docx'];

  /// 获取 Excel 表格扩展名
  List<String> getExcelExtensions() => ['xls', 'xlsx', 'csv'];

  /// 获取 PowerPoint 演示文稿扩展名
  List<String> getPptExtensions() => ['ppt', 'pptx'];

  /// 获取文本文件扩展名
  List<String> getTextExtensions() => ['txt', 'md', 'log', 'json', 'xml', 'rtf'];

  // ==================== MIME 类型映射 ====================

  /// 根据文件名获取 MIME 类型
  ///
  /// 用于 Android 分享等需要精确 MIME 类型的场景
  String getMimeType(String fileName) {
    final ext = _extractExtension(fileName);
    if (ext.isEmpty) return '*/*';

    // 图片类型
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'bmp') return 'image/bmp';
    if (ext == 'svg') return 'image/svg+xml';
    if (ext == 'heic') return 'image/heic';
    if (ext == 'heif') return 'image/heif';
    if (ext == 'ico') return 'image/x-icon';

    // 视频类型
    if (ext == 'mp4') return 'video/mp4';
    if (ext == 'avi') return 'video/x-msvideo';
    if (ext == 'mkv') return 'video/x-matroska';
    if (ext == 'mov') return 'video/quicktime';
    if (ext == 'wmv') return 'video/x-ms-wmv';
    if (ext == 'flv') return 'video/x-flv';
    if (ext == 'webm') return 'video/webm';
    if (ext == '3gp') return 'video/3gpp';
    if (ext == 'm4v') return 'video/x-m4v';
    if (ext == 'mpg' || ext == 'mpeg') return 'video/mpeg';

    // 音频类型
    if (ext == 'mp3') return 'audio/mpeg';
    if (ext == 'wav') return 'audio/wav';
    if (ext == 'flac') return 'audio/flac';
    if (ext == 'aac') return 'audio/aac';
    if (ext == 'm4a') return 'audio/mp4';
    if (ext == 'ogg') return 'audio/ogg';
    if (ext == 'opus') return 'audio/opus';
    if (ext == 'wma') return 'audio/x-ms-wma';
    if (ext == 'ape') return 'audio/ape';
    if (ext == 'alac') return 'audio/alac';

    // 文档类型
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'doc') return 'application/msword';
    if (ext == 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext == 'xls') return 'application/vnd.ms-excel';
    if (ext == 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (ext == 'ppt') return 'application/vnd.ms-powerpoint';
    if (ext == 'pptx') {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (ext == 'txt') return 'text/plain';
    if (ext == 'rtf') return 'application/rtf';
    if (ext == 'odt') return 'application/vnd.oasis.opendocument.text';
    if (ext == 'ods') return 'application/vnd.oasis.opendocument.spreadsheet';
    if (ext == 'odp') return 'application/vnd.oasis.opendocument.presentation';
    if (ext == 'csv') return 'text/csv';
    if (ext == 'md') return 'text/markdown';

    // 压缩包类型
    if (ext == 'zip') return 'application/zip';
    if (ext == 'rar') return 'application/x-rar-compressed';
    if (ext == '7z') return 'application/x-7z-compressed';
    if (ext == 'tar') return 'application/x-tar';
    if (ext == 'gz') return 'application/gzip';
    if (ext == 'bz2') return 'application/x-bzip2';
    if (ext == 'xz') return 'application/x-xz';

    // APK
    if (ext == 'apk') return 'application/vnd.android.package-archive';

    // 通用类型（用于图片分类但非标准 MIME）
    if (isImageExtension(ext)) return 'image/$ext';
    if (isVideoExtension(ext)) return 'video/$ext';
    if (isAudioExtension(ext)) return 'audio/$ext';
    if (isDocumentExtension(ext)) return 'application/$ext';
    if (isArchiveExtension(ext)) return 'application/$ext';

    // 默认类型
    return '*/*';
  }

  /// 获取简化的 MIME 类型（用于分类显示）
  ///
  /// 与 getMimeType 不同，这个方法返回的是用于 UI 展示的简化类型
  /// 例如：'image/jpeg' 的简化类型是 'image/jpg'
  String getSimplifiedMimeType(String fileName) {
    final ext = _extractExtension(fileName);
    if (ext.isEmpty) return 'application/octet-stream';

    // 使用分类进行简化映射
    if (isImageExtension(ext)) return 'image/$ext';
    if (isVideoExtension(ext)) return 'video/$ext';
    if (isAudioExtension(ext)) return 'audio/$ext';
    if (isDocumentExtension(ext)) return 'application/$ext';
    if (isArchiveExtension(ext)) return 'application/$ext';
    if (isApkExtension(ext)) return 'application/apk';

    return 'application/octet-stream';
  }

  /// 根据 MIME 类型获取合适的文件扩展名（反向映射）
  ///
  /// 用于回收站文件恢复时根据 MIME 类型推测扩展名
  /// 返回带点的扩展名（例如：'.jpg'）
  String getExtensionFromMimeType(String mimeType) {
    final lower = mimeType.toLowerCase();

    // 图片
    if (lower.contains('jpeg') || lower.contains('jpg')) return '.jpg';
    if (lower.contains('png')) return '.png';
    if (lower.contains('gif')) return '.gif';
    if (lower.contains('webp')) return '.webp';
    if (lower.contains('bmp')) return '.bmp';
    if (lower.contains('heic') || lower.contains('heif')) return '.heic';
    if (lower.contains('svg')) return '.svg';

    // 视频
    if (lower.contains('mp4')) return '.mp4';
    if (lower.contains('avi')) return '.avi';
    if (lower.contains('mov') || lower.contains('quicktime')) return '.mov';
    if (lower.contains('mkv') || lower.contains('matroska')) return '.mkv';
    if (lower.contains('webm')) return '.webm';
    if (lower.contains('3gp')) return '.3gp';
    if (lower.contains('wmv')) return '.wmv';
    if (lower.contains('flv')) return '.flv';

    // 音频
    if (lower.contains('mp3') || lower.contains('mpeg')) return '.mp3';
    if (lower.contains('wav')) return '.wav';
    if (lower.contains('flac')) return '.flac';
    if (lower.contains('aac')) return '.aac';
    if (lower.contains('ogg')) return '.ogg';
    if (lower.contains('m4a')) return '.m4a';
    if (lower.contains('opus')) return '.opus';

    // 文档
    if (lower.contains('pdf')) return '.pdf';
    if (lower.contains('word') ||
        lower.contains('msword') ||
        lower.contains('doc')) {
      return '.docx';
    }
    if (lower.contains('excel') ||
        lower.contains('ms-excel') ||
        lower.contains('xls')) {
      return '.xlsx';
    }
    if (lower.contains('powerpoint') ||
        lower.contains('ms-powerpoint') ||
        lower.contains('ppt')) {
      return '.pptx';
    }
    if (lower.contains('text/plain') || lower.contains('txt')) return '.txt';
    if (lower.contains('markdown')) return '.md';
    if (lower.contains('csv')) return '.csv';

    // 压缩
    if (lower.contains('zip')) return '.zip';
    if (lower.contains('rar')) return '.rar';
    if (lower.contains('7z')) return '.7z';
    if (lower.contains('tar')) return '.tar';
    if (lower.contains('gzip')) return '.gz';

    // APK
    if (lower.contains('android.package-archive') || lower.contains('apk')) {
      return '.apk';
    }

    // 默认
    return '.file';
  }

  // ==================== UI 分类判断方法（用于图标显示）====================

  /// 判断是否为 Word 文档类型
  bool isWordDocument(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'doc' || ext == 'docx';
  }

  /// 判断是否为 Excel 表格类型
  bool isExcelDocument(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'xls' || ext == 'xlsx' || ext == 'csv';
  }

  /// 判断是否为 PowerPoint 演示文档类型
  bool isPowerPointDocument(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'ppt' || ext == 'pptx';
  }

  /// 判断是否为文本文件（不包括CSV）
  bool isTextFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'txt' || ext == 'log' || ext == 'md' || ext == 'rtf';
  }

  /// 判断是否为代码文件
  bool isCodeFile(String fileName) {
    final ext = _extractExtension(fileName);
    return const [
      'java',
      'kt',
      'dart',
      'py',
      'js',
      'ts',
      'html',
      'css',
      'cpp',
      'c',
      'h',
      'hpp',
      'swift',
      'go',
      'rs',
      'php',
      'rb'
    ].contains(ext);
  }

  /// 判断是否为配置文件
  bool isConfigFile(String fileName) {
    final ext = _extractExtension(fileName);
    return const [
      'json',
      'xml',
      'yaml',
      'yml',
      'ini',
      'conf',
      'config',
      'toml',
      'properties'
    ].contains(ext);
  }

  /// 判断是否为数据库文件
  bool isDatabaseFile(String fileName) {
    final ext = _extractExtension(fileName);
    return ext == 'db' || ext == 'sqlite' || ext == 'sql';
  }

  /// 获取文件类型描述（中文）
  String getFileTypeDescription(String fileName) {
    if (isImageFile(fileName)) return '图片';
    if (isVideoFile(fileName)) return '视频';
    if (isAudioFile(fileName)) return '音频';
    if (isPdfFile(fileName)) return 'PDF文档';
    if (isWordDocument(fileName)) return 'Word文档';
    if (isExcelDocument(fileName)) return 'Excel表格';
    if (isPowerPointDocument(fileName)) return '演示文稿';
    if (isTextFile(fileName)) return '文本文件';
    if (isArchiveFile(fileName)) return '压缩包';
    if (isApkFile(fileName)) return 'APK文件';
    if (isCodeFile(fileName)) return '代码文件';
    if (isConfigFile(fileName)) return '配置文件';
    if (isDatabaseFile(fileName)) return '数据库文件';
    return '其他文件';
  }

  // ==================== 远程配置更新 ====================

  /// 合并远程配置（用于动态添加文件类型）
  ///
  /// 示例：
  /// ```dart
  /// await fileTypesConfig.mergeWith({
  ///   'image_extensions': ['jpg', 'png', 'avif', 'jpeg-xl'], // 添加新格式
  ///   'premium_image_extensions': ['psd', 'ai'],  // 会员格式
  /// });
  /// ```
  Future<void> mergeWith(Map<String, dynamic> updates) async {
    if (_storage == null) return;
    await _storage!.setAll(updates);
  }

  // ==================== 私有辅助方法 ====================

  /// 常见的备份/临时文件后缀
  /// 当文件以这些后缀结尾时，会尝试检查倒数第二个扩展名
  static const _backupSuffixes = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', // 数字后缀（下载管理器常用）
    'bak', 'backup', 'old', 'tmp', 'temp', // 备份/临时后缀
  ];

  /// 从文件名中提取扩展名（支持双扩展名智能识别）
  ///
  /// **智能识别规则**：
  /// 1. 优先使用最后一个扩展名
  /// 2. 如果最后扩展名是备份后缀（.1, .bak等），则检查倒数第二个扩展名
  /// 3. 只对重要文件类型（APK、文档、压缩包、媒体）启用双扩展名识别
  ///
  /// **示例**：
  /// - `app.apk.1` → 先检查 `1`（不支持） → 再检查 `apk`（支持）→ 返回 `apk`
  /// - `photo.jpg.2` → 先检查 `2`（不支持） → 再检查 `jpg`（支持）→ 返回 `jpg`
  /// - `file.xyz.1` → 先检查 `1`（不支持） → 再检查 `xyz`（不支持）→ 返回 `1`（保持原逻辑）
  /// - `normal.pdf` → 只有一个扩展名 → 返回 `pdf`
  String _extractExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return '';
    }

    final lastExt = fileName.substring(lastDot + 1).toLowerCase();

    // 如果最后扩展名不是备份后缀，直接返回
    if (!_backupSuffixes.contains(lastExt)) {
      return lastExt;
    }

    // 最后扩展名是备份后缀，尝试获取倒数第二个扩展名
    final beforeLastDot = fileName.lastIndexOf('.', lastDot - 1);
    if (beforeLastDot == -1) {
      // 只有一个点，返回最后扩展名
      return lastExt;
    }

    final secondLastExt =
        fileName.substring(beforeLastDot + 1, lastDot).toLowerCase();

    // 检查倒数第二个扩展名是否是我们支持的类型
    // 这样避免误判（例如 data.json.1 不应该被识别为 JSON）
    if (_isSupportedExtension(secondLastExt)) {
      return secondLastExt;
    }

    // 倒数第二个扩展名也不支持，返回最后扩展名（保持原逻辑）
    return lastExt;
  }

  /// 检查扩展名是否是支持的类型
  bool _isSupportedExtension(String ext) {
    return imageExtensions.contains(ext) ||
        videoExtensions.contains(ext) ||
        audioExtensions.contains(ext) ||
        documentExtensions.contains(ext) ||
        archiveExtensions.contains(ext) ||
        apkExtensions.contains(ext) ||
        premiumImageExtensions.contains(ext) ||
        premiumVideoExtensions.contains(ext) ||
        premiumAudioExtensions.contains(ext);
  }

  List<String> _getStringList(String key,
      {required List<String> defaultValue}) {
    if (_storage == null) return defaultValue;

    try {
      final value = _storage!.getString(key);
      if (value == null) return defaultValue;

      // 支持逗号分隔的字符串
      return value
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      return defaultValue;
    }
  }
}
