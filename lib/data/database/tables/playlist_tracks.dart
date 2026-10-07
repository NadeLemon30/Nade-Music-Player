import 'package:drift/drift.dart';

import 'playlists.dart';

/// One-to-many join table associating tracks with a playlist (Phase 3J).
///
/// A playlist owns an ordered list of songs; [position] preserves the user's
/// custom ordering (0-based). The composite primary key `(playlistId, trackId)`
/// means a track can appear at most once per playlist — adding an already-added
/// track is a no-op. `ON DELETE CASCADE` mirrors the spec 3J.3: deleting a
/// playlist automatically drops all of its rows.
@DataClassName('PlaylistTrackEntryData')
class PlaylistTracks extends Table {
  /// The owning playlist's UUID ([Playlists.id]).
  TextColumn get playlistId => text().references(Playlists, #id)();

  /// The track's MediaStore song id ([Track.id]).
  TextColumn get trackId => text()();

  /// 0-based order of this track within the playlist.
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}