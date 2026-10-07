import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/permissions/audio_permission_service.dart';


/// Riverpod Notifier managing reactive audio permission state.
class PermissionNotifier extends Notifier<AudioPermissionStatus> {
  @override
  AudioPermissionStatus build() {
    return AudioPermissionStatus.denied;
  }

  /// Checks the current permission state without prompting.
  Future<AudioPermissionStatus> checkPermission() async {
    final service = ref.read(audioPermissionServiceProvider);
    final status = await service.checkPermission();
    state = status;
    return status;
  }

  /// Requests audio permission from the user.
  Future<AudioPermissionStatus> requestPermission() async {
    final service = ref.read(audioPermissionServiceProvider);
    final status = await service.requestPermission();
    state = status;
    return status;
  }

  /// Opens the device application settings screen.
  Future<bool> openAppSettings() async {
    final service = ref.read(audioPermissionServiceProvider);
    return await service.openAppSettings();
  }
}

/// Provider exposing [PermissionNotifier] and reactive [AudioPermissionStatus].
final permissionNotifierProvider =
    NotifierProvider<PermissionNotifier, AudioPermissionStatus>(
  PermissionNotifier.new,
);
