import 'package:easyfile/data/models/file_source.dart';

/// 文件来源检测器
/// 根据文件路径自动识别文件来源
class FileSourceDetector {
  /// 检测文件来源
  static FileSource detectSource(String filePath) {
    if (filePath.isEmpty) return FileSource.unknown;

    final lowerPath = filePath.toLowerCase();

    // 系统下载
    if (lowerPath.contains('/download')) {
      return FileSource.download;
    }

    // 微信
    if (lowerPath.contains('/tencent/micromsg')) {
      return FileSource.wechat;
    }

    // QQ
    if (lowerPath.contains('/tencent/qqfile_recv') ||
        lowerPath.contains('/tencent/qq_')) {
      return FileSource.qq;
    }

    // 钉钉
    if (lowerPath.contains('/dingtalk')) {
      return FileSource.dingtalk;
    }

    // 企业微信
    if (lowerPath.contains('/wxwork') || lowerPath.contains('/wework')) {
      return FileSource.wework;
    }

    // 百度网盘
    if (lowerPath.contains('/baidunetdisk')) {
      return FileSource.baidunetdisk;
    }

    // 夸克
    if (lowerPath.contains('/quark')) {
      return FileSource.quark;
    }

    // UC浏览器
    if (lowerPath.contains('/ucdownloads')) {
      return FileSource.uc;
    }

    // 相机
    if (lowerPath.contains('/dcim/camera')) {
      return FileSource.camera;
    }

    // 截屏
    if (lowerPath.contains('/screenshots')) {
      return FileSource.screenshots;
    }

    // 录音
    if (lowerPath.contains('/recordings') || lowerPath.contains('/sounds')) {
      return FileSource.recordings;
    }

    // 文档
    if (lowerPath.contains('/documents')) {
      return FileSource.documents;
    }

    // 蓝牙
    if (lowerPath.contains('/bluetooth')) {
      return FileSource.bluetooth;
    }

    // 未知来源
    return FileSource.unknown;
  }

  /// 获取路径的显示名称（取最后一段有意义的部分）
  static String getPathDisplayName(String path) {
    final segments = path.split('/');
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }
}
