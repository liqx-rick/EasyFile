/// 文件来源枚举
enum FileSource {
  download, // 浏览器/应用市场下载
  wechat, // 微信下载/保存
  qq, // QQ文件
  camera, // 相机拍摄
  screenshots, // 屏幕截图
  recordings, // 录音/录屏
  documents, // 文档编辑生成
  bluetooth, // 蓝牙接收
  dingtalk, // 钉钉
  wework, // 企业微信
  baidunetdisk, // 百度网盘
  quark, // 夸克浏览器
  uc, // UC浏览器
  sharereceive, // 其他应用分享接收
  easycopy, // EasyFile复制
  easymove, // EasyFile移动
  custom, // 自定义路径
  unknown, // 未知来源
}

/// FileSource 扩展方法
extension FileSourceExtension on FileSource {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case FileSource.download:
        return '下载';
      case FileSource.wechat:
        return '微信';
      case FileSource.qq:
        return 'QQ';
      case FileSource.camera:
        return '相机';
      case FileSource.screenshots:
        return '截屏';
      case FileSource.recordings:
        return '录音';
      case FileSource.documents:
        return '文档';
      case FileSource.bluetooth:
        return '蓝牙';
      case FileSource.dingtalk:
        return '钉钉';
      case FileSource.wework:
        return '企业微信';
      case FileSource.baidunetdisk:
        return '百度网盘';
      case FileSource.quark:
        return '夸克';
      case FileSource.uc:
        return 'UC浏览器';
      case FileSource.sharereceive:
        return '接收';
      case FileSource.easycopy:
        return '复制';
      case FileSource.easymove:
        return '移动';
      case FileSource.custom:
        return '自定义';
      case FileSource.unknown:
        return '未知';
    }
  }

  /// 获取简短名称（用于标签）
  String get shortName {
    switch (this) {
      case FileSource.baidunetdisk:
        return '网盘';
      case FileSource.wework:
        return '企微';
      case FileSource.sharereceive:
        return '接收';
      case FileSource.easycopy:
        return '复制';
      case FileSource.easymove:
        return '移动';
      default:
        return displayName;
    }
  }

  /// 获取图标名称
  String get iconName {
    switch (this) {
      case FileSource.download:
        return 'download';
      case FileSource.wechat:
        return 'wechat';
      case FileSource.qq:
        return 'qq';
      case FileSource.camera:
        return 'camera';
      case FileSource.screenshots:
        return 'screenshot';
      case FileSource.recordings:
        return 'mic';
      case FileSource.documents:
        return 'document';
      case FileSource.bluetooth:
        return 'bluetooth';
      case FileSource.dingtalk:
        return 'dingtalk';
      case FileSource.wework:
        return 'work';
      case FileSource.baidunetdisk:
        return 'cloud';
      case FileSource.quark:
        return 'browser';
      case FileSource.uc:
        return 'browser';
      case FileSource.sharereceive:
        return 'share';
      case FileSource.easycopy:
        return 'copy';
      case FileSource.easymove:
        return 'move';
      case FileSource.custom:
        return 'folder';
      case FileSource.unknown:
        return 'unknown';
    }
  }
}
