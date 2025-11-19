import 'dart:io';
import 'dart:math';

/// 创建测试文件和文件夹结构
/// 用于测试分类页面的扫描功能
void main() async {
  print('🚀 开始创建测试文件结构...\n');

  final platform = Platform.isAndroid
      ? 'Android'
      : Platform.isWindows
          ? 'Windows'
          : 'Other';
  print('📱 检测到平台: $platform\n');

  // 确定根目录
  String rootPath;
  if (Platform.isAndroid) {
    rootPath = '/storage/emulated/0';
  } else if (Platform.isWindows) {
    rootPath = Platform.environment['USERPROFILE'] ?? 'C:\\';
  } else {
    rootPath = Platform.environment['HOME'] ?? '/tmp';
  }

  print('📂 根目录: $rootPath\n');

  // 创建用户自定义文件夹（根目录第一层）
  final userFolders = [
    'MyPhotos',
    'WorkFiles',
    'FamilyVideos',
    'PersonalMusic',
    'ProjectDocuments',
  ];

  for (final folderName in userFolders) {
    await createUserFolder(rootPath, folderName);
  }

  print('\n✅ 测试文件结构创建完成！');
  print('📊 统计信息：');
  print('   - 用户文件夹: ${userFolders.length} 个');
  print('   - 测试文件: 约 ${userFolders.length * 15} 个');
  print('\n💡 现在可以在应用中打开分类页面测试扫描功能了！');
}

/// 创建用户文件夹及其子文件
Future<void> createUserFolder(String rootPath, String folderName) async {
  try {
    final folderPath = '$rootPath${Platform.pathSeparator}$folderName';
    final folder = Directory(folderPath);

    print('📁 创建文件夹: $folderName');

    // 创建主文件夹
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    // 根据文件夹名称决定创建什么类型的文件
    if (folderName.contains('Photo') || folderName.contains('图片')) {
      await createImageFiles(folderPath);
    } else if (folderName.contains('Video') || folderName.contains('视频')) {
      await createVideoFiles(folderPath);
    } else if (folderName.contains('Music') || folderName.contains('音乐')) {
      await createMusicFiles(folderPath);
    } else if (folderName.contains('Document') || folderName.contains('文档')) {
      await createDocumentFiles(folderPath);
    } else {
      // 混合类型
      await createMixedFiles(folderPath);
    }

    print('   ✓ $folderName 创建完成\n');
  } catch (e) {
    print('   ✗ 创建 $folderName 失败: $e\n');
  }
}

/// 创建图片文件（带深层目录结构）
Future<void> createImageFiles(String basePath) async {
  final years = ['2023', '2024', '2025'];
  final extensions = ['jpg', 'png', 'gif', 'webp'];

  for (final year in years) {
    final yearPath = '$basePath${Platform.pathSeparator}$year';
    Directory(yearPath).createSync(recursive: true);

    for (var month = 1; month <= 3; month++) {
      final monthPath =
          '$yearPath${Platform.pathSeparator}${month.toString().padLeft(2, '0')}';
      Directory(monthPath).createSync(recursive: true);

      // 创建3-5张图片
      for (var i = 1; i <= Random().nextInt(3) + 3; i++) {
        final ext = extensions[Random().nextInt(extensions.length)];
        final filePath = '$monthPath${Platform.pathSeparator}photo_$i.$ext';
        await createDummyFile(filePath, 'Fake image file');
      }
    }
  }
  print('   → 创建了约 ${years.length * 3 * 4} 张图片（深度3层）');
}

