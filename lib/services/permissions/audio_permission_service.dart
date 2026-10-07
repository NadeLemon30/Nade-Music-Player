import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Provider for the [AudioPermissionService] singleton/instance.
final audioPermissionServiceProvider = Provider<AudioPermissionService>((ref) {
  return AppAudioPermissionService();
});

/// Status of permission authorization for accessing device audio media files.
enum AudioPermissionStatus {
  /// Permission has been granted.
  granted,

  /// Permission is denied, but can be requested again.
  denied,

  /// Permission is permanently denied and requires opening app settings.
  permanentlyDenied,

  /// Permission is restricted by system policy.
  restricted,

  /// Limited permission granted.
  limited,
}

/// Contract for checking and requesting audio media permissions.
abstract class AudioPermissionService {
  /// Checks the current permission status without prompting the user.
  Future<AudioPermissionStatus> checkPermission();

  /// Requests audio media permission from the user.
  Future<AudioPermissionStatus> requestPermission();

  /// Returns true if audio permission is granted or limited.
  Future<bool> hasPermission();

  /// Opens the device app settings screen.
  Future<bool> openAppSettings();
}

/// Concrete implementation handling modern Android (API 33+ READ_MEDIA_AUDIO),
/// legacy Android (API <= 32 READ_EXTERNAL_STORAGE), and fallback platforms.
class AppAudioPermissionService implements AudioPermissionService {
  final DeviceInfoPlugin _deviceInfoPlugin;

  AppAudioPermissionService({DeviceInfoPlugin? deviceInfoPlugin})
      : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  /// Returns the target permission based on platform and Android API level.
  Future<ph.Permission?> _getTargetPermission() async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Modern Android (API 33+ / Android 13+) uses READ_MEDIA_AUDIO
        return ph.Permission.audio;
      } else {
        // Legacy Android (API <= 32) uses READ_EXTERNAL_STORAGE
        return ph.Permission.storage;
      }
    } else if (Platform.isIOS) {
      return ph.Permission.mediaLibrary;
    }

    // Desktop/other platforms have direct file access
    return null;
  }

  @override
  Future<AudioPermissionStatus> checkPermission() async {
    final permission = await _getTargetPermission();
    if (permission == null) {
      return AudioPermissionStatus.granted;
    }

    final status = await permission.status;
    return _mapStatus(status);
  }

  @override
  Future<AudioPermissionStatus> requestPermission() async {
    final permission = await _getTargetPermission();
    if (permission == null) {
      return AudioPermissionStatus.granted;
    }

    final status = await permission.request();
    return _mapStatus(status);
  }

  @override
  Future<bool> hasPermission() async {
    final status = await checkPermission();
    return status == AudioPermissionStatus.granted ||
        status == AudioPermissionStatus.limited;
  }

  @override
  Future<bool> openAppSettings() async {
    return await ph.openAppSettings();
  }

  AudioPermissionStatus _mapStatus(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
        return AudioPermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return AudioPermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return AudioPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return AudioPermissionStatus.restricted;
      case ph.PermissionStatus.limited:
        return AudioPermissionStatus.limited;
      case ph.PermissionStatus.provisional:
        return AudioPermissionStatus.granted;
    }
  }
}

/// Mock permission service for unit tests and offline testing.
class MockAudioPermissionService implements AudioPermissionService {
  AudioPermissionStatus currentStatus;
  bool appSettingsOpened = false;

  MockAudioPermissionService({
    this.currentStatus = AudioPermissionStatus.denied,
  });

  @override
  Future<AudioPermissionStatus> checkPermission() async => currentStatus;

  @override
  Future<AudioPermissionStatus> requestPermission() async => currentStatus;

  @override
  Future<bool> hasPermission() async =>
      currentStatus == AudioPermissionStatus.granted ||
      currentStatus == AudioPermissionStatus.limited;

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened = true;
    return true;
  }
}
