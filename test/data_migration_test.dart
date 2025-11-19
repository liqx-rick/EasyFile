import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/services/data_migration_service.dart';

/// 数据迁移服务测试
///
/// 由于DataMigrationService依赖多个外部服务（FavoritesLocalSource, QuickAccessLocalSource, FolderAnalyzer），
/// 完整的单元测试需要mock框架支持。
///
/// 此测试文件主要测试MigrationResult数据类和基本逻辑验证。
/// 完整的集成测试应该在应用运行时手动进行。
void main() {
  group('MigrationResult Tests', () {
    test('creates result with correct counts', () {
      final result = MigrationResult()
        ..totalCount = 10
        ..successCount = 7
        ..failedCount = 2
        ..skippedCount = 1
        ..errors = ['Error 1', 'Error 2'];

      expect(result.totalCount, equals(10));
      expect(result.successCount, equals(7));
      expect(result.failedCount, equals(2));
      expect(result.skippedCount, equals(1));
      expect(result.errors.length, equals(2));
      expect(result.errors, contains('Error 1'));
      expect(result.errors, contains('Error 2'));
    });

    test('creates result with no errors', () {
      final result = MigrationResult()
        ..totalCount = 5
        ..successCount = 5
        ..failedCount = 0
        ..skippedCount = 0
        ..errors = [];

      expect(result.totalCount, equals(5));
      expect(result.successCount, equals(5));
      expect(result.failedCount, equals(0));
      expect(result.skippedCount, equals(0));
      expect(result.errors, isEmpty);
      expect(result.isSuccess, isTrue);
      expect(result.hasData, isTrue);
    });

    test('result counts add up correctly', () {
      final result = MigrationResult()
        ..totalCount = 10
        ..successCount = 6
        ..failedCount = 3
        ..skippedCount = 1
        ..errors = ['Error 1', 'Error 2', 'Error 3'];

      // successCount + failedCount + skippedCount should equal totalCount
      expect(
        result.successCount + result.failedCount + result.skippedCount,
        equals(result.totalCount),
      );

      // Number of errors should match failedCount
      expect(result.errors.length, equals(result.failedCount));
      expect(result.isSuccess, isFalse); // Has failures
      expect(result.hasData, isTrue);
    });

    test('handles empty migration', () {
      final result = MigrationResult();

      expect(result.totalCount, equals(0));
      expect(result.successCount, equals(0));
      expect(result.failedCount, equals(0));
      expect(result.skippedCount, equals(0));
      expect(result.errors, isEmpty);
      expect(result.isSuccess, isFalse); // No data
      expect(result.hasData, isFalse);
    });

    test('summary string format', () {
      final result = MigrationResult()
        ..totalCount = 10
        ..successCount = 8
        ..failedCount = 1
        ..skippedCount = 1;

      expect(result.summary, contains('Total: 10'));
      expect(result.summary, contains('Success: 8'));
      expect(result.summary, contains('Failed: 1'));
      expect(result.summary, contains('Skipped: 1'));
      expect(result.toString(), equals(result.summary));
    });

    test('isSuccess flag', () {
      // Success case
      final successResult = MigrationResult()
        ..totalCount = 5
        ..successCount = 5
        ..failedCount = 0;
      expect(successResult.isSuccess, isTrue);

      // Has failures
      final failedResult = MigrationResult()
        ..totalCount = 5
        ..successCount = 4
        ..failedCount = 1;
      expect(failedResult.isSuccess, isFalse);

      // Empty migration
      final emptyResult = MigrationResult();
      expect(emptyResult.isSuccess, isFalse);
    });
  });

  // 集成测试检查清单 (需手动测试):
  //
  // 1. 首次启动测试:
  //    - 准备一些Favorites数据
  //    - 清空QuickAccess数据
  //    - 启动应用
  //    - 验证Splash页面显示"正在迁移收藏数据..."
  //    - 验证迁移完成后QuickAccess包含所有Favorites
  //    - 验证文件夹类型正确分类 (system/app/userCustom)
  //    - 验证文件夹统计信息正确
  //
  // 2. 不存在文件夹测试:
  //    - 添加不存在的路径到Favorites
  //    - 启动应用
  //    - 验证迁移跳过不存在的文件夹
  //    - 验证日志中记录skippedCount
  //
  // 3. 重复启动测试:
  //    - 迁移完成后再次启动应用
  //    - 验证不会重复迁移
  //    - 验证needsMigration()返回false
  //
  // 4. 性能测试:
  //    - 准备大量Favorites (50+)
  //    - 测试迁移时间在可接受范围内
  //    - 验证不阻塞UI
  //
  // 5. 错误处理测试:
  //    - 测试权限不足的文件夹
  //    - 测试分析失败的情况
  //    - 验证错误被正确记录但不中断进程
}
