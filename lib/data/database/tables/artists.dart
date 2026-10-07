import 'package:drift/drift.dart';

/// Relational table for artists.
///
/// The primary key is the Android MediaStore artist ID, allowing artists to be
/// recognized across scans for reliable normalization and updates.
@DataClassName('ArtistEntry')
class Artists extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get sortName => text()();
  IntColumn get albumCount => integer().withDefault(const Constant(0))();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
