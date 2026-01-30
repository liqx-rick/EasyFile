import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_session_manager.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐私空间核心服务
///
/// 提供隐私文件管理、PIN校验、生物识别等功能
class PrivacyService {
  static const String _keyInitialized = 'privacy_initialized';
  static const String _keyPinHash = 'privacy_pin_hash';
  static const String _keyBiometricEnabled = 'privacy_biometric_enabled';
  static const String _keyLastAccess = 'privacy_last_access';

  static const MethodChannel _platformChannel = MethodChannel('easyfile/privacy_file');

  final LocalAuthentication _localAuth = LocalAuthentication();

  // 缓存私有目录路径，避免重复I/O
  String? _privateDirectoryPath;

  /// 获取私有目录路径（自动创建）
  Future<String> getPrivateDirectory() async {
    if (_privateDirectoryPath != null) {
      return _privateDirectoryPath!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final privateDir = Directory('${appDir.path}/private_files');

    if (!privateDir.existsSync()) {
      await privateDir.create(recursive: true);
      logger.i('🔒 创建隐私目录: ${privateDir.path}');
    }

    _privateDirectoryPath = privateDir.path;
    return _privateDirectoryPath!;
  }

  /// 检查是否已初始化隐私空间
  Future<bool> isInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyInitialized) ?? false;
  }

  /// 初始化隐私空间（首次设置PIN）
  Future<bool> initialize(String pin, {bool enableBiometric = false}) async {
    if (pin.length < 4 || pin.length > 6) {
      logger.w('PIN长度不符合要求: ${pin.length}');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = _hashPin(pin);

      await prefs.setBool(_keyInitialized, true);
      await prefs.setString(_keyPinHash, hash);
      await prefs.setBool(_keyBiometricEnabled, enableBiometric);
      await prefs.setString(_keyLastAccess, DateTime.now().toIso8601String());

      // 创建私有目录
      await getPrivateDirectory();

      logger.i('✅ 隐私空间初始化成功');
      return true;
    } catch (e) {
      logger.e('初始化隐私空间失败: $e');
      return false;
    }
  }

  /// 校验PIN
  Future<bool> verifyPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_keyPinHash);

      if (storedHash == null) {
        logger.w('未找到存储的PIN hash');
        return false;
      }

      final inputHash = _hashPin(pin);
      final isValid = inputHash == storedHash;

      if (isValid) {
        // 更新最后访问时间
        await prefs.setString(_keyLastAccess, DateTime.now().toIso8601String());
        logger.i('✅ PIN验证成功');
      } else {
        logger.w('❌ PIN验证失败');
      }

      return isValid;
    } catch (e) {
      logger.e('PIN验证异常: $e');
      return false;
    }
  }

  /// 计算PIN的SHA-256哈希
  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 检查设备是否支持生物识别（仅支持高安全级别）
  Future<bool> canUseBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      logger.i('生物识别检查: canCheckBiometrics=$canCheck, isDeviceSupported=$isDeviceSupported');

      if (!canCheck && !isDeviceSupported) return false;

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      logger.i('可用的生物识别类型: $availableBiometrics');

      // 仅支持高安全级别的生物识别：指纹、人脸、虹膜、强生物识别
      // 排除weak类型（图案、PIN等低安全性方式）
      final hasSecureBiometric = availableBiometrics.contains(BiometricType.fingerprint) ||
          availableBiometrics.contains(BiometricType.face) ||
          availableBiometrics.contains(BiometricType.iris) ||
          availableBiometrics.contains(BiometricType.strong);

      logger.i('是否支持高安全级别生物识别: $hasSecureBiometric');
      return hasSecureBiometric;
    } catch (e) {
      logger.e('检查生物识别失败: $e');
      return false;
    }
  }

  /// 检查是否启用生物识别
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  /// 设置生物识别开关
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
    logger.i('生物识别${enabled ? "已启用" : "已禁用"}');
  }

  /// 执行生物识别验证
  Future<bool> authenticateWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: '验证身份以访问隐私空间',
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: '生物识别验证',
            cancelButton: '取消',
            biometricHint: '请验证指纹',
          ),
          IOSAuthMessages(
            cancelButton: '取消',
            goToSettingsButton: '去设置',
            goToSettingsDescription: '请在设置中启用生物识别',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        // 更新最后访问时间
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastAccess, DateTime.now().toIso8601String());
        logger.i('✅ 生物识别验证成功');
      } else {
        logger.w('❌ 生物识别验证失败');
      }

      return authenticated;
    } catch (e) {
      logger.e('生物识别验证异常: $e');
      return false;
    }
  }

  /// 智能验证：优先使用会话，会话无效时弹出PIN验证
  ///
  /// [context] 用于显示验证对话框
  /// [forceVerify] 是否强制验证（忽略会话）
  /// [showQuickTip] 会话有效时是否显示快速提示
  ///
  /// 返回 true 表示验证成功（通过会话或PIN）
  Future<bool> verifyWithSession(
    BuildContext context, {
    bool forceVerify = false,
    bool showQuickTip = true,
  }) async {
    final sessionManager = PrivacySessionManager();

    // 如果不强制验证且会话有效，直接返回成功
    if (!forceVerify && sessionManager.isSessionValid()) {
      logger.i('✅ 会话有效，跳过PIN验证');

      if (showQuickTip && context.mounted) {
        // 显示快速提示（500ms自动消失）
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green[300]),
                const SizedBox(width: 8),
                const Text('会话有效 · 无需验证'),
              ],
            ),
            duration: const Duration(milliseconds: 500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return true;
    }

    // 需要验证PIN
    if (!context.mounted) return false;

    // 导入 PrivacyQuickAuthDialog
    final pinVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // 动态导入以避免循环依赖
        return FutureBuilder(
          future: _loadQuickAuthDialog(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return snapshot.data!;
            }
            return const Center(child: CircularProgressIndicator());
          },
        );
      },
    );

    if (pinVerified == true) {
      // 验证成功，激活会话
      sessionManager.markVerified();
      return true;
    }

    return false;
  }

  /// 动态加载 PrivacyQuickAuthDialog（避免循环依赖）
  Future<Widget> _loadQuickAuthDialog() async {
    // 这里使用延迟导入，实际实现中直接返回对话框
    // 由于已经有 PrivacyQuickAuthDialog，直接使用
    return FutureBuilder(
      future: Future.value(true),
      builder: (context, snapshot) {
        // 这里需要动态导入，暂时返回占位
        return AlertDialog(
          title: const Text('验证身份'),
          content: const Text('请输入PIN码'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  /// 标记会话激活（进入隐私空间成功后调用）
  void markSessionActive() {
    final sessionManager = PrivacySessionManager();
    sessionManager.markVerified();
  }

  /// 清除会话（退出隐私空间、修改PIN等场景）
  void clearSession() {
    final sessionManager = PrivacySessionManager();
    sessionManager.invalidate();
  }

  /// 获取生物识别类型描述
  Future<String> getBiometricTypeString() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();

      // 优先显示最具体的类型
      if (biometrics.contains(BiometricType.face)) {
        return '面部识别';
      } else if (biometrics.contains(BiometricType.fingerprint)) {
        return '指纹';
      } else if (biometrics.contains(BiometricType.iris)) {
        return '虹膜';
      } else if (biometrics.contains(BiometricType.strong)) {
        return '生物识别';
      }
    } catch (e) {
      logger.e('获取生物识别类型失败: $e');
    }

    return '生物识别';
  }

  /// 移入隐私空间
  Future<bool> moveToPrivate(FileItem file) async {
    try {
      // 1. 检查源文件是否存在
      final sourceFile = File(file.path);
      if (!sourceFile.existsSync()) {
        logger.e('源文件不存在: ${file.path}');
        return false;
      }

      // 2. 获取私有目录并确保存在
      final privateDir = await getPrivateDirectory();
      final privateDirObj = Directory(privateDir);
      if (!privateDirObj.existsSync()) {
        logger.w('私有目录不存在，正在创建: $privateDir');
        await privateDirObj.create(recursive: true);
      }

      // 3. 构建目标路径
      final fileName = file.name;
      String targetPath = '$privateDir/$fileName';

      // 4. 检查目标文件是否已存在
      if (File(targetPath).existsSync()) {
        // 添加时间戳避免冲突
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final nameParts = fileName.split('.');
        final newName = nameParts.length > 1
            ? '${nameParts.sublist(0, nameParts.length - 1).join('.')}_$timestamp.${nameParts.last}'
            : '${fileName}_$timestamp';
        targetPath = '$privateDir/$newName';
        logger.i('目标文件已存在，使用新名称: $newName');
      }

      // 5. 保存原始路径到元数据
      await _saveOriginalPath(fileName, file.path);

      // 6. 移动文件（优先使用rename，跨设备时降级到复制+删除）
      logger.d('移动文件到隐私空间: ${file.path} -> $targetPath');

      try {
        // 尝试快速rename（同分区时非常快）
        await sourceFile.rename(targetPath);
        logger.d('✅ 文件移动成功（使用原子操作）');
      } on FileSystemException catch (e) {
        // 跨分区错误，降级到复制+删除
        if (e.message.contains('Cross-device') || e.osError?.errorCode == 18) {
          logger.d('⚠️ 检测到跨分区，使用复制+删除');

          // 复制文件到隐私空间
          await sourceFile.copy(targetPath);

          // 验证复制成功
          final targetFile = File(targetPath);
          if (!targetFile.existsSync()) {
            throw Exception('文件复制失败');
          }

          // 删除源文件（优先使用原生方法，避免触发第三方回收站）
          final deleted = await _deleteFileCompletely(file.path);
          if (!deleted) {
            logger.w('原生删除失败，降级到File.delete()');
            await sourceFile.delete();
          }
          logger.d('✅ 复制+删除完成');
        } else {
          // 其他错误，抛出
          rethrow;
        }
      }

      logger.i('📥 文件已移入隐私空间: $targetPath');
      return true;
    } catch (e) {
      logger.e('移入隐私空间失败: $e');
      return false;
    }
  }

  /// 移出隐私空间
  ///
  /// [file] 要移出的文件
  /// [userSelectedPath] 用户选择的目标路径（可选）
  ///
  /// 返回值：
  /// - true: 成功移出
  /// - false: 失败或需要用户选择路径
  ///
  /// 逻辑：
  /// 1. 优先尝试恢复到原始位置
  /// 2. 原位置不可用时，使用用户选择的路径
  /// 3. 如果都没有，返回false要求用户选择
  Future<bool> moveFromPrivate(FileItem file, {String? userSelectedPath}) async {
    try {
      final sourceFile = File(file.path);

      // 1. 尝试获取并恢复到原始路径
      final originalPath = await _getOriginalPath(file.name);
      if (originalPath != null) {
        logger.d('找到原始路径: $originalPath');

        // 检查原始目录是否存在
        final originalFile = File(originalPath);
        final originalDir = Directory(originalFile.parent.path);

        if (originalDir.existsSync()) {
          try {
            String finalPath = originalPath;

            // 检查原位置是否已有同名文件
            if (originalFile.existsSync()) {
              logger.w('原位置已有同名文件，添加编号');
              finalPath = await _getUniqueFilePath(originalPath);
            }

            // 移动到原位置
            logger.d('恢复到原位置: ${file.path} -> $finalPath');

            try {
              // 尝试快速rename
              await sourceFile.rename(finalPath);
              logger.d('✅ 恢复成功（使用原子操作）');
            } on FileSystemException catch (e) {
              // 跨分区错误，降级到复制+删除
              if (e.message.contains('Cross-device') || e.osError?.errorCode == 18) {
                logger.d('⚠️ 检测到跨分区，使用复制+删除');
                await sourceFile.copy(finalPath);
                if (!File(finalPath).existsSync()) {
                  throw Exception('文件复制失败');
                }
                await sourceFile.delete();
                logger.d('✅ 复制+删除完成');
              } else {
                rethrow;
              }
            }

            // 清除元数据记录
            await _removeOriginalPathRecord(file.name);

            // 通知 MediaStore 扫描文件，让相册能看到
            await _scanFile(finalPath);

            logger.i('📤 文件已恢复到原位置: $finalPath');
            return true;
          } catch (e) {
            logger.w('恢复到原位置失败: $e，将使用用户选择的路径');
            // 继续执行下面的逻辑
          }
        } else {
          logger.w('原始目录不存在: ${originalDir.path}');
        }
      }

      // 2. 原位置不可用，检查是否有用户选择的路径
      if (userSelectedPath == null) {
        logger.i('需要用户选择目标路径');
        return false;
      }

      // 3. 使用用户选择的路径
      String finalTargetPath = userSelectedPath;

      // 检查目标目录是否存在
      final targetFile = File(userSelectedPath);
      final targetDir = Directory(targetFile.parent.path);
      if (!targetDir.existsSync()) {
        logger.w('目标目录不存在: ${targetDir.path}');
        return false;
      }

      // 检查目标文件是否已存在
      if (targetFile.existsSync()) {
        logger.w('目标位置已有同名文件，添加编号');
        finalTargetPath = await _getUniqueFilePath(userSelectedPath);
      }

// 直接移动文件（优先使用rename，跨设备时降级到复制+删除）
      logger.d('移出隐私空间: ${file.path} -> $finalTargetPath');

      try {
        // 尝试快速rename
        await sourceFile.rename(finalTargetPath);
        logger.d('✅ 文件移动成功（使用原子操作）');
      } on FileSystemException catch (e) {
        // 跨分区错误，降级到复制+删除
        if (e.message.contains('Cross-device') || e.osError?.errorCode == 18) {
          logger.d('⚠️ 检测到跨分区，使用复制+删除');
          await sourceFile.copy(finalTargetPath);
          if (!File(finalTargetPath).existsSync()) {
            throw Exception('文件复制失败');
          }
          await sourceFile.delete();
          logger.d('✅ 复制+删除完成');
        } else {
          rethrow;
        }
      }

      // 清除元数据记录
      await _removeOriginalPathRecord(file.name);

      // 通知 MediaStore 扫描文件，让相册能看到
      await _scanFile(finalTargetPath);

      logger.i('📤 文件已移出隐私空间: $finalTargetPath');
      return true;
    } catch (e) {
      logger.e('移出隐私空间失败: $e');
      return false;
    }
  }

  /// 生成唯一文件路径（处理同名冲突）
  Future<String> _getUniqueFilePath(String originalPath) async {
    final file = File(originalPath);
    final dir = file.parent.path;
    final fileName = file.uri.pathSegments.last;
    final nameParts = fileName.split('.');

    int counter = 1;
    String newPath;

    do {
      final newName = nameParts.length > 1
          ? '${nameParts.sublist(0, nameParts.length - 1).join('.')}($counter).${nameParts.last}'
          : '$fileName($counter)';
      newPath = '$dir/$newName';
      counter++;
    } while (File(newPath).existsSync());

    return newPath;
  }

  /// 获取隐私文件列表
  Future<List<FileItem>> getPrivateFiles() async {
    try {
      final privateDir = await getPrivateDirectory();
      final dir = Directory(privateDir);

      if (!dir.existsSync()) {
        return [];
      }

      final entities = dir.listSync().whereType<File>().toList();

      final files = entities.map((e) => FileItem.fromEntity(e)).toList();

      // 按修改时间降序排序
      files.sort((a, b) => b.modified.compareTo(a.modified));

      logger.d('获取到 ${files.length} 个隐私文件');
      return files;
    } catch (e) {
      logger.e('获取隐私文件列表失败: $e');
      return [];
    }
  }

  /// 删除隐私文件
  Future<bool> deletePrivateFile(FileItem file) async {
    try {
      await File(file.path).delete();
      logger.i('🗑️ 隐私文件已删除: ${file.name}');
      return true;
    } catch (e) {
      logger.e('删除隐私文件失败: $e');
      return false;
    }
  }

  /// 检查文件是否在隐私目录
  Future<bool> isPrivateFile(String path) async {
    final privateDir = await getPrivateDirectory();
    return path.startsWith(privateDir);
  }

  /// 重置PIN（需要先验证身份）
  Future<bool> resetPin(String newPin) async {
    if (newPin.length < 4 || newPin.length > 6) {
      logger.w('新PIN长度不符合要求: ${newPin.length}');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = _hashPin(newPin);
      await prefs.setString(_keyPinHash, hash);

      logger.i('🔄 PIN已重置');
      return true;
    } catch (e) {
      logger.e('重置PIN失败: $e');
      return false;
    }
  }

  /// 清空隐私空间（删除所有文件+配置）
  Future<void> resetPrivacySpace() async {
    try {
      // 1. 删除所有隐私文件和元数据
      final privateDir = await getPrivateDirectory();
      final dir = Directory(privateDir);

      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        logger.i('🗑️ 隐私文件和元数据已删除');
      }

      // 2. 清除配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyInitialized);
      await prefs.remove(_keyPinHash);
      await prefs.remove(_keyBiometricEnabled);
      await prefs.remove(_keyLastAccess);

      // 3. 清除路径缓存
      _privateDirectoryPath = null;

      logger.i('🔓 隐私空间配置已清除');
    } catch (e) {
      logger.e('重置隐私空间失败: $e');
      rethrow;
    }
  }

  // ==================== 元数据管理（原始路径记录） ====================

  /// 获取元数据文件路径
  Future<String> _getMetadataFilePath() async {
    final privateDir = await getPrivateDirectory();
    return '$privateDir/.metadata.json';
  }

  /// 加载元数据（文件名 -> 原始路径映射）
  Future<Map<String, String>> _loadMetadata() async {
    try {
      final metadataPath = await _getMetadataFilePath();
      final metadataFile = File(metadataPath);

      if (!metadataFile.existsSync()) {
        return {};
      }

      final content = await metadataFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Map<String, String>.from(json);
    } catch (e) {
      logger.w('加载元数据失败: $e');
      return {};
    }
  }

  /// 保存元数据
  Future<void> _saveMetadata(Map<String, String> metadata) async {
    try {
      final metadataPath = await _getMetadataFilePath();
      final metadataFile = File(metadataPath);

      final content = jsonEncode(metadata);
      await metadataFile.writeAsString(content);

      logger.d('元数据已保存: ${metadata.length} 条记录');
    } catch (e) {
      logger.e('保存元数据失败: $e');
    }
  }

  /// 保存文件的原始路径
  Future<void> _saveOriginalPath(String fileName, String originalPath) async {
    final metadata = await _loadMetadata();
    metadata[fileName] = originalPath;
    await _saveMetadata(metadata);
    logger.d('已记录原始路径: $fileName -> $originalPath');
  }

  /// 获取文件的原始路径
  Future<String?> _getOriginalPath(String fileName) async {
    final metadata = await _loadMetadata();
    return metadata[fileName];
  }

  /// 移除文件的原始路径记录
  Future<void> _removeOriginalPathRecord(String fileName) async {
    final metadata = await _loadMetadata();
    if (metadata.remove(fileName) != null) {
      await _saveMetadata(metadata);
      logger.d('已移除原始路径记录: $fileName');
    }
  }

  /// 使用原生方法彻底删除文件（避免触发第三方回收站）
  ///
  /// 在 Android 10+ 上，使用 MediaStore API 直接删除，不会触发系统相册的"最近删除"
  /// 降级到 File.delete() 如果原生方法失败
  Future<bool> _deleteFileCompletely(String filePath) async {
    try {
      final result = await _platformChannel.invokeMethod<bool>(
        'deleteFileCompletely',
        {'filePath': filePath},
      );
      return result ?? false;
    } catch (e) {
      logger.w('原生删除方法调用失败: $e');
      return false;
    }
  }

  /// 通知 MediaStore 扫描文件
  ///
  /// 当文件从隐私空间恢复到公共存储后，需要通知系统相册/媒体库重新扫描
  /// 这样文件才会显示在相册中
  Future<void> _scanFile(String filePath) async {
    try {
      logger.d('通知 MediaStore 扫描文件: $filePath');
      final result = await _platformChannel.invokeMethod<bool>(
        'scanFile',
        {'filePath': filePath},
      );
      if (result == true) {
        logger.i('✅ 文件已添加到媒体库: $filePath');
      } else {
        logger.w('⚠️ 文件扫描失败: $filePath');
      }
    } catch (e) {
      logger.w('扫描文件异常: $e');
    }
  }
}
