import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('Path Navigation Tests', () {
    test('Windows path navigation should work correctly', () {
      // 测试 Windows 路径
      final windowsPath = 'C:\\Users\\Documents\\folder';
      final parentPath = path.dirname(windowsPath);
      
      expect(parentPath, equals('C:\\Users\\Documents'));
      
      // 测试根目录
      final rootPath = 'C:\\';
      final rootParent = path.dirname(rootPath);
      expect(rootParent, equals('C:\\'));
      
      // 测试驱动器根
      final driveRoot = 'C:';
      final driveParent = path.dirname(driveRoot);
      expect(driveParent, equals('.'));
    });
    
    test('Unix path navigation should work correctly', () {
      // 测试 Unix 路径
      final unixPath = '/home/user/documents/folder';
      final parentPath = path.dirname(unixPath);
      
      expect(parentPath, equals('/home/user/documents'));
      
      // 测试根目录
      final rootPath = '/';
      final rootParent = path.dirname(rootPath);
      expect(rootParent, equals('/'));
    });
  });
}