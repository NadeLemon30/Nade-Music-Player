import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/track.dart';

/// An immutable favorite entry: the favorited [track] plus the time it was
/// favorited, used to (re)order the Favorites list.
class FavoriteEntry {
  final Track track;

  /// When the track was added to favorites.
  final DateTime favoritedAt;

  const FavoriteEntry({
    required this.track,
    required this.favoritedAt,
  });

  FavoriteEntry copyWith({
    Track? track,
    DateTime? favoritedAt,
  }) {
    return FavoriteEntry(
      track: track ?? this.track,
      favoritedAt: favoritedAt ?? this.favoritedAt,
    );
  }
}

/// Persistent user favorites backed by the Drift `favorites` table (Phase 3I).
///
/// Keeps an in-memory mirror of the favorited tracks so the app can answer
/// "is this track a favorite?" instantly — [isFavorite] and the [favoriteIds]
/// set are O(1) lookups that never touch the database during normal UI frame
/// build. Favorites are de-duplicated by track ID (a track can be favorited at
/// most once; toggling an existing favorite removes it).
///
/// The default constructor requires [db]; the no-arg form is used by test
/// stubs that override all persistence. Sort preferences:
///   - [FavoriteSort.newest] — most recently favorited first (default).
///   - [FavoriteSort.artist] — grouped/sorted by artist name.
///   - [FavoriteSort.title] — sorted by track title.
class FavoritesService {
  final AppDatabase? _db;

  /// In-memory favorites, most recently favorited first. Used as the fast
  /// lookup mirror and the source for the ordered lists.
  final List<FavoriteEntry> _entries = [];

  /// O(1) membership lookup: the set of currently-favorited track IDs. Kept in
  /// sync with [_entries] so UI can answer "is this a favorite?" instantly.
  final Set<String> _favoriteIds = {};

  final StreamController<List<FavoriteEntry>> _controller =
      StreamController<List<FavoriteEntry>>.broadcast();

  bool _loaded = false;

  /// Resolves once the persisted favorites have been restored into memory.
  /// Getters that answer "is this a favorite?" synchronously rely on this
  /// having completed, so the service starts restoring eagerly on creation.
  Future<void>? _ready;

  FavoritesService([
    this._db,
    this.sort = FavoriteSort.newest,
  ]) {
    // Eagerly restore persisted favorites so the fast in-memory lookups
    // ([isFavorite], [favoriteIds]) reflect them on first use. `_ensureLoaded`
    // awaits the SAME future (_ready), so a call that races the eager restore
    // (e.g. the first `addFavorite` right after construction) never mutates a
    // snapshot that a still-running `_restore` is about to overwrite.
    _ready = _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    await _restore();
  }

  /// Completes once the persisted favorites are available in memory.
  Future<void> get ready => _ready ?? Future.value();

  Future<void> _ensureLoaded() async {
    await (_ready ?? Future.value());
  }

  /// Active sort order of the exposed lists.
  FavoriteSort sort;

  /// Live list of favorite entries under the configured [sort].
  Stream<List<FavoriteEntry>> get entriesStream => _controller.stream;

  /// Snapshot of the current favorite entries under the configured [sort].
  List<FavoriteEntry> get entries =>
      List.unmodifiable(_sorted());

  /// All currently-favorited track IDs (O(1) membership lookup).
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// Whether the service has a backing database (false only in test stubs).
  bool get hasBackingStore => _db != null;

  /// Closes the broadcast stream used by [entriesStream].
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  /// Whether [track] is currently a favorite (O(1), no DB round-trip).
  bool isFavorite(Track track) => _favoriteIds.contains(track.id);

  /// Whether the track with [trackId] is currently a favorite (O(1)).
  bool isFavoriteId(String trackId) => _favoriteIds.contains(trackId);

  /// The number of favorited tracks.
  int get count => _favoriteIds.length;

  /// Adds [track] to favorites. No-op when it is already favorited.
  Future<void> addFavorite(Track track) async {
    await _ensureLoaded();
    if (_favoriteIds.contains(track.id)) return;

    final now = DateTime.now();
    _entries.insert(0, FavoriteEntry(track: track, favoritedAt: now));
    _favoriteIds.add(track.id);
    _emit();

    final db = _db;
    if (db != null) {
      await db.into(db.favorites).insertOnConflictUpdate(
            _entryToCompanion(track, now),
          );
    }
  }

  /// Removes [track] from favorites. No-op when it is not favorited.
  Future<void> removeFavorite(Track track) async {
    await removeFavoriteId(track.id);
  }

  /// Removes the favorite with [trackId]. No-op when not favorited.
  Future<void> removeFavoriteId(String trackId) async {
    await _ensureLoaded();
    if (!_favoriteIds.remove(trackId)) return;

    _entries.removeWhere((e) => e.track.id == trackId);
    _emit();

    final db = _db;
    if (db != null) {
      await (db.delete(db.favorites)
            ..where((r) => r.trackId.equals(trackId)))
          .go();
    }
  }

  /// Adds [track] to favorites if it is not already, or removes it if it is.
  /// Returns `true` when the track ended up favorited, `false` when removed.
  Future<bool> toggleFavorite(Track track) async {
    if (isFavorite(track)) {
      await removeFavorite(track);
      return false;
    }
    await addFavorite(track);
    return true;
  }

