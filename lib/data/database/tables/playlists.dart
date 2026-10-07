import 'package:drift/drift.dart';

/// Metadata table for user-created playlists (Phase 3J).
///
/// Stores only the playlist header: a UUID [id] (3J.5 — the name is NOT the
/// identifier, so a rename never changes the playlist's identity), the display
/// [name], and when it was [createdAt]. The songs themselves live in the
/// `playlist_tracks` one-to-many join table ([PlaylistTracks]).
@DataClassName('PlaylistEntryData')
class Playlists extends Table {
  /// UUID identifier; the playlist name is deliberately not used as the key
  /// (3J.5) since it can change without affecting the playlist's identity.
  TextColumn get id => text()();

  /// Display name of the playlist.
  TextColumn get name => text()();

  /// When the playlist was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}