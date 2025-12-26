import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/file_change_listener_service.dart';
import 'package:easyfile/core/services/app_statistics_cache.dart';

void main() {
  group('FileChangeListenerService Tests', () {
    test('should create instance successfully', () {
      final cache = AppStatisticsCache();
      final service = FileChangeListenerService(statisticsCache: cache);
      
      expect(service, isNotNull);
      expect(service.isListening, false);
      expect(service.lastEventTime, isNull);
    });

    test('should start and stop listening', () async {
      final cache = AppStatisticsCache();
      await cache.initialize();
      
      final service = FileChangeListenerService(statisticsCache: cache);
      
      // Start listening
      await service.startListening();
      expect(service.isListening, true);
      
      // Stop listening
      service.stopListening();
      expect(service.isListening, false);
    });

    test('should cleanup on dispose', () async {
      final cache = AppStatisticsCache();
      await cache.initialize();
      
      final service = FileChangeListenerService(statisticsCache: cache);
      await service.startListening();
      
      expect(service.isListening, true);
      
      service.dispose();
      expect(service.isListening, false);
    });
  });
}
