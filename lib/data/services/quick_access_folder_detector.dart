import 'dart:io';

import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 快速访问文件夹检测器配置
class QuickAccessDetectorConfig {
  static const int minFileCount = 5;
  static const double minFolderSizeMB = 5.0;
  static const int maxDaysForRecent = 60;
  static const int minFileTypesDiversity = 2;
  static const int maxDepthForAnalysis = 5;
  static const int maxFilesToAnalyze = 500;
  static const int maxFoldersToScan = 0;

  /// 文件夹名称黑名单（系统生成、缓存等）
  static const List<String> folderNameBlacklist = [
    // 系统/应用生成目录
    '.cache',
    'cache',
    'Cache',
    'CACHE',
    '.gradle',
    'node_modules',
    '__pycache__',
    '.git',
    '.svn',
    '.idea',
    'build',
    'dist',
    'out',
    'target',

    // 临时目录
    'temp',
    'tmp',
    'Temp',
    'Tmp',
    'TMP',

    // 日志目录
    'log',
    'logs',
    'Log',
    'Logs',

    // 特殊系统目录
    'Android',
    '.app',
    '.framework',
    'root',
    'system',

    // Android 系统生成
    '.Trash',
    '.Trash-1000',
    'lost+found',
  ];
}

/// 文件夹分析结果（内部使用）
class _FolderAnalysisResult {
  final String path;
  final int fileCount;
  final int folderSize;
  final DateTime? lastModified;
  final Set<String> fileExtensions;
  final Set<String> largeMediaFiles; // >1MB的图片/视频

  _FolderAnalysisResult({
    required this.path,
    required this.fileCount,
    required this.folderSize,
    required this.lastModified,
    required this.fileExtensions,
    this.largeMediaFiles = const {},
  });

  /// 检查是否包含重要文档（PDF/Office/大图片视频）
  bool get hasImportantDocuments {
    if (fileExtensions.contains('pdf')) return true;
    
    const officeExts = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp'};
    if (fileExtensions.any((ext) => officeExts.contains(ext))) return true;
    
    if (largeMediaFiles.isNotEmpty) return true;
    
    return false;
  }

  /// 判断是否满足任意一个过滤条件
  bool meetsAnyCondition({
    required int minFileCount,
    required double minFolderSizeMB,
    required int maxDaysForRecent,
    required int minFileTypesDiversity,
  }) {
    // 优先级1：重要文档（PDF/Office/大媒体文件）
    if (hasImportantDocuments) {
      logger.d('$path: has important documents');
      return true;
    }

    // 优先级2：文件数达标
    if (fileCount >= minFileCount) {
      logger.d('$path: fileCount $fileCount >= $minFileCount');
      return true;
    }

    // 优先级3：文件夹大小达标
    final sizeInMB = folderSize / 1024 / 1024;
    if (sizeInMB >= minFolderSizeMB) {
      logger.d('$path: size ${sizeInMB.toStringAsFixed(1)}MB >= $minFolderSizeMB');
      return true;
    }

    // 优先级4：最近修改
    if (lastModified != null) {
      final daysOld = DateTime.now().difference(lastModified!).inDays;
      if (daysOld <= maxDaysForRecent) {
        logger.d('$path: modified $daysOld days ago <= $maxDaysForRecent');
        return true;
      }
    }

    // 优先级5：文件类型多样性
    if (fileExtensions.length >= minFileTypesDiversity) {
      logger.d('$path: ${fileExtensions.length} file types >= $minFileTypesDiversity');
      return true;
    }

    return false;
  }

  @override
  String toString() {
    return '_FolderAnalysisResult('
        'path: $path, '
        'files: $fileCount, '
        'size: $folderSize bytes, '
        'types: ${fileExtensions.length}, '
        'largeMedia: ${largeMediaFiles.length}'
        ')';
  }
}

/// 快速访问文件夹检测器
/// 
/// 扫描并检测应该显示在"快速访问"中的文件夹：
/// 1. 系统常见目录（DCIM/Download等）及其直接子目录
/// 2. 根目录下满足条件的其他用户文件夹
class QuickAccessFolderDetector {
  QuickAccessFolderDetector();

