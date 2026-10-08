import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/permission_controller.dart';
import 'package:nades_music_player/services/permissions/audio_permission_service.dart';

void main() {
  group('PermissionNotifier', () {
    test('initial state is denied', () {
      final mockService = MockAudioPermissionService();
      final container = ProviderContainer(
        overrides: [
          audioPermissionServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(permissionNotifierProvider),
        AudioPermissionStatus.denied,
      );
    });

    test('checkPermission updates state to granted', () async {
      final mockService = MockAudioPermissionService(
        currentStatus: AudioPermissionStatus.granted,
      );
      final container = ProviderContainer(
        overrides: [
          audioPermissionServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      final status = await container
          .read(permissionNotifierProvider.notifier)
          .checkPermission();

      expect(status, AudioPermissionStatus.granted);
      expect(
        container.read(permissionNotifierProvider),
        AudioPermissionStatus.granted,
      );
    });

    test('requestPermission updates state when granted', () async {
      final mockService = MockAudioPermissionService(
        currentStatus: AudioPermissionStatus.granted,
      );
      final container = ProviderContainer(
        overrides: [
          audioPermissionServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      final status = await container
          .read(permissionNotifierProvider.notifier)
          .requestPermission();

      expect(status, AudioPermissionStatus.granted);
      expect(
        container.read(permissionNotifierProvider),
        AudioPermissionStatus.granted,
      );
    });

    test('openAppSettings delegates to service', () async {
      final mockService = MockAudioPermissionService();
      final container = ProviderContainer(
        overrides: [
          audioPermissionServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      expect(mockService.appSettingsOpened, false);
      final result = await container
          .read(permissionNotifierProvider.notifier)
          .openAppSettings();

      expect(result, true);
      expect(mockService.appSettingsOpened, true);
    });
  });
}
