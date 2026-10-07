import '../../data/database/app_database.dart';
import '../../data/repositories/album_repository.dart';
import '../../data/repositories/artist_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/genre.dart';
import '../../models/library_scan_result.dart';
import '../../models/track.dart';
import 'music_scanner_service.dart';

/// High-level service coordinating MediaStore scanning, SQLite persistence, and
/// the normalization of artists and albums into their relational tables.
///
/// This is the single entry point the application uses to build and refresh the
/// on-device library. It layers the [MusicScannerService] (device scan) over a
/// [MusicRepository] backed by the [AppDatabase] (persistence) and re-syncs the
/// normalized `artists` and `albums` tables after every pass.
///
/// Decoupling rule: UI code talks to this service, never directly to
/// [MusicScannerService], `OnAudioQuery`, or platform permission constants.
class MusicLibrarySyncService {
  final MusicScannerService _scanner;
  final MusicRepository _repository;
  final ArtistRepository _artistRepository;
  final AlbumRepository _albumRepository;

  DateTime? _lastScanTime;

  /// Timestamp of the last successful [synchronize] pass, or null before the
  /// first scan.
  DateTime? get lastScanTime => _lastScanTime;

  MusicLibrarySyncService({
    MusicScannerService? scanner,
    AppDatabase? database,
  })  : _scanner = scanner ?? MusicScannerService(),
        _repository = DriftMusicRepository(database ?? AppDatabase()),
        _artistRepository = ArtistRepository(database ?? AppDatabase()),
        _albumRepository = AlbumRepository(database ?? AppDatabase());

  /// Requests audio media permission on the underlying platform.
  Future<bool> requestPermission() => _scanner.requestPermission();

  /// Checks whether audio media permission is currently granted.
  Future<bool> hasPermission() => _scanner.hasPermission();

  /// Runs a fresh MediaStore scan and synchronizes the persisted library.
  ///
  /// Discovery, persistence, and normalization run in this order:
  /// 1. Scan the device for audio tracks (permission is ensured internally).
  /// 2. Diff the fresh scan against the stored track IDs to compute
  ///    added/updated/removed counts.
  /// 3. Persist the scanned tracks and remove stale rows.
  /// 4. Re-normalize the `artists` and `albums` relational tables.
  ///
  /// Returns a [LibraryScanResult] summarizing the changes performed.
  Future<LibraryScanResult> synchronize() async {
    final tracks = await _scanner.scan();

    final existingIds = await _repository.getAllTrackIds();
    final scannedIds = tracks.map((t) => t.id).toSet();

    final removedIds = existingIds.difference(scannedIds);

    final updated = tracks
        .map((t) => t.id)
        .where(existingIds.contains)
        .toSet()
        .length;

    await _repository.saveTracks(tracks);
    await _repository.deleteTracksByIds(removedIds);

    // Spec 23/24 — library synchronization integrity: tracks that vanished from
    // the device are purged from every collection relationship (favorites, play
    // history, playlist membership) in one transaction. Playlists themselves
    // survive; their member lists are what shrink.
    if (removedIds.isNotEmpty) {
      await _repository.purgeTrackRelations(removedIds);
    }

    await _artistRepository.synchronizeArtists();
    await _albumRepository.synchronizeAlbums();

    _lastScanTime = DateTime.now();

    return LibraryScanResult(
      added: scannedIds.difference(existingIds).length,
      updated: updated,
      removed: removedIds.length,
      total: tracks.length,
    );
  }

  /// Returns all tracks currently persisted in the library.
  Future<List<Track>> getLibrary() => _repository.getAllTracks();

  /// Returns the total number of available tracks in the library.
  Future<int> getTrackCount() => _repository.getTrackCount();

  /// Returns all artists, including live track counts.
  Future<List<Artist>> getArtists() => _repository.getArtists();

  /// Returns all genres with their track counts.
  Future<List<Genre>> getGenres() => _repository.getGenres();

  /// Returns all albums with artist information and track counts.
  Future<List<Album>> getAlbums() => _repository.getAlbums();

  /// Permanently removes all tracks from the library.
  Future<void> clearLibrary() => _repository.clearAll();
}
