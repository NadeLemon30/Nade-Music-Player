import 'package:drift/drift.dart';

/// Relational table for per-track playback history (Phase 3H).
///
/// Denormalizes enough track metadata to reconstruct a [Track] for the
/// "Recently played" / History UI even if the track is absent from the library
/// scan, mirroring the earlier JSON-backed history. The primary key is the
/// MediaStore song ID (the [Track.id]).
@DataClassName('PlayHistoryEntryData')
class PlayHistory extends Table {
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

  /// The number of times the track has been played.
  IntColumn get playCount => integer().withDefault(const Constant(0))();

  /// The last time the track finished loading/playing, used to order history.
  DateTimeColumn get lastPlayedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Saved playback position (milliseconds) to resume from on reopen.
  IntColumn get resumePositionMs =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {trackId};
}
