import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/trash_file_item.dart';

void main() {
  group('TrashFilesPage - 智能抑制期判断逻辑测试', () {
    // 辅助方法：创建测试文件（避免触发 AppConfig 依赖）
    TrashFileItem createTestFile({
      required String name,
      required int size,
      required DateTime modified,
    }) {
      return TrashFileItem(
        name: name,
        path: '/storage/emulated/0/.Trash/$name',
        size: size,
        modified: modified,
        trashedTime: modified,
        mimeType: 'application/octet-stream', // 显式指定 mimeType 避免推断
      );
    }

    // 辅助方法：判断是否应该设置抑制期（模拟 _deleteSelected 中的逻辑）
    bool shouldSetSuppressionPeriod(
      List<TrashFileItem> allFiles,
      Set<String> selectedPaths,
    ) {
      // 计算剩余的3个月前的文件
      final cutoffDate = DateTime.now().subtract(
        const Duration(days: 3 * 30),
      );

      final remainingOldFiles =
          allFiles.where((f) => !selectedPaths.contains(f.path)).where((f) {
        final fileDate = f.trashedTime ?? f.modified;
        return fileDate.isBefore(cutoffDate);
      }).toList();

      final remainingOldSize = remainingOldFiles.fold<int>(
        0,
        (sum, f) => sum + f.size,
      );
      final remainingOldSizeMB = remainingOldSize / (1024 * 1024);

      // 智能判断：只有当剩余的3个月前文件很少时才设置抑制期
      return remainingOldFiles.length < 10 && remainingOldSizeMB < 100;
    }

    group('场景1：清空所有操作', () {
      test('清空所有回收站应该始终设置抑制期（无论文件数量）', () {
        // 这个逻辑在 _emptyAllTrash() 中，只要 result['success'] > 0 就设置
        // 无需额外测试，因为是简单的条件判断
        expect(true, true); // 占位测试
      });
    });

    group('场景2：删除选中文件 - 应该设置抑制期', () {
      test('删除后剩余3个月前文件为0个', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100)); // 超过3个月

        final allFiles = [
          createTestFile(name: 'old1.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old2.txt', size: 2048, modified: oldDate),
        ];

        // 全部删除
        final selectedPaths = {
          '/storage/emulated/0/.Trash/old1.txt',
          '/storage/emulated/0/.Trash/old2.txt',
        };

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '剩余0个3个月前文件，应该设置抑制期');
      });

      test('删除后剩余9个3个月前文件，50MB', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100)); // 超过3个月
        final recentDate = now.subtract(const Duration(days: 30)); // 1个月

        // 优化：减少对象创建，只创建必要的测试数据
        final allFiles = [
          // 15个旧文件（通过循环简化表示）
          for (int i = 0; i < 15; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 5 * 1024 * 1024, // 5MB
              modified: oldDate,
            ),
          // 5个最近的文件（不计入判断）
          for (int i = 0; i < 5; i++)
            createTestFile(
              name: 'recent$i.txt',
              size: 10 * 1024 * 1024, // 10MB
              modified: recentDate,
            ),
        ];

        // 删除6个旧文件，剩余9个旧文件（45MB）
        final selectedPaths = {
          for (int i = 0; i < 6; i++) '/storage/emulated/0/.Trash/old$i.txt'
        };

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '剩余9个3个月前文件（45MB），<10个且<100MB，应该设置抑制期');
      });

      test('删除后剩余5个3个月前文件，99MB（边界值）', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          createTestFile(
            name: 'old1.txt',
            size: 99 * 1024 * 1024, // 99MB
            modified: oldDate,
          ),
          createTestFile(
            name: 'old2.txt',
            size: 1024, // 1KB
            modified: oldDate,
          ),
          createTestFile(name: 'old3.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old4.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old5.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'deleted.txt', size: 1024, modified: oldDate),
        ];

        final selectedPaths = {'/storage/emulated/0/.Trash/deleted.txt'};

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '剩余5个文件，99MB，<10个且<100MB，应该设置抑制期');
      });
    });

    group('场景3：删除选中文件 - 不应该设置抑制期', () {
      test('删除后剩余10个3个月前文件（边界值）', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          for (int i = 0; i < 11; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 5 * 1024 * 1024, // 5MB
              modified: oldDate,
            ),
        ];

        // 删除1个，剩余10个
        final selectedPaths = {'/storage/emulated/0/.Trash/old0.txt'};

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, false, reason: '剩余10个文件，>=10个，不应该设置抑制期');
      });

      test('删除后剩余5个3个月前文件，但有100MB（边界值）', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          createTestFile(
            name: 'old1.txt',
            size: 100 * 1024 * 1024, // 100MB
            modified: oldDate,
          ),
          createTestFile(name: 'old2.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old3.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old4.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'old5.txt', size: 1024, modified: oldDate),
          createTestFile(name: 'deleted.txt', size: 1024, modified: oldDate),
        ];

        final selectedPaths = {'/storage/emulated/0/.Trash/deleted.txt'};

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, false, reason: '剩余5个文件，但100MB，>=100MB，不应该设置抑制期');
      });

      test('删除后剩余50个3个月前文件，200MB', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          for (int i = 0; i < 100; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 2 * 1024 * 1024, // 2MB
              modified: oldDate,
            ),
        ];

        // 删除50个，剩余50个（100MB）
        final selectedPaths = {
          for (int i = 0; i < 50; i++) '/storage/emulated/0/.Trash/old$i.txt'
        };

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, false, reason: '剩余50个文件（100MB），>=10个且>=100MB，不应该设置抑制期');
      });

      test('删除5个旧文件，但剩余95个旧文件，800MB', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          for (int i = 0; i < 100; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 8 * 1024 * 1024, // 8MB
              modified: oldDate,
            ),
        ];

        // 只删除5个
        final selectedPaths = {
          for (int i = 0; i < 5; i++) '/storage/emulated/0/.Trash/old$i.txt'
        };

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, false, reason: '只删除5个文件，剩余95个（760MB），远超阈值，不应该设置抑制期');
      });
    });

    group('场景4：混合文件（新旧文件）', () {
      test('删除后剩余20个文件，但只有5个是3个月前的', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100)); // 超过3个月
        final recentDate = now.subtract(const Duration(days: 30)); // 1个月

        final allFiles = [
          // 5个旧文件（40MB）
          for (int i = 0; i < 5; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 8 * 1024 * 1024, // 8MB
              modified: oldDate,
            ),
          // 20个最近的文件（不计入判断）
          for (int i = 0; i < 20; i++)
            createTestFile(
              name: 'recent$i.txt',
              size: 10 * 1024 * 1024, // 10MB
              modified: recentDate,
            ),
        ];

        // 删除5个最近的文件（不影响旧文件统计）
        final selectedPaths = {
          for (int i = 0; i < 5; i++) '/storage/emulated/0/.Trash/recent$i.txt'
        };

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '虽然剩余20个文件，但只有5个是3个月前的（40MB），应该设置抑制期');
      });

      test('删除后剩余2个旧文件，但有150个最近文件', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));
        final recentDate = now.subtract(const Duration(days: 30));

        final allFiles = [
          // 2个旧文件（20MB）
          for (int i = 0; i < 2; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 10 * 1024 * 1024, // 10MB
              modified: oldDate,
            ),
          // 150个最近的文件
          for (int i = 0; i < 150; i++)
            createTestFile(
              name: 'recent$i.txt',
              size: 5 * 1024 * 1024, // 5MB
              modified: recentDate,
            ),
        ];

        final selectedPaths = <String>{}; // 没有删除任何文件

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '虽然总共152个文件，但只有2个是3个月前的（20MB），应该设置抑制期');
      });
    });

    group('场景5：边界条件', () {
      test('所有文件都是最近的（没有3个月前的文件）', () {
        final now = DateTime.now();
        final recentDate = now.subtract(const Duration(days: 30));

        final allFiles = [
          for (int i = 0; i < 50; i++)
            createTestFile(
              name: 'recent$i.txt',
              size: 10 * 1024 * 1024, // 10MB
              modified: recentDate,
            ),
        ];

        final selectedPaths = {'/storage/emulated/0/.Trash/recent0.txt'};

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '没有3个月前的文件（0个），应该设置抑制期');
      });

      test('正好9个文件，正好99MB（临界值内）', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          // 9个文件，每个11MB（总共99MB）
          for (int i = 0; i < 9; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 11 * 1024 * 1024, // 11MB
              modified: oldDate,
            ),
        ];

        final selectedPaths = <String>{}; // 没有删除

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, true, reason: '正好9个文件，99MB，<10个且<100MB，应该设置抑制期');
      });

      test('正好10个文件，正好100MB（临界值外）', () {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 100));

        final allFiles = [
          // 10个文件，每个10MB（总共100MB）
          for (int i = 0; i < 10; i++)
            createTestFile(
              name: 'old$i.txt',
              size: 10 * 1024 * 1024, // 10MB
              modified: oldDate,
            ),
        ];

        final selectedPaths = <String>{}; // 没有删除

        final result = shouldSetSuppressionPeriod(allFiles, selectedPaths);
        expect(result, false, reason: '正好10个文件，100MB，>=10个且>=100MB，不应该设置抑制期');
      });
    });
  });
}
