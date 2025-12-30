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
  List<String> get imageExtensions => _getStringList('image_extensions', defaultValue: [
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
      ]);

  /// 视频文件扩展名
  List<String> get videoExtensions => _getStringList('video_extensions', defaultValue: [
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
      ]);

  /// 音频文件扩展名
  List<String> get audioExtensions => _getStringList('audio_extensions', defaultValue: [
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
      ]);

  /// 文档文件扩展名
  List<String> get documentExtensions => _getStringList('document_extensions', defaultValue: [
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
      ]);

  /// 压缩包文件扩展名
  List<String> get archiveExtensions => _getStringList('archive_extensions', defaultValue: [
        'zip',
        'rar',
        '7z',
        'tar',
        'gz',
        'bz2',
        'xz',
        'z',
        'lz',
        'lzma',
        'tgz',
        'tbz2',
      ]);

  /// APK 文件扩展名
  List<String> get apkExtensions => _getStringList('apk_extensions', defaultValue: ['apk']);

  // ==================== 会员专享文件类型（未来扩展）====================

  /// 专业图片格式（会员可用）
  /// 例如：Photoshop/Illustrator/Sketch 源文件
  List<String> get premiumImageExtensions => _getStringList('premium_image_extensions', defaultValue: [
        // 'psd',  // Photoshop
        // 'ai',   // Illustrator
        // 'sketch', // Sketch
        // 'fig',  // Figma
        // 'xd',   // Adobe XD
      ]);

  /// 专业视频格式（会员可用）
  /// 例如：RAW 视频/专业编解码器
  List<String> get premiumVideoExtensions => _getStringList('premium_video_extensions', defaultValue: [
        // 'mxf',  // Material Exchange Format
        // 'prores', // Apple ProRes
        // 'dnxhd', // Avid DNxHD
        // 'r3d',  // RED Raw
      ]);

  /// 专业音频格式（会员可用）
  /// 例如：无损音频/专业编解码器
  List<String> get premiumAudioExtensions => _getStringList('premium_audio_extensions', defaultValue: [
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

  List<String> _getStringList(String key, {required List<String> defaultValue}) {
    if (_storage == null) return defaultValue;

    try {
      final value = _storage!.getString(key);
      if (value == null) return defaultValue;

      // 支持逗号分隔的字符串
      return value.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      return defaultValue;
    }
  }
}