  /// 检测所有快速访问文件夹
  /// 
  /// **注意**：执行 I/O 操作，应在后台线程运行
  Future<List<QuickAccessFolder>> detectQuickAccessFolders() async {
    logger.i('QuickAccessFolderDetector.detectQuickAccessFolders called');

    try {
      final commonFolders = await _scanCommonDirectories();
      logger.i('Found ${commonFolders.length} common folders');

      final otherFolders = await _scanOtherRootFolders();
      logger.i('Found ${otherFolders.length} other folders');

      final allFolders = [...commonFolders, ...otherFolders];
      logger.i('Total: ${allFolders.length} folders');

      return allFolders;
    } catch (e, stackTrace) {
      logger.e('Error detecting folders: $e\n$stackTrace');
      return [];
    }
  }

  /// 扫描系统常见目录及其一级子目录
  Future<List<QuickAccessFolder>> _scanCommonDirectories() async {
    logger.i('_scanCommonDirectories called');
    final commonDirs = <QuickAccessFolder>[];

    for (final systemPath in SystemFoldersConfig.systemPaths) {
      final dir = Directory(systemPath);

      if (!await dir.exists()) {
        logger.d('System directory not found: $systemPath');
        continue;
      }

      try {
        // 添加系统根目录
        String cleanPath = systemPath;
        if (cleanPath.endsWith(Platform.pathSeparator)) {
          cleanPath = cleanPath.substring(0, cleanPath.length - 1);
        }
        final name = cleanPath.split(Platform.pathSeparator).last;
        final rootFolder = QuickAccessFolder(
          id: '${DateTime.now().millisecondsSinceEpoch}_${name}_root',
          path: systemPath,
          originalName: name,
          type: QuickAccessFolderType.system,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
        );
        commonDirs.add(rootFolder);
        logger.d('Added system directory: $systemPath');

        // 扫描一级子目录
        await _scanCommonSubdirectories(systemPath, commonDirs);
      } catch (e) {
        logger.w('Error processing $systemPath: $e');
      }
    }

    logger.i('_scanCommonDirectories: ${commonDirs.length} folders');
    return commonDirs;
  }

  /// 扫描系统目录的直接子目录（过滤隐藏和空目录）
  Future<void> _scanCommonSubdirectories(
    String parentPath,
    List<QuickAccessFolder> allDirs,
  ) async {
    try {
      final parentDir = Directory(parentPath);
      if (!await parentDir.exists()) {
        return;
      }

      final entities = await parentDir.list(followLinks: false).toList();
      logger.d('Found ${entities.length} entities in $parentPath');

      int subdirCount = 0;
      for (final entity in entities) {
        if (entity is Directory) {
          // 去除路径尾部可能存在的分隔符，避免split后得到空字符串
          String entityPath = entity.path;
          if (entityPath.endsWith(Platform.pathSeparator)) {
            entityPath = entityPath.substring(0, entityPath.length - 1);
          }
          final entityName = entityPath.split(Platform.pathSeparator).last;

          // 过滤隐藏目录
          if (entityName.startsWith('.')) {
            logger.d('Skipping hidden directory: ${entity.path}');
            continue;
          }

          // 检查是否为空目录
          if (!await _hasFiles(entity.path)) {
            logger.d('Skipping empty directory: ${entity.path}');
            continue;
          }

          try {
            final subfolder = QuickAccessFolder(
              id: '${DateTime.now().millisecondsSinceEpoch}_${entityName}_$subdirCount',
              path: entity.path,
              originalName: entityName,
              type: QuickAccessFolderType.system,
              createdAt: DateTime.now(),
              isAddedToQuickAccess: false,
              isHidden: false,
              parentPath: parentPath, // 记录父目录关系
            );
            allDirs.add(subfolder);
            logger.d('Added system subdirectory: ${entity.path}');
            subdirCount++;
          } catch (e) {
            logger.w('Error processing subdirectory ${entity.path}: $e');
          }
        }
      }

      logger.d('_scanCommonSubdirectories: found $subdirCount subdirs in $parentPath');
    } catch (e) {
      logger.w('Error scanning subdirectories of $parentPath: $e');
    }
  }

  /// Part 2: 扫描其他文件夹
  /// 
  /// 扫描 /storage/emulated/0 根目录的一级目录，
  /// 对每个候选目录进行5级深度分析，
  /// 返回满足条件的文件夹
  /// 
  /// 排除：
  /// - 系统常见目录
  /// - 隐藏目录
  /// - EasyFile 自身
  /// - 黑名单中的目录
  Future<List<QuickAccessFolder>> _scanOtherRootFolders() async {
    logger.i('_scanOtherRootFolders called');
    final otherFolders = <QuickAccessFolder>[];

    // Android 内部存储根目录
    const String rootPath = '/storage/emulated/0';
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) {
      logger.w('Root directory does not exist: $rootPath');
      return otherFolders;
    }

