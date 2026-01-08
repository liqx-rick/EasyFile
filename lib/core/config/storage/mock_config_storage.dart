import 'config_storage.dart';

/// Mock 配置存储（用于单元测试）
///
/// 完全内存实现，不依赖 SharedPreferences。
class MockConfigStorage implements ConfigStorage {
  final Map<String, dynamic> _data = {};

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  List<String>? getStringList(String key) => _data[key] as List<String>?;

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<void> setAll(Map<String, dynamic> values) async {
    _data.addAll(values);
  }

  @override
  Set<String> getKeys() => _data.keys.toSet();

  /// 测试辅助：直接读取内存数据
  dynamic getRaw(String key) => _data[key];

  /// 测试辅助：获取所有数据
  Map<String, dynamic> getAll() => Map.from(_data);
}