/// 创建视频文件
Future<void> createVideoFiles(String basePath) async {
  final categories = ['Vacation', 'Family', 'Work'];
  final extensions = ['mp4', 'avi', 'mkv', 'mov'];

  for (final category in categories) {
    final categoryPath = '$basePath${Platform.pathSeparator}$category';
    Directory(categoryPath).createSync(recursive: true);

    for (final subFolder in ['2024', '2025']) {
      final subPath = '$categoryPath${Platform.pathSeparator}$subFolder';
      Directory(subPath).createSync(recursive: true);

      for (var i = 1; i <= 2; i++) {
        final ext = extensions[Random().nextInt(extensions.length)];
        final filePath = '$subPath${Platform.pathSeparator}video_$i.$ext';
        await createDummyFile(filePath, 'Fake video file');
      }
    }
  }
  print('   → 创建了约 ${categories.length * 2 * 2} 个视频（深度2层）');
}

/// 创建音乐文件
Future<void> createMusicFiles(String basePath) async {
  final artists = ['Artist_A', 'Artist_B', 'Artist_C'];
  final extensions = ['mp3', 'flac', 'wav', 'm4a'];

  for (final artist in artists) {
    final artistPath = '$basePath${Platform.pathSeparator}$artist';
    Directory(artistPath).createSync(recursive: true);

    for (final album in ['Album_1', 'Album_2']) {
      final albumPath = '$artistPath${Platform.pathSeparator}$album';
      Directory(albumPath).createSync(recursive: true);

      for (var i = 1; i <= 3; i++) {
        final ext = extensions[Random().nextInt(extensions.length)];
        final filePath = '$albumPath${Platform.pathSeparator}track_$i.$ext';
        await createDummyFile(filePath, 'Fake music file');
      }
    }
  }
  print('   → 创建了约 ${artists.length * 2 * 3} 首音乐（深度2层）');
}

/// 创建文档文件
Future<void> createDocumentFiles(String basePath) async {
  final categories = ['Reports', 'Presentations', 'Spreadsheets'];
  final extensions = {
    'Reports': ['pdf', 'doc', 'docx', 'txt'],
    'Presentations': ['ppt', 'pptx'],
    'Spreadsheets': ['xls', 'xlsx', 'csv'],
  };

  for (final category in categories) {
    final categoryPath = '$basePath${Platform.pathSeparator}$category';
    Directory(categoryPath).createSync(recursive: true);

    final exts = extensions[category]!;
    for (var i = 1; i <= 4; i++) {
      final ext = exts[Random().nextInt(exts.length)];
      final filePath = '$categoryPath${Platform.pathSeparator}document_$i.$ext';
      await createDummyFile(filePath, 'Fake document file');
    }
  }
  print('   → 创建了约 ${categories.length * 4} 个文档（深度1层）');
}

/// 创建混合类型文件（深度5层测试）
Future<void> createMixedFiles(String basePath) async {
  final structure = {
    'Level1': {
      'Level2': {
        'Level3': {
          'Level4': {
            'Level5': ['deep_image.jpg', 'deep_video.mp4', 'deep_doc.pdf']
          }
        }
      }
    },
    'Photos': ['image1.jpg', 'image2.png'],
    'Videos': ['video1.mp4'],
    'Docs': ['document.pdf', 'spreadsheet.xlsx'],
  };

  await createNestedStructure(basePath, structure);
  print('   → 创建了混合文件（最深5层）');
}

/// 递归创建嵌套结构
Future<void> createNestedStructure(String basePath, Map structure) async {
  for (final entry in structure.entries) {
    if (entry.value is Map) {
      final subPath = '$basePath${Platform.pathSeparator}${entry.key}';
      Directory(subPath).createSync(recursive: true);
      await createNestedStructure(subPath, entry.value);
    } else if (entry.value is List) {
      final folderPath = '$basePath${Platform.pathSeparator}${entry.key}';
      Directory(folderPath).createSync(recursive: true);
      for (final filename in entry.value) {
        final filePath = '$folderPath${Platform.pathSeparator}$filename';
        await createDummyFile(filePath, 'Test file');
      }
    }
  }
}

/// 创建虚拟文件
Future<void> createDummyFile(String filePath, String content) async {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      await file.writeAsString(content);
    }
  } catch (e) {
    // 忽略单个文件创建失败
  }
}
