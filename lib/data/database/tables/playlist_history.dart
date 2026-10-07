import 'package:drift/drift.dart';

/// Per-playlist playback history (Phase 3K, spec 3K.3).
///
/// Deliberately separate from the per-song `play_history` table: a "playlist
/// play" only counts when the user explicitly chooses playlist-level playback
/// (Play Playlist / Shuffle Playlist), never when individual songs from the
/// playlist are played. `playlist_id` is the playlist's UUID (the same id used
/// by the `playlists` table); `last_played_at` is a milliseconds-since-epoch
/// integer, matching the denormalized-track history's timestamp style.
@DataClassName('PlaylistHistoryEntryData')
class PlaylistHistory extends Table {
  /// The playlist's UUID id (`playlists.id`).
  TextColumn get playlistId => text()();

  /// How many times the playlist has been played at playlist level.
  IntColumn get playCount =>
      integer().withDefault(const Constant(0))();

  /// Milliseconds since epoch of the most recent playlist-level play.
  IntColumn get lastPlayedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {playlistId};
}