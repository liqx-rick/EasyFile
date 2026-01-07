import 'package:easyfile/core/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';

void main() {
  group('FileSourceDetector', () {
    group('层级1 - 系统目录根路径识别', () {
      test('识别下载目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/test.jpg',
        );
        expect(result, equals('下载'));
      });

      test('识别图片目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Pictures/photo.png',
        );
        expect(result, equals('图片'));
      });

      test('识别相机目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/DCIM/image.jpg',
        );
        expect(result, equals('相机'));
      });

      test('识别音乐目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Music/song.mp3',
        );
        expect(result, equals('音乐'));
      });

      test('识别视频目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Movies/video.mp4',
        );
        expect(result, equals('视频'));
      });

      test('识别文档目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Documents/file.pdf',
        );
        expect(result, equals('文档'));
      });

      test('识别声音目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Sounds/audio.wav',
        );
        expect(result, equals('声音'));
      });
    });

    group('层级2 - 二级子目录映射（大小写不敏感）', () {
      test('识别微信子目录 - 标准大小写', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/WeiXin/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('识别微信子目录 - 全小写', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/weixin/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('识别微信子目录 - 全大写', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/WEIXIN/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('识别微信子目录 - WeChat变体', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Pictures/WeChat/photo.png',
        );
        expect(result, equals('微信'));
      });

      test('识别QQ子目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Pictures/QQ/photo.png',
        );
        expect(result, equals('QQ'));
      });

      test('识别截屏子目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Pictures/Screenshots/screen.png',
        );
        expect(result, equals('截屏'));
      });

      test('识别相机子目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/DCIM/Camera/IMG_001.jpg',
        );
        expect(result, equals('相机'));
      });

      test('识别钉钉子目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/DingTalk/file.pdf',
        );
        expect(result, equals('钉钉'));
      });

      test('识别百度网盘子目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/BaiduNetdisk/file.zip',
        );
        expect(result, equals('百度网盘'));
      });

      test('未映射的子目录保留原名', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/MyCustomFolder/file.txt',
        );
        expect(result, equals('MyCustomFolder'));
      });

      test('多层嵌套取二级目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/WeiXin/SubFolder/Deep/file.jpg',
        );
        expect(result, equals('微信'));
      });
    });

    group('层级3 - 扩展系统目录', () {
      test('识别闹钟目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Alarms/ring.mp3',
        );
        expect(result, equals('闹钟'));
      });

      test('识别通知目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Notifications/notify.mp3',
        );
        expect(result, equals('通知'));
      });

      test('识别铃声目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Ringtones/ring.mp3',
        );
        expect(result, equals('铃声'));
      });

      test('识别Android目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Android/data/com.test/file.txt',
        );
        expect(result, equals('Android'));
      });

      test('识别播客目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Podcasts/episode.mp3',
        );
        expect(result, equals('播客'));
      });

      test('识别备用下载目录', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Downloads/file.zip',
        );
        expect(result, equals('下载'));
      });
    });

    group('层级4 - 路径特征和文件名前缀匹配', () {
      test('通过路径识别微信（深层路径）', () {
        final result = FileSourceDetector.detectSource(
          '/data/data/com.tencent.mm/tencent/MicroMsg/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('通过文件名前缀识别微信 - wx_开头', () {
        final result = FileSourceDetector.detectSource(
          '/any/random/path/wx_camera_1767423401409.jpg',
        );
        expect(result, equals('微信'));
      });

      test('通过文件名前缀识别微信 - mmexport开头', () {
        final result = FileSourceDetector.detectSource(
          '/any/random/path/mmexport1234567890.jpg',
        );
        expect(result, equals('微信'));
      });

      test('通过文件名前缀识别QQ', () {
        final result = FileSourceDetector.detectSource(
          '/any/random/path/qq_file_123456.txt',
        );
        expect(result, equals('QQ'));
      });

      test('通过路径识别蓝牙', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/bluetooth/received/file.pdf',
        );
        expect(result, equals('蓝牙'));
      });

      test('通过路径识别百度网盘（深层）', () {
        final result = FileSourceDetector.detectSource(
          '/data/baidunetdisk/downloads/file.zip',
        );
        expect(result, equals('百度网盘'));
      });

      test('通过路径识别夸克', () {
        final result = FileSourceDetector.detectSource(
          '/data/quark/browser/download/file.apk',
        );
        expect(result, equals('夸克'));
      });

      test('通过路径识别钉钉（深层）', () {
        final result = FileSourceDetector.detectSource(
          '/data/dingtalk/files/document.pdf',
        );
        expect(result, equals('钉钉'));
      });

      test('通过路径识别企业微信', () {
        final result = FileSourceDetector.detectSource(
          '/data/wxwork/files/report.xlsx',
        );
        expect(result, equals('企业微信'));
      });
    });

    group('层级5 - 兜底逻辑', () {
      test('返回父目录名', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/CustomFolder/SubFolder/file.txt',
        );
        expect(result, equals('SubFolder'));
      });

      test('父目录名也尝试映射', () {
        final result = FileSourceDetector.detectSource(
          '/random/path/wechat/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('路径太短返回未知', () {
        final result = FileSourceDetector.detectSource('/file.txt');
        expect(result, equals('未知'));
      });

      test('空路径返回未知', () {
        final result = FileSourceDetector.detectSource('');
        expect(result, equals(SystemFoldersConfig.unknownSource));
      });
    });

    group('边界情况和特殊场景', () {
      test('路径末尾有斜杠', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/WeiXin/',
        );
        expect(result, equals('微信'));
      });

      test('路径末尾无斜杠（文件）', () {
        // 无斜杠结尾的路径被视为文件，在系统目录下直接文件返回系统目录名
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/file.txt',
        );
        expect(result, equals('下载'));
      });

      test('混合大小写的路径', () {
        final result = FileSourceDetector.detectSource(
          '/Storage/Emulated/0/Download/WeiXin/file.jpg',
        );
        expect(result, equals('微信'));
      });

      test('文件名包含路径分隔符的特殊情况', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/file.txt',
        );
        expect(result, equals('下载'));
      });

      test('优先级测试：系统目录 > 文件名前缀', () {
        // wx_camera开头的文件在下载目录中，应识别为"下载"而非"微信"
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/wx_camera_test.jpg',
        );
        expect(result, equals('下载'));
      });

      test('优先级测试：二级目录 > 文件名前缀', () {
        // wx_camera文件在QQ子目录中，应识别为"QQ"
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/QQ/wx_camera_test.jpg',
        );
        expect(result, equals('QQ'));
      });

      test('中文路径名称', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/我的文件夹/file.txt',
        );
        expect(result, equals('我的文件夹'));
      });

      test('包含特殊字符的目录名', () {
        final result = FileSourceDetector.detectSource(
          '/storage/emulated/0/Download/2024-01-01_backup/file.zip',
        );
        expect(result, equals('2024-01-01_backup'));
      });
    });

    group('性能测试（可选）', () {
      test('批量识别性能', () {
        final paths = [
          '/storage/emulated/0/Download/WeiXin/file1.jpg',
          '/storage/emulated/0/Pictures/Screenshots/screen.png',
          '/storage/emulated/0/DCIM/Camera/photo.jpg',
          '/any/path/wx_camera_123.jpg',
          '/storage/emulated/0/CustomFolder/file.txt',
        ];

        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          for (final path in paths) {
            FileSourceDetector.detectSource(path);
          }
        }
        stopwatch.stop();

        logger.i('识别5000次耗时: ${stopwatch.elapsedMilliseconds}ms');
        expect(stopwatch.elapsedMilliseconds, lessThan(500)); // 应该小于500ms
      });
    });
  });
}
