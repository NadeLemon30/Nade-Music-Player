import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/track.dart';

/// A recorded playback event for the "Recently played" / History UI.
class PlayHistoryEntry {
  final Track track;

  /// The last time the track was played, used to order history.
  final DateTime playedAt;

  /// The number of times the track has been played.
  final int playCount;

  /// Saved playback position to resume from on reopen.
  final Duration resumePosition;

  const PlayHistoryEntry({
    required this.track,
    required this.playedAt,
    this.playCount = 1,
    this.resumePosition = Duration.zero,
  });

  PlayHistoryEntry copyWith({
    Track? track,
    DateTime? playedAt,
    int? playCount,
    Duration? resumePosition,
  }) {
    return PlayHistoryEntry(
      track: track ?? this.track,
      playedAt: playedAt ?? this.playedAt,
      playCount: playCount ?? this.playCount,
      resumePosition: resumePosition ?? this.resumePosition,
    );
  }
}

/// Persistent playback history backed by the Drift `play_history` table.
///
/// Tracks the most recent plays, a per-track play count, the last-played
/// timestamp, and a per-track resume position. Entries are de-duplicated by
/// track ID (playing a song again moves it to the top and increments its
/// count). The default constructor requires [db]; the no-arg form is used by
/// test stubs (e.g. [NoopPlayHistoryService]) that override all persistence.
class PlayHistoryService {
  final AppDatabase? _db;

  /// Maximum number of in-memory entries kept, most recent first.
  final int maxEntries;

  final List<PlayHistoryEntry> _entries = [];
  final StreamController<List<PlayHistoryEntry>> _controller =
      StreamController<List<PlayHistoryEntry>>.broadcast();

  bool _loaded = false;

  PlayHistoryService([
    this._db,
    this.maxEntries = 50,
  ]);

  /// Live list of recently played entries, most recent first.
  Stream<List<PlayHistoryEntry>> get entriesStream => _controller.stream;

  /// Snapshot of the current entries, most recent first.
  List<PlayHistoryEntry> get entries => List.unmodifiable(_entries);

  /// Whether the service has a backing database (false only in test stubs).
  bool get hasBackingStore => _db != null;

