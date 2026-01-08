import 'package:shared_preferences/shared_preferences.dart';
import 'config_storage.dart';

/// 本地配置存储实现（使用 SharedPreferences）
class LocalConfigStorage implements ConfigStorage {
  final SharedPreferences _prefs;

  const LocalConfigStorage(this._prefs);

  /// 工厂方法：创建实例
  static Future<LocalConfigStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalConfigStorage(prefs);
  }

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  double? getDouble(String key) => _prefs.getDouble(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  @override
  Future<void> setAll(Map<String, dynamic> values) async {
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is int) {
        await setInt(key, value);
      } else if (value is double) {
        await setDouble(key, value);
      } else if (value is bool) {
        await setBool(key, value);
      } else if (value is String) {
        await setString(key, value);
      } else if (value is List<String>) {
        await setStringList(key, value);
      }
    }
  }

  @override
  Set<String> getKeys() => _prefs.getKeys();
}
