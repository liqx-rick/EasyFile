import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/utils/time_formatter.dart';

void main() {
  group('TimeFormatter Tests', () {
    test('should format time within 1 minute as "刚刚"', () {
      final now = DateTime.now();
      final time = now.subtract(const Duration(seconds: 30));
      expect(TimeFormatter.formatRelativeTime(time), '刚刚');
    });

    test('should format time within 1 hour as "X分钟前"', () {
      final now = DateTime.now();
      final time = now.subtract(const Duration(minutes: 25));
      expect(TimeFormatter.formatRelativeTime(time), '25分钟前');
    });

    test('should format time within 24 hours as "X小时前"', () {
      final now = DateTime.now();
      final time = now.subtract(const Duration(hours: 5));
      expect(TimeFormatter.formatRelativeTime(time), '5小时前');
    });

    test('should format time 1 day ago as "昨天"', () {
      final now = DateTime.now();
      final time = now.subtract(const Duration(days: 1));
      expect(TimeFormatter.formatRelativeTime(time), '昨天');
    });

    test('should format time within 7 days as "X天前"', () {
      final now = DateTime.now();
      final time = now.subtract(const Duration(days: 3));
      expect(TimeFormatter.formatRelativeTime(time), '3天前');
    });

    test('should format time over 7 days as "MM-DD"', () {
      final time = DateTime(2025, 11, 1, 10, 30);
      final result = TimeFormatter.formatRelativeTime(time);
      expect(result, '11-01');
    });

    test('should format full time correctly', () {
      final time = DateTime(2025, 11, 11, 14, 30);
      expect(
        TimeFormatter.formatFullTime(time),
        '2025-11-11 14:30',
      );
    });
  });
}