  /// Closes the broadcast stream used by [entriesStream].
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await _restore();
  }

  /// Records a play, de-duplicating by track id, bumping the play count and
  /// refreshing the last-played timestamp.
  Future<void> record(Track track) async {
    await _ensureLoaded();

    final now = DateTime.now();
    final existingIndex =
        _entries.indexWhere((e) => e.track.id == track.id);

    if (existingIndex >= 0) {
      final existing = _entries.removeAt(existingIndex);
      _entries.insert(
        0,
        existing.copyWith(
          track: track,
          playedAt: now,
          playCount: existing.playCount + 1,
        ),
      );
    } else {
      _entries.insert(0, PlayHistoryEntry(track: track, playedAt: now, playCount: 1));
    }

    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }

    final db = _db;
    if (db != null) {
      await db.into(db.playHistory).insertOnConflictUpdate(
            _entryToCompanion(track, now, playCount: _playCountFor(track.id)),
          );
    }

    _emit();
  }

  /// Persists a resumed playback [position] for [trackId] without treating it
  /// as a brand-new play.
  Future<void> saveResumePosition(
    String trackId,
    Duration position,
  ) async {
    await _ensureLoaded();

    final index = _entries.indexWhere((e) => e.track.id == trackId);
    if (index >= 0) {
      _entries[index] =
          _entries[index].copyWith(resumePosition: position);
    }
    _emit();

    final db = _db;
    if (db != null) {
      final millis = position.inMilliseconds;
      await (db.update(db.playHistory)
            ..where((r) => r.trackId.equals(trackId)))
          .write(PlayHistoryCompanion(resumePositionMs: Value(millis)));
    }
  }

  /// Removes a single history entry by track id.
  Future<void> removeEntry(String trackId) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.track.id == trackId);
    _emit();

    final db = _db;
    if (db != null) {
      await (db.delete(db.playHistory)
            ..where((r) => r.trackId.equals(trackId)))
          .go();
    }
  }

  /// Removes all recorded plays.
  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    _emit();

    final db = _db;
    if (db != null) {
      await db.delete(db.playHistory).go();
    }
  }

  int _playCountFor(String trackId) {
    final index = _entries.indexWhere((e) => e.track.id == trackId);
    if (index < 0) return 1;
    return _entries[index].playCount;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_entries));
    }
  }

  PlayHistoryCompanion _entryToCompanion(
    Track track,
    DateTime playedAt, {
    required int playCount,
  }) {
    return PlayHistoryCompanion.insert(
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
      playCount: Value(playCount),
      lastPlayedAt: Value(playedAt),
      resumePositionMs: Value(_resumeFor(track.id)),
    );
  }

  int _resumeFor(String trackId) {
    final index = _entries.indexWhere((e) => e.track.id == trackId);
    if (index < 0) return 0;
    return _entries[index].resumePosition.inMilliseconds;
  }

  Future<void> _restore() async {
    final db = _db;
    if (db == null) return;

    try {
      final rows = await (db.select(db.playHistory)
            ..orderBy([
              (r) => OrderingTerm.desc(r.lastPlayedAt),
            ]))
          .get();

      _entries
        ..clear()
        ..addAll(rows.map(_rowToEntry));
    } catch (_) {
      // Non-fatal: fall back to an empty history for this session.
    }
  }

  /// The [limit] most recently played tracks, most recent first (3H.11).
  ///
  /// Conceptually emits
  /// `SELECT * FROM playback_history ORDER BY last_played_at DESC LIMIT ?`
  /// (the `last_played_at IS NOT NULL` guard is implicit — the column is
  /// non-nullable with a default). A bounded, ordered read. Falls back to the
  /// in-memory entries (already deduped + most-recent-first) when there is no
  /// Drift backing store.
  Future<List<PlayHistoryEntry>> getRecentlyPlayed({
    int limit = 50,
  }) async {
    final db = _db;
    if (db == null) {
      final all = List.of(_entries);
      return all.length > limit ? all.sublist(0, limit) : all;
    }

    await _ensureLoaded();
    final rows = await (db.select(db.playHistory)
          ..orderBy([(r) => OrderingTerm.desc(r.lastPlayedAt)])
          ..limit(limit))
        .get();
    return rows.map(_rowToEntry).toList();
  }

  /// Live [getRecentlyPlayed]: re-emits the [limit] most recent entries
  /// whenever the history table changes.
  Stream<List<PlayHistoryEntry>> watchRecentlyPlayed({
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) {
      return entriesStream;
    }
    return (db.select(db.playHistory)
          ..orderBy([(r) => OrderingTerm.desc(r.lastPlayedAt)])
          ..limit(limit))
        .watch()
        .map((rows) => rows.map(_rowToEntry).toList());
  }

  /// The [Track]s of the [limit] most recently played entries, most recent
  /// first (3H.30). Entries whose track is no longer available are omitted.
  Future<List<Track>> getRecentlyPlayedTracks({int limit = 50}) async {
    final entries = await getRecentlyPlayed(limit: limit);
    return entries
        .map((e) => e.track)
        .where((t) => t.isAvailable)
        .toList();
  }

  /// Lazy removal of stale history entries whose music file has been deleted
  /// (3H.29). Called when the Recently Played / History UI is shown rather
  /// than continuously scanning. [availableTrackIds] are the tracks known to
  /// still exist in the library; any entry outside that set is dropped (from
  /// memory and the `play_history` table). The actual song file is untouched
  /// (3H.28).
  Future<void> pruneMissingTracks(Set<String> availableTrackIds) async {
    await _ensureLoaded();

    final before = _entries.length;
    _entries.removeWhere((e) => !availableTrackIds.contains(e.track.id));
    if (_entries.length != before) {
      _emit();
    }

    final db = _db;
    if (db != null) {
      final keep = {for (final e in _entries) e.track.id};
      final all = await (db.select(db.playHistory)).get();
      for (final row in all) {
        if (!keep.contains(row.trackId)) {
          await removeEntry(row.trackId);
        }
      }
    }
  }

  PlayHistoryEntry _rowToEntry(PlayHistoryEntryData row) {
    return PlayHistoryEntry(
      track: Track(
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
      ),
      playedAt: row.lastPlayedAt,
      playCount: row.playCount,
      resumePosition: Duration(milliseconds: row.resumePositionMs),
    );
  }
}

/// Provider exposing the singleton [PlayHistoryService], backed by Drift.
final playHistoryServiceProvider = Provider<PlayHistoryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final service = PlayHistoryService(db);
  ref.onDispose(service.dispose);
  return service;
});

/// Live "Recently played" entries, most recent first. Emits once empty.
final recentlyPlayedProvider =
    StreamProvider<List<PlayHistoryEntry>>((ref) async* {
  final service = ref.watch(playHistoryServiceProvider);
  yield service.entries;
  yield* service.watchRecentlyPlayed();
});
