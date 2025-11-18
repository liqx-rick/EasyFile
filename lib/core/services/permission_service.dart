import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../logger.dart';

/// 权限状态枚举
enum PermissionState {
  unknown, // 未知状态
  granted, // 已授权
  denied, // 已拒绝
  permanentlyDenied, // 永久拒绝（需要去设置页面）
}

/// 权限状态扩展方法
extension PermissionStateExtension on PermissionState {
  bool get isGranted => this == PermissionState.granted;
  bool get isDenied => this == PermissionState.denied;
  bool get isPermanentlyDenied => this == PermissionState.permanentlyDenied;
  bool get isUnknown => this == PermissionState.unknown;
  bool get needsRequest => this == PermissionState.denied || isUnknown;
  bool get needsSettings => this == PermissionState.permanentlyDenied;
}

/// 权限管理服务
/// 负责检查和管理应用的存储权限状态
class PermissionService extends ChangeNotifier {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 权限状态
  PermissionState _state = PermissionState.unknown;
  PermissionState get state => _state;

  /// 是否已检查过权限
  bool _hasChecked = false;
  bool get hasChecked => _hasChecked;

  /// 检查当前权限状态
  Future<PermissionState> checkPermission() async {
    try {
      logger.d('PermissionService: Checking permission status...');

      // 首先检查 MANAGE_EXTERNAL_STORAGE (All files access)
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      
      // 检查存储权限
      final storageStatus = await Permission.storage.status;

      // Android 13+ 需要额外检查媒体权限
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;

      logger.d('Permission status - manage: $manageStorageStatus, storage: $storageStatus, photos: $photosStatus, videos: $videosStatus');

      // 判断整体权限状态
      // 优先使用 MANAGE_EXTERNAL_STORAGE（最高权限）
      if (manageStorageStatus.isGranted) {
        _setState(PermissionState.granted);
      } else if (storageStatus.isGranted ||
          (photosStatus.isGranted && videosStatus.isGranted)) {
        _setState(PermissionState.granted);
      } else if (storageStatus.isPermanentlyDenied ||
          photosStatus.isPermanentlyDenied ||
          videosStatus.isPermanentlyDenied) {
        _setState(PermissionState.permanentlyDenied);
      } else if (storageStatus.isDenied ||
          photosStatus.isDenied ||
          videosStatus.isDenied) {
        _setState(PermissionState.denied);
      } else {
        _setState(PermissionState.unknown);
      }

      _hasChecked = true;
      logger.i('PermissionService: Permission state: $_state');
      return _state;
    } catch (e) {
      logger.e('PermissionService: Error checking permission: $e');
      _setState(PermissionState.unknown);
      return _state;
    }
  }

  /// 请求权限
  Future<PermissionState> requestPermission() async {
    try {
      logger.i('PermissionService: Requesting permissions...');

      // 先尝试请求 MANAGE_EXTERNAL_STORAGE (All files access)
      final manageStorageStatus = await Permission.manageExternalStorage.request();
      logger.i('MANAGE_EXTERNAL_STORAGE status: $manageStorageStatus');
      
      // 如果获得了完全访问权限，直接返回
      if (manageStorageStatus.isGranted) {
        _setState(PermissionState.granted);
        logger.i('PermissionService: MANAGE_EXTERNAL_STORAGE granted');
        return _state;
      }

      // 否则请求基本存储权限
      final storageStatus = await Permission.storage.request();

      // Android 13+ 请求媒体权限
      final photosStatus = await Permission.photos.request();
      final videosStatus = await Permission.videos.request();

      // 判断结果
      if (storageStatus.isGranted ||
          (photosStatus.isGranted && videosStatus.isGranted)) {
        _setState(PermissionState.granted);
        logger.i('PermissionService: Storage/Media permission granted');
      } else if (storageStatus.isPermanentlyDenied ||
          photosStatus.isPermanentlyDenied ||
          videosStatus.isPermanentlyDenied) {
        _setState(PermissionState.permanentlyDenied);
        logger.w('PermissionService: Permission permanently denied');
      } else {
        _setState(PermissionState.denied);
        logger.w('PermissionService: Permission denied');
      }

      return _state;
    } catch (e) {
      logger.e('PermissionService: Error requesting permission: $e');
      _setState(PermissionState.unknown);
      return _state;
    }
  }

  /// 打开应用设置页面
  Future<void> openAppSettings() async {
    try {
      logger.i('PermissionService: Opening app settings...');
      await openAppSettings();
    } catch (e) {
      logger.e('PermissionService: Error opening app settings: $e');
    }
  }

  /// 重置权限检查状态（用于刷新）
  void resetCheckState() {
    _hasChecked = false;
    _setState(PermissionState.unknown);
    logger.d('PermissionService: Check state reset');
  }

  void _setState(PermissionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }
}
