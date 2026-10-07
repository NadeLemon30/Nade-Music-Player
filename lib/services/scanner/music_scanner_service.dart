import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/utils/metadata_utils.dart';
import '../../models/track.dart';
import '../permissions/audio_permission_service.dart';

/// Scanner service providing an abstraction over [OnAudioQuery] and Android MediaStore.
class MusicScannerService {
  final OnAudioQuery _audioQuery;
  final AudioPermissionService _permissionService;
  final StreamController<List<Track>> _changesController =
      StreamController<List<Track>>.broadcast();

  MusicScannerService({
    OnAudioQuery? audioQuery,
    AudioPermissionService? permissionService,
  })  : _audioQuery = audioQuery ?? OnAudioQuery(),
        _permissionService =
            permissionService ?? AppAudioPermissionService();

  /// Requests audio media permission.
  Future<bool> requestPermission() async {
    final onAudioQueryPerm = await _audioQuery.permissionsRequest();
    if (onAudioQueryPerm) return true;
    return await _permissionService.hasPermission();
  }

  /// Checks whether audio media permission is granted.
  Future<bool> hasPermission() async {
    final onAudioQueryStatus = await _audioQuery.permissionsStatus();
    if (onAudioQueryStatus) return true;
    return await _permissionService.hasPermission();
  }

  /// Scans and returns parsed [Track] audio songs directly from MediaStore.
  Future<List<Track>> scanSongs() async {
    final songs = await _audioQuery.querySongs();

    final tracks = songs.map(_mapSong).toList();

    tracks.sort(
      (a, b) => a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          ),
    );

    return tracks;
  }

  Track _mapSong(SongModel song) {
    return Track(
      id: song.id.toString(),
      title: _cleanTitle(song),
      artist: cleanMetadata(song.artist),
      album: cleanMetadata(song.album),
      albumArtist: cleanMetadata(
        (song.getMap['album_artist'] ?? song.artist).toString(),
      ),
      genre: cleanMetadata(song.genre),
      artistId: song.artistId,
      year: int.tryParse(song.getMap['year']?.toString() ?? ''),
      trackNumber: song.track,
      discNumber: int.tryParse(song.getMap['disc_number']?.toString() ?? ''),
      duration: song.duration != null
          ? Duration(milliseconds: song.duration!)
          : null,
      filePath: song.data,
      fileName: song.displayNameWOExt,
      fileSize: song.size,
      mimeType: song.fileExtension,
      albumId: song.albumId,
      albumArtUri: song.albumId?.toString(),
      isAvailable: true,
    );
  }

  String _cleanTitle(SongModel song) {
    final cleaned = cleanMetadata(song.title);

    if (cleaned != 'Unknown') {
      return cleaned;
    }

    final fallback = cleanMetadata(
      song.displayNameWOExt,
      fallback: 'Unknown Title',
    );
    return fallback;
  }

  /// Scans the local device storage / MediaStore for audio tracks.
  /// Returns a list of parsed [Track] domain objects.
  Future<List<Track>> scan() async {
    try {
      final hasPerm = await hasPermission();
      if (!hasPerm) {
        final granted = await requestPermission();
        if (!granted) {
          debugPrint('MusicScannerService: Permission not granted. Aborting scan.');
          return [];
        }
      }

      final songModels = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final tracks = songModels
          .where((song) => (song.duration ?? 0) > 0 && song.data.isNotEmpty)
          .map(_mapSong)
          .toList();

      if (!_changesController.isClosed) {
        _changesController.add(tracks);
      }

      return tracks;
    } catch (e, stack) {
      debugPrint('MusicScannerService error during scan: $e\n$stack');
      return [];
    }
  }

  /// Observes or scans for newly added, modified, or removed audio tracks.
  Stream<List<Track>> scanChanges() {
    return _changesController.stream;
  }

  /// Releases any active scanner streams or resources.
  Future<void> dispose() async {
    if (!_changesController.isClosed) {
      await _changesController.close();
    }
  }
}

/// Mock scanner service for unit testing and development preview.
class MockMusicScannerService extends MusicScannerService {
  final List<Track> tracks;
  bool permissionGranted;

  MockMusicScannerService({
    List<Track>? tracks,
    this.permissionGranted = true,
  })  : tracks = tracks ?? [],
        super();

  @override
  Future<bool> requestPermission() async {
    return permissionGranted;
  }

  @override
  Future<bool> hasPermission() async {
    return permissionGranted;
  }

  @override
  Future<List<Track>> scanSongs() async {
    if (!permissionGranted) {
      return [];
    }
    return List.unmodifiable(tracks);
  }

  @override
  Future<List<Track>> scan() async {
    if (!permissionGranted) {
      return [];
    }
    return List.unmodifiable(tracks);
  }

  void emitChanges(List<Track> updatedTracks) {
    // Mock helper
  }
}

/// Riverpod provider for the [MusicScannerService].
final musicScannerServiceProvider = Provider<MusicScannerService>((ref) {
  final permissionService = ref.watch(audioPermissionServiceProvider);
  return MusicScannerService(
    permissionService: permissionService,
  );
});
