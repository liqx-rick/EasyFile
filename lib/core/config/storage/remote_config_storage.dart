import 'config_storage.dart';

/// 远程配置存储实现（预留，可接入 Firebase Remote Config 或自建服务）
///
/// 这个类展示了如何实现远程配置：
/// 1. 从远程服务器获取配置
/// 2. 本地缓存作为 fallback
/// 3. 支持优先级覆盖（远程 > 本地）
///
/// 使用示例：
/// ```dart
/// final remoteStorage = await RemoteConfigStorage.create(
///   remoteUrl: 'https://api.example.com/config',
///   localFallback: await LocalConfigStorage.create(),
/// );
/// await AppConfig.instance.initialize(storage: remoteStorage);
/// ```
class RemoteConfigStorage implements ConfigStorage {
  final String remoteUrl;
  final ConfigStorage localFallback;
  final Map<String, dynamic> _remoteCache = {};

  bool _initialized = false;

  RemoteConfigStorage({
    required this.remoteUrl,
    required this.localFallback,
  });

  /// 工厂方法：创建并初始化远程配置
  static Future<RemoteConfigStorage> create({
    required String remoteUrl,
    required ConfigStorage localFallback,
  }) async {
    final storage = RemoteConfigStorage(
      remoteUrl: remoteUrl,
      localFallback: localFallback,
    );
    await storage._fetchRemoteConfig();
    return storage;
  }

  /// 从远程服务器获取配置
  Future<void> _fetchRemoteConfig() async {
    try {
      // TODO: 实现实际的 HTTP 请求
      // final response = await http.get(Uri.parse(remoteUrl));
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body) as Map<String, dynamic>;
      //   _remoteCache.addAll(data);
      //   _initialized = true;
      // }

      // 临时示例：模拟远程配置
      _remoteCache.addAll({
        'feature_new_files': true,
        'feature_premium': false,
        'scan_large_file_threshold': 100,
        'scan_new_files_retention': 15,
      });
      _initialized = true;
    } catch (e) {
      // 如果获取失败，使用本地配置
      _initialized = false;
    }
  }

  /// 刷新远程配置
  Future<void> refresh() async {
    await _fetchRemoteConfig();
  }

  // ==================== 读取实现（优先级：远程 > 本地） ====================

  @override
  int? getInt(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return _remoteCache[key] as int?;
    }
    return localFallback.getInt(key);
  }

  @override
  double? getDouble(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return _remoteCache[key] as double?;
    }
    return localFallback.getDouble(key);
  }

  @override
  bool? getBool(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return _remoteCache[key] as bool?;
    }
    return localFallback.getBool(key);
  }

  @override
  String? getString(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return _remoteCache[key] as String?;
    }
    return localFallback.getString(key);
  }

  @override
  List<String>? getStringList(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return _remoteCache[key] as List<String>?;
    }
    return localFallback.getStringList(key);
  }

  // ==================== 写入实现（写入本地，不影响远程） ====================

  @override
  Future<bool> setInt(String key, int value) {
    return localFallback.setInt(key, value);
  }

  @override
  Future<bool> setDouble(String key, double value) {
    return localFallback.setDouble(key, value);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    return localFallback.setBool(key, value);
  }

  @override
  Future<bool> setString(String key, String value) {
    return localFallback.setString(key, value);
  }

  @override
  Future<bool> setStringList(String key, List<String> value) {
    return localFallback.setStringList(key, value);
  }

  // ==================== 管理操作 ====================

  @override
  Future<bool> remove(String key) {
    return localFallback.remove(key);
  }

  @override
  Future<bool> clear() {
    return localFallback.clear();
  }

  @override
  bool containsKey(String key) {
    if (_initialized && _remoteCache.containsKey(key)) {
      return true;
    }
    return localFallback.containsKey(key);
  }

  @override
  Future<void> setAll(Map<String, dynamic> values) {
    return localFallback.setAll(values);
  }

  @override
  Set<String> getKeys() {
    final keys = localFallback.getKeys();
    if (_initialized) {
      keys.addAll(_remoteCache.keys);
    }
    return keys;
  }
}