    try {
      final entities = await rootDir.list(followLinks: false).toList();
      logger.d('Found ${entities.length} entities in root directory');

      int scannedCount = 0;
      int addedCount = 0;

      for (final entity in entities) {
        // 检查是否达到扫描限制（0 表社无限制）
        if (QuickAccessDetectorConfig.maxFoldersToScan > 0 &&
            scannedCount >= QuickAccessDetectorConfig.maxFoldersToScan) {
          logger.i('Reached max folders to scan limit: ${QuickAccessDetectorConfig.maxFoldersToScan}');
          break;
        }

        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;

          // 过滤1：隐藏目录
          if (_isHiddenFolder(folderName)) {
            logger.d('Skipping hidden folder: $folderName');
            continue;
          }

          // 过滤2：系统常见目录
          if (SystemFoldersConfig.isSystemFolder(entity.path)) {
            logger.d('Skipping system folder: $folderName');
            continue;
          }

          // 过滤3：EasyFile 自身
          if (_isEasyFileDir(folderName)) {
            logger.d('Skipping EasyFile directory: $folderName');
            continue;
          }

          // 过滤4：黑名单
          if (_isInBlacklist(folderName)) {
            logger.d('Skipping blacklisted folder: $folderName');
            continue;
          }

          scannedCount++;

          try {
            // 5级深度分析
            final analysis = await _analyzeFolder(
              entity.path,
              maxDepth: QuickAccessDetectorConfig.maxDepthForAnalysis,
            );

            logger.d('Analysis result: $analysis');

            // 检查是否满足条件
            if (analysis.meetsAnyCondition(
              minFileCount: QuickAccessDetectorConfig.minFileCount,
              minFolderSizeMB: QuickAccessDetectorConfig.minFolderSizeMB,
              maxDaysForRecent: QuickAccessDetectorConfig.maxDaysForRecent,
              minFileTypesDiversity:
                  QuickAccessDetectorConfig.minFileTypesDiversity,
            )) {
              // 创建 QuickAccessFolder
              final folder = QuickAccessFolder(
                id: '${DateTime.now().millisecondsSinceEpoch}_$folderName',
                path: entity.path,
                originalName: folderName,
                type: QuickAccessFolderType.other,
                createdAt: DateTime.now(),
                isAddedToQuickAccess: false,
                isHidden: false,
              );

              otherFolders.add(folder);
              addedCount++;
              logger.d('Added other folder: $folderName');
            } else {
              logger.d('Folder does not meet any condition: $folderName');
            }
          } catch (e) {
            logger.w('Error analyzing folder ${entity.path}: $e');
          }
        }
      }

