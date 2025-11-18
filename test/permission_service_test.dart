import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/permission_service.dart';

void main() {
  group('PermissionService', () {
    late PermissionService permissionService;

    setUp(() {
      permissionService = PermissionService();
    });

    test('初始状态应为unknown', () {
      expect(permissionService.state, PermissionState.unknown);
      expect(permissionService.hasChecked, false);
    });

    test('PermissionState扩展方法应正确工作', () {
      expect(PermissionState.granted.isGranted, true);
      expect(PermissionState.denied.isDenied, true);
      expect(PermissionState.permanentlyDenied.isPermanentlyDenied, true);
      expect(PermissionState.unknown.isUnknown, true);

      expect(PermissionState.denied.needsRequest, true);
      expect(PermissionState.unknown.needsRequest, true);
      expect(PermissionState.granted.needsRequest, false);

      expect(PermissionState.permanentlyDenied.needsSettings, true);
      expect(PermissionState.denied.needsSettings, false);
    });

    test('重置状态应将hasChecked设为false', () {
      permissionService.resetCheckState();
      expect(permissionService.hasChecked, false);
      expect(permissionService.state, PermissionState.unknown);
    });
  });
}
