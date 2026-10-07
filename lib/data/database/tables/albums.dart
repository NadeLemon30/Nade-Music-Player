import 'package:drift/drift.dart';

/// Relational table for albums, at the album-artwork level of the library.
///
/// The primary key is the Android MediaStore album ID, allowing albums to be
/// recognized across scans for reliable synchronization. Artwork is referenced
/// by [artworkKey] rather than stored as a BLOB — the image itself is cached
/// outside of SQLite.
@DataClassName('AlbumEntry')
class Albums extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get albumArtist => text()();
  IntColumn get artistId => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  TextColumn get artworkKey => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
