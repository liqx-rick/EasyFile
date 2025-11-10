import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/sources/local_file_source.dart';

void main() {
  group('LocalFileRepository Tests', () {
    late LocalFileRepository repository;

    setUp(() {
      repository = LocalFileRepository();
    });

    test('should return empty list for non-existent directory', () async {
      final files = await repository.getFiles('/non_existent_path');
      expect(files, isEmpty);
    });

    test('should handle file listing errors gracefully', () async {
      // 测试无权限访问的目录
      final files = await repository.getFiles('/system');
      expect(files, isA<List>());
    });
  });
}
