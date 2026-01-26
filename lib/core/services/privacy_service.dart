import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_session_manager.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:flutter/material.dart';
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

      final targetFile = File(targetPath);

      // 5. 跨设备移动：复制 + 删除
      logger.d('开始复制文件: ${file.path} -> $targetPath');
      await sourceFile.copy(targetPath);

      // 6. 验证复制成功
      if (!targetFile.existsSync()) {
        logger.e('文件复制失败: $targetPath');
        return false;
      }

      // 7. 删除源文件
      logger.d('删除源文件: ${file.path}');
      await sourceFile.delete();

      logger.i('📥 文件已移入隐私空间: ${targetFile.path}');
      return true;
    } catch (e) {
      logger.e('移入隐私空间失败: $e');
      return false;
    }
  }

  /// 移出隐私空间
  Future<bool> moveFromPrivate(FileItem file, String targetPath) async {
    try {
      final sourceFile = File(file.path);
      String finalTargetPath = targetPath;

      // 检查目标目录是否存在
      final targetFile = File(targetPath);
      final targetDir = Directory(targetFile.parent.path);
      if (!targetDir.existsSync()) {
        logger.w('目标目录不存在: ${targetDir.path}');
        return false;
      }

      // 检查目标文件是否已存在
      if (targetFile.existsSync()) {
        // 添加编号避免冲突
        final fileName = file.name;
        final nameParts = fileName.split('.');
        int counter = 1;

        do {
          final newName = nameParts.length > 1
              ? '${nameParts.sublist(0, nameParts.length - 1).join('.')}($counter).${nameParts.last}'
              : '$fileName($counter)';
          finalTargetPath = '${targetDir.path}/$newName';
          counter++;
        } while (File(finalTargetPath).existsSync());
      }

      // 跨设备移动：复制 + 删除
      // 不能使用 rename()，因为源文件和目标文件可能在不同的文件系统上
      await sourceFile.copy(finalTargetPath);

      // 验证复制成功
      final newTargetFile = File(finalTargetPath);
      if (!newTargetFile.existsSync()) {
        logger.e('文件复制失败: $finalTargetPath');
        return false;
      }

      // 删除源文件
      await sourceFile.delete();

      logger.i('📤 文件已移出隐私空间: ${newTargetFile.uri.pathSegments.last}');
      return true;
    } catch (e) {
      logger.e('移出隐私空间失败: $e');
      return false;
    }
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
      // 1. 删除所有隐私文件
      final privateDir = await getPrivateDirectory();
      final dir = Directory(privateDir);

      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        logger.i('🗑️ 隐私文件已删除');
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
}
