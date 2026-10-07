import 'package:drift/drift.dart';

/// Relational table for user-favorited tracks (Phase 3I).
///
/// Stores the immutable track snapshot denormalized (mirroring `play_history`)
/// so the Favorites screen can render a [Track]'s metadata/art even if the
/// track is absent from the active library scan. The primary key is the
/// MediaStore song ID (the [Track.id]) — a track can be favorited at most once.
///
/// `favoritedAt` records when the track was favorited so the Favorites screen
/// can sort by "most recently favorited" without an extra join.
@DataClassName('FavoriteEntryData')
class Favorites extends Table {
  TextColumn get trackId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get albumArtist => text()();
  TextColumn get genre => text()();
  IntColumn get year => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get artistId => integer().nullable()();
  IntColumn get albumId => integer().nullable()();
  TextColumn get albumArtUri => text().nullable()();
  BoolColumn get isAsset => boolean().withDefault(const Constant(false))();

  /// When the track was added to favorites, used to order the list.
  DateTimeColumn get favoritedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {trackId};
}
