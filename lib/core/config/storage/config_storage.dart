/// 配置存储抽象接口
/// 
/// 所有配置类依赖此接口，不依赖具体实现。
/// 便于测试和替换存储方式。
abstract class ConfigStorage {
  // ==================== 基础读取 ====================
  
  int? getInt(String key);
  double? getDouble(String key);
  bool? getBool(String key);
  String? getString(String key);
  List<String>? getStringList(String key);

  // ==================== 基础写入 ====================
  
  Future<bool> setInt(String key, int value);
  Future<bool> setDouble(String key, double value);
  Future<bool> setBool(String key, bool value);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);

  // ==================== 管理操作 ====================
  
  Future<bool> remove(String key);
  Future<bool> clear();
  bool containsKey(String key);

  /// 批量写入（用于远程配置合并）
  Future<void> setAll(Map<String, dynamic> values);
  
  /// 获取所有键
  Set<String> getKeys();
}
