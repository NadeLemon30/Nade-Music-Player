import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import 'music_repository.dart';

/// A single playlist-history row, denormalized to what the UI needs.
class PlaylistHistoryEntry {
  PlaylistHistoryEntry({
    required this.playlistId,
    required this.playCount,
    this.lastPlayedAt,
  });

  /// The playlist's UUID id (`playlists.id`).
  final String playlistId;

  /// Number of explicit playlist-level plays.
  final int playCount;

  /// When the playlist was last played at playlist level.
  final DateTime? lastPlayedAt;
}

/// Persistence layer for playlist-level playback history (Phase 3K, spec 3K.3).
///
/// Lives out of the per-song [PlayHistoryService] table: only explicit
/// playlist-level playback (Play Playlist / Shuffle Playlist) counts here —
/// playing individual songs never does. Rows are keyed by the playlist's UUID;
/// they are not linked by a foreign key, so deleting a playlist leaves its
/// history behind until [remove] / [clear] is called (the spec defines no
/// cascade for this table).
class PlaylistHistoryRepository {
  PlaylistHistoryRepository(this._db);

  final AppDatabase _db;

  /// Records a playlist-level play of [playlistId]: bumps `play_count` and
  /// refreshes `last_played_at` to now. Creates the row on first play.
  Future<void> recordPlay(String playlistId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.playlistHistory)
          ..where((r) => r.playlistId.equals(playlistId)))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.playlistHistory).insert(
            PlaylistHistoryCompanion.insert(
              playlistId: playlistId,
              playCount: const Value(1),
              lastPlayedAt: Value(now),
            ),
          );
      return;
    }

    await (_db.update(_db.playlistHistory)
          ..where((r) => r.playlistId.equals(playlistId)))
        .write(
      PlaylistHistoryCompanion(
        playCount: Value(existing.playCount + 1),
        lastPlayedAt: Value(now),
      ),
    );
  }

  /// All playlist-history rows, most recently played first (ties broken by the
  /// higher play count).
  Future<List<PlaylistHistoryEntry>> getRecentlyPlayed() async {
    final rows = await (_db.select(_db.playlistHistory)
          ..orderBy([
            (r) => OrderingTerm.desc(r.lastPlayedAt),
            (r) => OrderingTerm.desc(r.playCount),
          ]))
        .get();
    return rows.map(_toEntry).toList();
  }

  /// How many times [playlistId] has been played at playlist level (0 when it
  /// has never been played).
  Future<int> getPlayCount(String playlistId) async {
    final row = await (_db.select(_db.playlistHistory)
          ..where((r) => r.playlistId.equals(playlistId)))
        .getSingleOrNull();
    return row?.playCount ?? 0;
  }

  /// Removes [playlistId] from playlist history entirely.
  Future<void> remove(String playlistId) async {
    await (_db.delete(_db.playlistHistory)
          ..where((r) => r.playlistId.equals(playlistId)))
        .go();
  }

  /// Empty table in one statement.
  Future<void> clear() async {
    await _db.delete(_db.playlistHistory).go();
  }

  PlaylistHistoryEntry _toEntry(PlaylistHistoryEntryData row) {
    return PlaylistHistoryEntry(
      playlistId: row.playlistId,
      playCount: row.playCount,
      lastPlayedAt: row.lastPlayedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastPlayedAt!),
    );
  }
}

/// Provider for the singleton [PlaylistHistoryRepository], backed by Drift.
final playlistHistoryRepositoryProvider =
    Provider<PlaylistHistoryRepository>((ref) {
  return PlaylistHistoryRepository(ref.watch(appDatabaseProvider));
});