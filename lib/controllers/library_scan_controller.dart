import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/music_repository.dart';
import '../services/favorites/favorites_service.dart';
import '../services/playback/play_history_service.dart';
import '../services/playlists/playlist_service.dart';
import '../services/scanner/music_library_sync_service.dart';

/// State of local media scanning and library synchronization.
class LibraryScanState {
  final bool isScanning;
  final int scannedCount;
  final int addedCount;
  final int updatedCount;
  final int removedCount;
  final DateTime? lastScanTime;
  final String? errorMessage;

  const LibraryScanState({
    this.isScanning = false,
    this.scannedCount = 0,
    this.addedCount = 0,
    this.updatedCount = 0,
    this.removedCount = 0,
    this.lastScanTime,
    this.errorMessage,
  });

  LibraryScanState copyWith({
    bool? isScanning,
    int? scannedCount,
    int? addedCount,
    int? updatedCount,
    int? removedCount,
    DateTime? lastScanTime,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryScanState(
      isScanning: isScanning ?? this.isScanning,
      scannedCount: scannedCount ?? this.scannedCount,
      addedCount: addedCount ?? this.addedCount,
      updatedCount: updatedCount ?? this.updatedCount,
      removedCount: removedCount ?? this.removedCount,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Riverpod notifier coordinating local device scanning with the SQLite database.
class LibraryScanController extends Notifier<LibraryScanState> {
  MusicLibrarySyncService get _library =>
      ref.read(musicLibrarySyncServiceProvider);

  MusicRepository get _repository => ref.read(musicRepositoryProvider);

  @override
  LibraryScanState build() {
    return const LibraryScanState();
  }

  /// Triggers a device scan and synchronizes discovered tracks with SQLite.
  Future<int> scanMusic() async {
    if (state.isScanning) return state.scannedCount;

    state = state.copyWith(isScanning: true, clearError: true);

    try {
      final result = await _library.synchronize();
      // Spec 23: mirror the DB-level relationship purge (removed tracks) into
      // the in-memory favorites / play-history / playlist collections.
      await _syncCollectionMirrors();

      state = state.copyWith(
        isScanning: false,
        scannedCount: result.total,
        addedCount: result.added,
        updatedCount: result.updated,
        removedCount: result.removed,
        lastScanTime: _library.lastScanTime,
      );

      return result.total;
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: e.toString(),
      );
      return 0;
    }
  }

  /// Drops deleted-track entries from the in-memory collection mirrors using
  /// the set of tracks still present in the database after a scan (spec 23).
  Future<void> _syncCollectionMirrors() async {
    final availableIds = await _repository.getAllTrackIds();
    await ref.read(favoritesServiceProvider).pruneMissingTracks(availableIds);
    await ref.read(playHistoryServiceProvider).pruneMissingTracks(availableIds);
    await ref.read(playlistServiceProvider).pruneMissingTracks(availableIds);
  }

  /// Clears all library tracks and metadata from the database.
  Future<void> clearLibrary() async {
    await _repository.clearAll();
    state = const LibraryScanState();
  }
}

/// Provider exposing [LibraryScanController] and [LibraryScanState].
final libraryScanControllerProvider =
    NotifierProvider<LibraryScanController, LibraryScanState>(
  LibraryScanController.new,
);

/// Provider exposing the [MusicLibrarySyncService].
final musicLibrarySyncServiceProvider =
    Provider<MusicLibrarySyncService>((ref) => MusicLibrarySyncService());
