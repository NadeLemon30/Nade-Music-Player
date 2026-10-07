import 'package:drift/drift.dart';

import '../../models/artist.dart';
import '../database/app_database.dart';

/// Repository responsible for the relational `artists` table.
///
/// Artists are normalized from the MediaStore artist ID extracted during each
/// scan, so artist rows are populated/synchronized from the current tracks.
class ArtistRepository {
  final AppDatabase _database;

  ArtistRepository([
    AppDatabase? database,
  ]) : _database = database ?? AppDatabase();

  /// Rebuilds the `artists` table from the distinct artist IDs in `tracks`.
  ///
  /// The set is fully rebuilt from the current tracks: any previous artist rows
  /// whose songs no longer exist are removed, and surviving artists re-inserted.
  /// This is acceptable for now because the artists table has no relationships
  /// to other user-created entities yet; reference handling will be introduced
  /// alongside playlists.
  Future<void> synchronizeArtists() async {
    final tracks = await _database.select(_database.tracks).get();

    final artists = <int, String>{};

    for (final track in tracks) {
      final artistId = track.artistId;

      if (artistId == null) {
        continue;
      }

      artists[artistId] = track.artist;
    }

    await _database.transaction(() async {
      await _database.delete(_database.artists).go();

      for (final entry in artists.entries) {
        final artistId = entry.key;
        final artistName = entry.value;

        await _database.into(_database.artists).insert(
              ArtistsCompanion.insert(
                id: Value(artistId),
                name: artistName,
                sortName: artistName.toLowerCase(),
              ),
            );
      }
    });
  }

  /// Retrieves all artists, ordered by their sort (case-insensitive) name.
  ///
  /// Song counts are computed live from the `tracks` table rather than trusting
  /// the stored `trackCount` column, which is not yet maintained by sync.
  Future<List<Artist>> getAllArtists() {
    return (_database.select(_database.artists)
          ..orderBy([
            (artist) => OrderingTerm(
                  expression: artist.sortName,
                ),
          ]))
        .get()
        .then((rows) => Future.wait(rows.map(_mapEntry)));
  }

  /// Searches artists matching [query] by name.
  ///
  /// An empty or blank query returns the full library via [getAllArtists].
  /// Results are ordered by their sort (case-insensitive) name, with live song
  /// counts computed from the `tracks` table.
  Future<List<Artist>> searchArtists(String query) async {
    final normalized = query.trim();

    if (normalized.isEmpty) {
      return getAllArtists();
    }

    final searchPattern = '%$normalized%';

    final rows = await (_database.select(_database.artists)
          ..where(
            (artist) => artist.name.like(searchPattern),
          )
          ..orderBy([
            (artist) => OrderingTerm(
                  expression: artist.sortName,
                ),
          ]))
        .get();

    return Future.wait(rows.map(_mapEntry));
  }

  /// Live reactive stream of all artists in the relational `artists` table.
  ///
  /// Emits fresh results whenever either the artists table or the tracks table
  /// changes, with song counts computed live from `tracks`.
  Stream<List<Artist>> watchArtists() {
    return (_database.select(_database.artists)
          ..orderBy([
            (artist) => OrderingTerm(
                  expression: artist.sortName,
                ),
          ]))
        .watch()
        .asyncMap((rows) => Future.wait(rows.map(_mapEntry)));
  }

  Future<Artist> _mapEntry(ArtistEntry row) async {
    return Artist(
      id: row.id.toString(),
      name: row.name,
      trackCount: await getTrackCount(row.id),
    );
  }

  /// Returns the number of tracks currently associated with an artist.
  Future<int> getTrackCount(int artistId) async {
    final query = _database.selectOnly(_database.tracks)
      ..addColumns([
        _database.tracks.id.count(),
      ])
      ..where(
        _database.tracks.artistId.equals(artistId),
      );

    return await query
            .map((row) => row.read(_database.tracks.id.count()))
            .getSingle() ??
        0;
  }
}