      logger.i(
        '_scanOtherRootFolders: scanned $scannedCount folders, '
        'added $addedCount to results',
      );
    } catch (e) {
      logger.e('Error scanning other root folders: $e');
    }

    return otherFolders;
  }

  /// 递归分析文件夹（5级深度）
  /// 
  /// 累计统计：
  /// - 文件数量
  /// - 文件总大小
  /// - 最新修改时间
  /// - 不同的文件扩展名
  /// 
  /// **性能优化**：
  /// - 早停：满足任意条件立即返回
  /// - 深度限制：最多递归 maxDepth 层
  /// - 文件限制：最多扫描 maxFilesToAnalyze 个文件
  Future<_FolderAnalysisResult> _analyzeFolder(
    String folderPath, {
    int currentDepth = 0,
    int maxDepth = 5,
    int fileCountSoFar = 0,
    int folderSizeSoFar = 0,
    DateTime? lastModifiedSoFar,
    Set<String>? extensionsSoFar,
    Set<String>? largeMediaFilesSoFar,
  }) async {
    int fileCount = fileCountSoFar;
    int folderSize = folderSizeSoFar;
    DateTime? lastModified = lastModifiedSoFar;
    final extensions = extensionsSoFar ?? <String>{};
    final largeMediaFiles = largeMediaFilesSoFar ?? <String>{};

    // 深度限制
    if (currentDepth > maxDepth) {
      logger.d(
        '_analyzeFolder: reached max depth at $folderPath (depth=$currentDepth)',
      );
      return _FolderAnalysisResult(
        path: folderPath,
        fileCount: fileCount,
        folderSize: folderSize,
        lastModified: lastModified,
        fileExtensions: extensions,
      );
    }

    // 文件数限制
    if (fileCount >= QuickAccessDetectorConfig.maxFilesToAnalyze) {
      logger.d(
        '_analyzeFolder: reached max file count at $folderPath '
        '($fileCount files)',
      );
      return _FolderAnalysisResult(
        path: folderPath,
        fileCount: fileCount,
        folderSize: folderSize,
        lastModified: lastModified,
        fileExtensions: extensions,
        largeMediaFiles: largeMediaFiles,
      );
    }

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return _FolderAnalysisResult(
          path: folderPath,
          fileCount: fileCount,
          folderSize: folderSize,
          lastModified: lastModified,
          fileExtensions: extensions,
          largeMediaFiles: largeMediaFiles,
        );
      }

      final entities = await dir.list(followLinks: false).toList();

      // 顶层目录检查：如果顶层没有可见内容（只有隐藏文件/文件夹），视为空目录
      if (currentDepth == 0) {
        final hasVisibleContent = entities.any((entity) {
          final name = entity.path.split(Platform.pathSeparator).last;
          return !name.startsWith('.');
        });
        
        if (!hasVisibleContent) {
          logger.d('$folderPath is considered empty (only hidden content at top level)');
          return _FolderAnalysisResult(
            path: folderPath,
            fileCount: 0,
            folderSize: 0,
            lastModified: null,
            fileExtensions: {},
            largeMediaFiles: {},
          );
        }
      }

      for (final entity in entities) {
        // 文件数限制检查
        if (fileCount >= QuickAccessDetectorConfig.maxFilesToAnalyze) {
          break;
        }

        if (entity is File) {
          fileCount++;
          final fileSize = await entity.length();
          folderSize += fileSize;

          // 更新修改时间
          try {
            final stat = await entity.stat();
            if (lastModified == null ||
                stat.modified.isAfter(lastModified)) {
              lastModified = stat.modified;
            }
          } catch (e) {
            logger.d('Error getting file stat for ${entity.path}: $e');
          }

          // 提取文件扩展名
          final parts = entity.path.split('.');
          if (parts.length > 1) {
            final ext = parts.last.toLowerCase();
            extensions.add(ext);
            
            // 检测大于1MB的图片或视频
            if (fileSize > 1024 * 1024) { // 1MB
              const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};
              const videoExts = {'mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', '3gp'};
              if (imageExts.contains(ext) || videoExts.contains(ext)) {
                largeMediaFiles.add(parts.last);
              }
            }
          }
        } else if (entity is Directory) {
          // 过滤隐藏子目录
          final dirName = entity.path.split(Platform.pathSeparator).last;
          if (!dirName.startsWith('.')) {
            // 限制扫描前两级（currentDepth <= 1）
            if (currentDepth <= 1) {
              // 递归分析子目录
              final subAnalysis = await _analyzeFolder(
                entity.path,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                fileCountSoFar: fileCount,
                folderSizeSoFar: folderSize,
                lastModifiedSoFar: lastModified,
                extensionsSoFar: extensions,
                largeMediaFilesSoFar: largeMediaFiles,
              );

              fileCount = subAnalysis.fileCount;
              folderSize = subAnalysis.folderSize;
              lastModified = subAnalysis.lastModified;
              extensions.addAll(subAnalysis.fileExtensions);
              largeMediaFiles.addAll(subAnalysis.largeMediaFiles);
            }
          }
        }
      }
    } catch (e) {
      logger.w('Error analyzing folder $folderPath: $e');
    }

    return _FolderAnalysisResult(
      path: folderPath,
      fileCount: fileCount,
      folderSize: folderSize,
      lastModified: lastModified,
      fileExtensions: extensions,
      largeMediaFiles: largeMediaFiles,
    );
  }

  /// 检查文件夹是否为隐藏（以 . 开头）
  bool _isHiddenFolder(String folderName) {
    return folderName.startsWith('.');
  }

  /// 检查文件夹是否为 EasyFile 自身
  bool _isEasyFileDir(String folderName) {
    final lowerName = folderName.toLowerCase();
    return lowerName == 'easyfile' ||
        lowerName == '.easyfile' ||
        lowerName == 'easy_file';
  }

  /// 检查文件夹名称是否在黑名单中
  bool _isInBlacklist(String folderName) {
    return QuickAccessDetectorConfig.folderNameBlacklist.contains(folderName);
  }

  /// 检查目录是否包含任何文件（不检查子目录）
  /// 
  /// 用于过滤完全空的一级子目录
  Future<bool> _hasFiles(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return false;
      }

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          return true;
        }
      }
      return false;
    } catch (e) {
      logger.d('Error checking if directory has files: $e');
      return false;
    }
  }
}
