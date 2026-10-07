import 'package:drift/drift.dart';

import '../../models/album.dart';
import '../../models/track.dart';
import '../database/app_database.dart';

/// Repository responsible for the relational `albums` table.
///
/// Albums are normalized from the MediaStore album ID treated as the album
/// artwork level of the library hierarchy (artists -> albums -> tracks).
class AlbumRepository {
  final AppDatabase _database;

  AlbumRepository([
    AppDatabase? database,
  ]) : _database = database ?? AppDatabase();

  /// Retrieves all albums, ordered by title.
  Future<List<Album>> getAllAlbums() async {
    final rows = await (_database.select(_database.albums)
          ..orderBy([
            (album) => OrderingTerm(
                  expression: album.title,
                ),
          ]))
        .get();

    return rows.map(_mapAlbum).toList();
  }

  /// Retrieves a single album by its MediaStore album ID, or null if absent.
  Future<Album?> getAlbum(int albumId) async {
    final query = _database.select(_database.albums)
      ..where(
        (album) => album.id.equals(albumId),
      );

    final row = await query.getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _mapAlbum(row);
  }

  /// Retrieves the albums belonging to an artist, ordered by title.
  ///
  /// Uses the relational `albums.artistId` link populated during
  /// [synchronizeAlbums], enabling the Artist -> Albums drilldown.
  Future<List<Album>> getAlbumsByArtist(int artistId) async {
    final rows = await (_database.select(_database.albums)
          ..where(
            (album) => album.artistId.equals(artistId),
          )
          ..orderBy([
            (album) => OrderingTerm(
                  expression: album.title,
                ),
          ]))
        .get();

    return rows.map(_mapAlbum).toList();
  }

  /// Searches albums matching [query] by title or album artist.
  ///
  /// An empty or blank query returns the full library via [getAllAlbums].
  Future<List<Album>> searchAlbums(String query) async {
    final normalized = query.trim();

    if (normalized.isEmpty) {
      return getAllAlbums();
    }

    final searchPattern = '%$normalized%';

    final rows = await (_database.select(_database.albums)
          ..where(
            (album) =>
                album.title.like(searchPattern) |
                album.albumArtist.like(searchPattern),
          )
          ..orderBy([
            (album) => OrderingTerm(
                  expression: album.title,
                ),
          ]))
        .get();

    return rows.map(_mapAlbum).toList();
  }

  /// Retrieves the available tracks belonging to an album, ordered by disc
  /// number then track number.
  Future<List<Track>> getAlbumTracks(int albumId) async {
    final rows = await (_database.select(_database.tracks)
          ..where(
            (track) =>
                track.albumId.equals(albumId) &
                track.isAvailable.equals(true),
          )
          ..orderBy([
            (track) => OrderingTerm(
                  expression: track.discNumber,
                ),
            (track) => OrderingTerm(
                  expression: track.trackNumber,
                ),
          ]))
        .get();

    return rows.map(_mapTrack).toList();
  }

  Album _mapAlbum(AlbumEntry row) {
    return Album(
      id: row.id,
      title: row.title,
      albumArtist: row.albumArtist,
      artistId: row.artistId,
      year: row.year,
      trackCount: row.trackCount,
      artworkKey: row.artworkKey,
    );
  }

  /// Rebuilds the `albums` table from the distinct album IDs in `tracks`.
  ///
  /// Albums are aggregated from the current tracks (grouped by MediaStore album
  /// ID) and the table is fully rebuilt, so stale album rows are removed.
  Future<void> synchronizeAlbums() async {
    final tracks = await _database
        .select(
          _database.tracks,
        )
        .get();

    final albums = <int, _AlbumAccumulator>{};

    for (final track in tracks) {
      final albumId = track.albumId;

      if (albumId == null) {
        continue;
      }

      final existing = albums[albumId];

      if (existing == null) {
        albums[albumId] = _AlbumAccumulator(
          id: albumId,
          title: track.album,
          albumArtist: track.albumArtist,
          artistId: track.artistId,
          year: track.year,
          trackCount: 1,
        );
      } else {
        existing.trackCount++;
      }
    }

    await _database.transaction(() async {
      await _database.delete(_database.albums).go();

      for (final album in albums.values) {
        await _database.into(_database.albums).insert(
              AlbumsCompanion.insert(
                id: Value(album.id),
                title: album.title,
                albumArtist: album.albumArtist,
                artistId: Value(album.artistId),
                year: Value(album.year),
                trackCount: Value(album.trackCount),
              ),
            );
      }
    });
  }

  Track _mapTrack(TrackEntry row) {
    return Track(
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album,
      albumArtist: row.albumArtist,
      genre: row.genre,
      artistId: row.artistId,
      year: row.year,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      duration: row.durationMs != null
          ? Duration(milliseconds: row.durationMs!)
          : null,
      filePath: row.filePath,
      fileName: row.fileName,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      albumId: row.albumId,
      isAvailable: row.isAvailable,
    );
  }
}

/// Mutable accumulator used while grouping tracks into albums during sync.
class _AlbumAccumulator {
  final int id;
  final String title;
  final String albumArtist;
  final int? artistId;
  final int? year;
  int trackCount;

  _AlbumAccumulator({
    required this.id,
    required this.title,
    required this.albumArtist,
    required this.artistId,
    required this.year,
    required this.trackCount,
  });
}
