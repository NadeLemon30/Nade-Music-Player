import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/permissions/audio_permission_service.dart';

void main() {
  group('MockAudioPermissionService', () {
    test('initial state is denied by default', () async {
      final service = MockAudioPermissionService();
      expect(await service.checkPermission(), AudioPermissionStatus.denied);
      expect(await service.hasPermission(), false);
    });

    test('granted status returns true for hasPermission', () async {
      final service = MockAudioPermissionService(
        currentStatus: AudioPermissionStatus.granted,
      );
      expect(await service.checkPermission(), AudioPermissionStatus.granted);
      expect(await service.hasPermission(), true);
    });

    test('limited status returns true for hasPermission', () async {
      final service = MockAudioPermissionService(
        currentStatus: AudioPermissionStatus.limited,
      );
      expect(await service.hasPermission(), true);
    });

    test('requestPermission returns configured status', () async {
      final service = MockAudioPermissionService(
        currentStatus: AudioPermissionStatus.granted,
      );
      final status = await service.requestPermission();
      expect(status, AudioPermissionStatus.granted);
    });

    test('openAppSettings marks settings as opened', () async {
      final service = MockAudioPermissionService();
      expect(service.appSettingsOpened, false);
      final result = await service.openAppSettings();
      expect(result, true);
      expect(service.appSettingsOpened, true);
    });
  });
}
