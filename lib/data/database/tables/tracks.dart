import 'package:drift/drift.dart';

/// Relational table for audio tracks, denormalized around the Android MediaStore.
///
/// The primary key is the MediaStore song ID, allowing the database to recognize
/// "this is the same song I scanned previously" for reliable synchronization.
@DataClassName('TrackEntry')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  IntColumn get artistId => integer().nullable()();
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
  IntColumn get albumId => integer().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