  /// Removes all favorites.
  Future<void> clearFavorites() async {
    await _ensureLoaded();
    _entries.clear();
    _favoriteIds.clear();
    _emit();

    final db = _db;
    if (db != null) {
      await db.delete(db.favorites).go();
    }
  }

  /// The favorite [Track]s, under the configured [sort].
  List<Track> get favoriteTracks => _sorted().map((e) => e.track).toList();

  /// The favorite [Track]s available in the current library.
  List<Track> get favoriteTracksAvailable =>
      favoriteTracks.where((t) => t.isAvailable).toList();

  /// Lazy removal of favorites whose music file has been deleted (3I.29).
  ///
  /// Called when the Favorites screen is shown (matching the history prune
  /// pattern) rather than continuously. [availableTrackIds] are the tracks
  /// still present in the library; any favorite outside that set is dropped
  /// from memory and the `favorites` table. The song file itself is untouched.
  Future<void> pruneMissingTracks(Set<String> availableTrackIds) async {
    await _ensureLoaded();

    final ids = List.of(_favoriteIds);
    for (final id in ids) {
      if (!availableTrackIds.contains(id)) {
        // Remove the DB row directly (avoids per-row _emit churn).
        _entries.removeWhere((e) => e.track.id == id);
        _favoriteIds.remove(id);
        final db = _db;
        if (db != null) {
          await (db.delete(db.favorites)
                ..where((r) => r.trackId.equals(id)))
              .go();
        }
      }
    }
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_sorted()));
    }
  }

  /// Returns the entries ordered by the configured [sort] (default newest).
  List<FavoriteEntry> _sorted() {
    final list = List<FavoriteEntry>.of(_entries);
    switch (sort) {
      case FavoriteSort.newest:
        // _entries is maintained most-recently-favorited-first.
        break;
      case FavoriteSort.artist:
        list.sort((a, b) {
          final byArtist = a.track.artist.toLowerCase().compareTo(
                b.track.artist.toLowerCase(),
              );
          if (byArtist != 0) return byArtist;
          return a.track.title.toLowerCase().compareTo(
                b.track.title.toLowerCase(),
              );
        });
        break;
      case FavoriteSort.title:
        list.sort((a, b) => a.track.title.toLowerCase().compareTo(
              b.track.title.toLowerCase(),
            ));
        break;
    }
    return list;
  }

  FavoritesCompanion _entryToCompanion(Track track, DateTime favoritedAt) {
    return FavoritesCompanion.insert(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      albumArtist: track.albumArtist,
      genre: track.genre,
      year: Value(track.year),
      trackNumber: Value(track.trackNumber),
      discNumber: Value(track.discNumber),
      durationMs: Value(track.duration?.inMilliseconds),
      filePath: track.filePath,
      fileName: track.fileName,
      fileSize: Value(track.fileSize),
      mimeType: Value(track.mimeType),
      artistId: Value(track.artistId),
      albumId: Value(track.albumId),
      albumArtUri: Value(track.albumArtUri),
      isAsset: Value(track.isAsset),
      favoritedAt: Value(favoritedAt),
    );
  }

  Future<void> _restore() async {
    final db = _db;
    if (db == null) return;

    try {
      final rows = await (db.select(db.favorites)
            ..orderBy([(r) => OrderingTerm.desc(r.favoritedAt)]))
          .get();

      _entries
        ..clear()
        ..addAll(rows.map(_rowToEntry));
      _favoriteIds
        ..clear()
        ..addAll(_entries.map((e) => e.track.id));
    } catch (_) {
      // Non-fatal: fall back to an empty favorites list for this session.
    }
  }

  FavoriteEntry _rowToEntry(FavoriteEntryData row) {
    return FavoriteEntry(
      track: _rowToTrack(row),
      favoritedAt: row.favoritedAt,
    );
  }

  Track _rowToTrack(FavoriteEntryData row) {
    return Track(
      id: row.trackId,
      title: row.title,
      artist: row.artist,
      album: row.album,
      albumArtist: row.albumArtist,
      genre: row.genre,
      year: row.year,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      duration: row.durationMs != null
          ? Duration(milliseconds: row.durationMs!)
          : null,
      filePath: row.filePath,
      fileName: row.fileName,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      isAsset: row.isAsset,
      artistId: row.artistId,
      albumId: row.albumId,
      albumArtUri: row.albumArtUri,
      isAvailable: true,
    );
  }
}

/// The sort order for the Favorites list.
enum FavoriteSort {
  /// Most recently favorited first.
  newest,

  /// Grouped / sorted by artist name.
  artist,

  /// Sorted by track title.
  title,
}

/// Provider exposing the singleton [FavoritesService], backed by Drift.
final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final service = FavoritesService(db);
  ref.onDispose(service.dispose);
  return service;
});

/// Which track IDs are currently favorited, as a reactive [StreamProvider].
///
/// Emits a fresh [Set] whenever favorites change. This is what list tiles use
/// to render the filled vs. outline favorite heart without a per-track query.
final favoriteIdsProvider =
    StreamProvider<Set<String>>((ref) async* {
  final service = ref.watch(favoritesServiceProvider);
  // Ensure persisted favorites are loaded before the first synchronous yield.
  await service.ready;
  yield service.favoriteIds;
  yield* service.entriesStream.map((entries) {
    return entries.map((e) => e.track.id).toSet();
  });
});
