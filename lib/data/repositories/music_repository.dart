import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import 'album_repository.dart';
import 'artist_repository.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/folder_node.dart';
import '../../models/genre.dart';
import '../../models/search_results.dart';
import '../../models/track.dart';
import '../../services/folders/folder_service.dart';

/// Central repository interface for querying and persisting library media.
abstract class MusicRepository {
  /// Inserts or updates tracks into the database.
  Future<void> saveTracks(List<Track> tracks);

  /// Retrieves all tracks from the database.
  Future<List<Track>> getAllTracks();

  /// Retrieves the total number of tracks in the library.
  Future<int> getTrackCount();

  /// Retrieves all track IDs currently stored in the database.
  Future<Set<String>> getAllTrackIds();

  /// Permanently deletes the tracks with the given [ids] from the database.
  ///
  /// Returns the number of rows actually deleted. Safely returns 0 when [ids] is empty.
  Future<int> deleteTracksByIds(Set<String> ids);

  /// Removes all collection relationships pointing at [trackIds] in a single
  /// transaction (spec 23/24 — library synchronization integrity).
  ///
  /// Deletes the `favorites`, `play_history`, and `playlist_tracks` rows whose
  /// track has vanished from the library, then compacts each affected
  /// playlist's `position` values so ordering stays contiguous. The playlists
  /// themselves are never deleted. No-op when [trackIds] is empty.
  Future<void> purgeTrackRelations(Set<String> trackIds);

  /// Live reactive stream of all tracks.
  Stream<List<Track>> watchAllTracks();

  /// Retrieves the [limit] most recently added available tracks, newest first.
  Future<List<Track>> getRecentlyAddedTracks({int limit = 10});

  /// Retrieves all unique artists with aggregated track counts.
  Future<List<Artist>> getArtists();

  /// Live reactive stream of all artists.
  Stream<List<Artist>> watchArtists();

  /// Retrieves all albums with artist information and track counts.
  Future<List<Album>> getAlbums();

  /// Live reactive stream of all albums.
  Stream<List<Album>> watchAlbums();

  /// Retrieves all genres with track counts.
  Future<List<Genre>> getGenres();

  /// Live reactive stream of all genres.
  Stream<List<Genre>> watchGenres();

  /// Retrieves tracks associated with an artist.
  Future<List<Track>> getTracksByArtist(String artistId);

  /// Live reactive stream of tracks for a given artist.
  Stream<List<Track>> watchTracksByArtist(String artistId);

  /// Retrieves tracks whose MediaStore artist ID matches [artistId].
  Future<List<Track>> getTracksByArtistId(int artistId);

  /// Live reactive stream of tracks whose MediaStore artist ID matches [artistId].
  Stream<List<Track>> watchTracksByArtistId(int artistId);

  /// Retrieves albums associated with an artist.
  Future<List<Album>> getAlbumsByArtist(String artistId);

  /// Live reactive stream of albums for a given artist.
  Stream<List<Album>> watchAlbumsByArtist(String artistId);

  /// Retrieves albums associated with a MediaStore artist ID.
  Future<List<Album>> getAlbumsByArtistId(int artistId);

  /// Live reactive stream of albums for a given MediaStore artist ID.
  Stream<List<Album>> watchAlbumsByArtistId(int artistId);

  /// Retrieves tracks associated with an album.
  Future<List<Track>> getTracksByAlbum(String albumId);

  /// Live reactive stream of tracks for a given album, matched by album **title**.
  ///
  /// Prefer [watchTracksByAlbumId]: the album objects the UI holds carry the
  /// MediaStore `albumId` as [Album.id], so a title lookup never matches them.
  Stream<List<Track>> watchTracksByAlbum(String albumId);

  /// Retrieves tracks for a given MediaStore album ID, ordered by disc + track number.
  Future<List<Track>> getTracksByAlbumId(int albumId);

  /// Live reactive stream of tracks for a given MediaStore album ID.
  ///
  /// This is the lookup [AlbumDetailScreen] needs: it receives an [Album] whose
  /// `id` is the MediaStore `album_id`, so filtering on the `album` *title*
  /// column would return nothing.
  Stream<List<Track>> watchTracksByAlbumId(int albumId);

  /// Retrieves tracks associated with a genre.
  Future<List<Track>> getTracksByGenre(String genreId);

  /// Live reactive stream of tracks for a given genre.
  Stream<List<Track>> watchTracksByGenre(String genreId);

  /// Searches tracks matching [query] directly in SQLite by title, artist, album, or filename.
  Future<List<Track>> searchTracks(String query, {int limit = 50});

  /// Searches artists matching [query] directly in SQLite by artist name.
  Future<List<Artist>> searchArtists(String query, {int limit = 30});

  /// Searches albums matching [query] directly in SQLite by album title or artist name.
  Future<List<Album>> searchAlbums(String query, {int limit = 30});

  /// Searches genres matching [query] directly in SQLite by genre name.
  Future<List<Genre>> searchGenres(String query, {int limit = 30});

  /// Searches folders matching [query] directly in SQLite by directory path segments.
  Future<List<FolderNode>> searchFolders(String query, {int limit = 30});

  /// Unified fast search across all categories (songs, artists, albums, genres, folders).
  Future<SearchResults> searchAll(String query);

  /// Deletes a track from the library by its ID.
  Future<void> deleteTrack(String id);

  /// Clears all library tracks from the database.
  Future<void> clearAll();
}

/// Drift SQLite implementation of [MusicRepository].
class DriftMusicRepository implements MusicRepository {
  final AppDatabase _db;

  DriftMusicRepository(this._db);

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    await _db.transaction(() async {
      for (final track in tracks) {
        await _db.into(_db.tracks).insertOnConflictUpdate(
              TracksCompanion.insert(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                albumArtist: track.albumArtist,
                genre: track.genre,
                artistId: Value(track.artistId),
                year: Value(track.year),
                trackNumber: Value(track.trackNumber),
                discNumber: Value(track.discNumber),
                durationMs: Value(track.duration?.inMilliseconds),
                filePath: track.filePath,
                fileName: track.fileName,
                fileSize: Value(track.fileSize),
                mimeType: Value(track.mimeType),
                albumId: Value(track.albumId),
                isAvailable: Value(track.isAvailable),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
    });
  }

  @override
  Future<List<Track>> getAllTracks() async {
    final rows = await _selectAllQuery().get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Future<int> getTrackCount() async {
    final count = _db.tracks.id.count();

    final query = _db.selectOnly(_db.tracks)
      ..addColumns([count])
      ..where(_db.tracks.isAvailable.equals(true));

    final result = await query.getSingle();

    return result.read(count) ?? 0;
  }

  @override
  Future<List<Track>> getRecentlyAddedTracks({int limit = 10}) async {
    final query = _selectAllQuery()
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchAllTracks() {
    return _selectAllQuery().watch().map(
          (rows) => rows.map(_mapRowToTrack).toList(),
        );
  }

  @override
  Future<List<Artist>> getArtists() async {
    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.artist, count])
          ..where(_db.tracks.artist.isNotValue('') &
              _db.tracks.artist.isNotValue('Unknown Artist') &
              _db.tracks.artist.isNotNull())
          ..groupBy([_db.tracks.artist])
          ..orderBy([OrderingTerm.asc(_db.tracks.artist)]))
        .get();

    return rows.map((row) {
      final name = row.read(_db.tracks.artist)!;
      return Artist(
        id: _idFromName(name),
        name: name,
        trackCount: row.read(count) ?? 0,
      );
    }).toList();
  }

  @override
  Stream<List<Artist>> watchArtists() {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.artist, count])
      ..where(_db.tracks.artist.isNotValue('') &
          _db.tracks.artist.isNotValue('Unknown Artist') &
          _db.tracks.artist.isNotNull())
      ..groupBy([_db.tracks.artist])
      ..orderBy([OrderingTerm.asc(_db.tracks.artist)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final name = row.read(_db.tracks.artist)!;
        return Artist(
          id: _idFromName(name),
          name: name,
          trackCount: row.read(count) ?? 0,
        );
      }).toList();
    });
  }

  @override
  Future<List<Album>> getAlbums() async {
    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([
            _db.tracks.album,
            _db.tracks.albumArtist,
            _db.tracks.year,
            _db.tracks.albumId,
            count,
          ])
          ..where(_db.tracks.album.isNotValue('') &
              _db.tracks.album.isNotValue('Unknown Album') &
              _db.tracks.album.isNotNull())
          ..groupBy([
            _db.tracks.album,
            _db.tracks.albumArtist,
            _db.tracks.year,
            _db.tracks.albumId,
          ])
          ..orderBy([OrderingTerm.asc(_db.tracks.album)]))
        .get();

    return rows.map((row) {
      final title = row.read(_db.tracks.album)!;
      return Album(
        id: row.read(_db.tracks.albumId) ?? 0,
        title: title,
        albumArtist: row.read(_db.tracks.albumArtist) ?? '',
        artistId: null,
        year: row.read(_db.tracks.year),
        trackCount: row.read(count) ?? 0,
        artworkKey: row.read(_db.tracks.albumId)?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbums() {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([
        _db.tracks.album,
        _db.tracks.albumArtist,
        _db.tracks.year,
        _db.tracks.albumId,
        count,
      ])
      ..where(_db.tracks.album.isNotValue('') &
          _db.tracks.album.isNotValue('Unknown Album') &
          _db.tracks.album.isNotNull())
      ..groupBy([
        _db.tracks.album,
        _db.tracks.albumArtist,
        _db.tracks.year,
        _db.tracks.albumId,
      ])
      ..orderBy([OrderingTerm.asc(_db.tracks.album)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final title = row.read(_db.tracks.album)!;
        return Album(
          id: row.read(_db.tracks.albumId) ?? 0,
          title: title,
          albumArtist: row.read(_db.tracks.albumArtist) ?? '',
          artistId: null,
          year: row.read(_db.tracks.year),
          trackCount: row.read(count) ?? 0,
          artworkKey: row.read(_db.tracks.albumId)?.toString(),
        );
      }).toList();
    });
  }

  @override
  Future<List<Genre>> getGenres() async {
    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.genre, count])
          ..where(_db.tracks.genre.isNotValue('') &
              _db.tracks.genre.isNotValue('Unknown Genre') &
              _db.tracks.genre.isNotNull())
          ..groupBy([_db.tracks.genre])
          ..orderBy([OrderingTerm.asc(_db.tracks.genre)]))
        .get();

    return rows.map((row) {
      final name = row.read(_db.tracks.genre)!;
      return Genre(
        id: _idFromName(name),
        name: name,
        trackCount: row.read(count) ?? 0,
      );
    }).toList();
  }

  @override
  Stream<List<Genre>> watchGenres() {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.genre, count])
      ..where(_db.tracks.genre.isNotValue('') &
          _db.tracks.genre.isNotValue('Unknown Genre') &
          _db.tracks.genre.isNotNull())
      ..groupBy([_db.tracks.genre])
      ..orderBy([OrderingTerm.asc(_db.tracks.genre)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final name = row.read(_db.tracks.genre)!;
        return Genre(
          id: _idFromName(name),
          name: name,
          trackCount: row.read(count) ?? 0,
        );
      }).toList();
    });
  }

  @override
  Future<List<Track>> getTracksByArtist(String artistId) async {
    final query = _selectAllQuery()
      ..where((t) => t.artist.lower().equals(artistId.toLowerCase()) |
          t.albumArtist.lower().equals(artistId.toLowerCase()))
      ..orderBy([
        (t) => OrderingTerm.asc(t.album),
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchTracksByArtist(String artistId) {
    final query = _selectAllQuery()
      ..where((t) => t.artist.lower().equals(artistId.toLowerCase()) |
          t.albumArtist.lower().equals(artistId.toLowerCase()))
      ..orderBy([
        (t) => OrderingTerm.asc(t.album),
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    return query.watch().map((rows) => rows.map(_mapRowToTrack).toList());
  }

  @override
  Future<List<Track>> getTracksByArtistId(int artistId) async {
    final query = _selectAllQuery()
      ..where((t) => t.artistId.equals(artistId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.album),
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchTracksByArtistId(int artistId) {
    final query = _selectAllQuery()
      ..where((t) => t.artistId.equals(artistId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.album),
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    return query.watch().map((rows) => rows.map(_mapRowToTrack).toList());
  }

  @override
  Future<List<Album>> getAlbumsByArtist(String artistId) async {
    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId, count])
          ..where((_db.tracks.album.isNotValue('') &
                  _db.tracks.album.isNotValue('Unknown Album') &
                  _db.tracks.album.isNotNull()) &
              (_db.tracks.artist.lower().equals(artistId.toLowerCase()) |
                  _db.tracks.albumArtist.lower().equals(artistId.toLowerCase())))
          ..groupBy([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId])
          ..orderBy([OrderingTerm.asc(_db.tracks.album)]))
        .get();

    return rows.map((row) {
      final title = row.read(_db.tracks.album)!;
      return Album(
        id: row.read(_db.tracks.albumId) ?? 0,
        title: title,
        albumArtist: row.read(_db.tracks.albumArtist) ?? '',
        artistId: null,
        year: row.read(_db.tracks.year),
        trackCount: row.read(count) ?? 0,
        artworkKey: row.read(_db.tracks.albumId)?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbumsByArtist(String artistId) {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId, count])
      ..where((_db.tracks.album.isNotValue('') &
              _db.tracks.album.isNotValue('Unknown Album') &
              _db.tracks.album.isNotNull()) &
          (_db.tracks.artist.lower().equals(artistId.toLowerCase()) |
              _db.tracks.albumArtist.lower().equals(artistId.toLowerCase())))
      ..groupBy([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId])
      ..orderBy([OrderingTerm.asc(_db.tracks.album)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final title = row.read(_db.tracks.album)!;
        return Album(
          id: row.read(_db.tracks.albumId) ?? 0,
          title: title,
          albumArtist: row.read(_db.tracks.albumArtist) ?? '',
          artistId: null,
          year: row.read(_db.tracks.year),
          trackCount: row.read(count) ?? 0,
          artworkKey: row.read(_db.tracks.albumId)?.toString(),
        );
      }).toList();
    });
  }

  @override
  Future<List<Album>> getAlbumsByArtistId(int artistId) async {
    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId, count])
          ..where((_db.tracks.album.isNotValue('') &
                  _db.tracks.album.isNotValue('Unknown Album') &
                  _db.tracks.album.isNotNull()) &
              _db.tracks.artistId.equals(artistId))
          ..groupBy([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId])
          ..orderBy([OrderingTerm.asc(_db.tracks.album)]))
        .get();

    return rows.map((row) {
      final title = row.read(_db.tracks.album)!;
      return Album(
        id: row.read(_db.tracks.albumId) ?? 0,
        title: title,
        albumArtist: row.read(_db.tracks.albumArtist) ?? '',
        artistId: artistId,
        year: row.read(_db.tracks.year),
        trackCount: row.read(count) ?? 0,
        artworkKey: row.read(_db.tracks.albumId)?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbumsByArtistId(int artistId) {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId, count])
      ..where((_db.tracks.album.isNotValue('') &
              _db.tracks.album.isNotValue('Unknown Album') &
              _db.tracks.album.isNotNull()) &
          _db.tracks.artistId.equals(artistId))
      ..groupBy([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId])
      ..orderBy([OrderingTerm.asc(_db.tracks.album)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final title = row.read(_db.tracks.album)!;
        return Album(
          id: row.read(_db.tracks.albumId) ?? 0,
          title: title,
          albumArtist: row.read(_db.tracks.albumArtist) ?? '',
          artistId: artistId,
          year: row.read(_db.tracks.year),
          trackCount: row.read(count) ?? 0,
          artworkKey: row.read(_db.tracks.albumId)?.toString(),
        );
      }).toList();
    });
  }

  @override
  Future<List<Track>> getTracksByAlbum(String albumId) async {
    final query = _selectAllQuery()
      ..where((t) => t.album.lower().equals(albumId.toLowerCase()))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchTracksByAlbum(String albumId) {
    final query = _selectAllQuery()
      ..where((t) => t.album.lower().equals(albumId.toLowerCase()))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    return query.watch().map((rows) => rows.map(_mapRowToTrack).toList());
  }

  @override
  Future<List<Track>> getTracksByAlbumId(int albumId) async {
    final query = _selectAllQuery()
      ..where((t) => t.albumId.equals(albumId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchTracksByAlbumId(int albumId) {
    final query = _selectAllQuery()
      ..where((t) => t.albumId.equals(albumId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    return query.watch().map((rows) => rows.map(_mapRowToTrack).toList());
  }

  @override
  Future<List<Track>> getTracksByGenre(String genreId) async {
    final query = _selectAllQuery()
      ..where((t) => t.genre.lower().equals(genreId.toLowerCase()))
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    final rows = await query.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Stream<List<Track>> watchTracksByGenre(String genreId) {
    final query = _selectAllQuery()
      ..where((t) => t.genre.lower().equals(genreId.toLowerCase()))
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    return query.watch().map((rows) => rows.map(_mapRowToTrack).toList());
  }

  @override
  Future<List<Track>> searchTracks(String query, {int limit = 50}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final searchPattern = '%$trimmed%';

    final q = (_selectAllQuery()
          ..where((t) =>
              t.title.like(searchPattern) |
              t.artist.like(searchPattern) |
              t.album.like(searchPattern) |
              t.fileName.like(searchPattern))
          ..orderBy([(t) => OrderingTerm.asc(t.title)])
          ..limit(limit));

    final rows = await q.get();
    return rows.map(_mapRowToTrack).toList();
  }

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final searchPattern = '%$trimmed%';

    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.artist, count])
          ..where(_db.tracks.artist.like(searchPattern))
          ..groupBy([_db.tracks.artist])
          ..orderBy([OrderingTerm.asc(_db.tracks.artist)])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final name = row.read(_db.tracks.artist)!;
      return Artist(
        id: _idFromName(name),
        name: name,
        trackCount: row.read(count) ?? 0,
      );
    }).toList();
  }

  @override
  Future<List<Album>> searchAlbums(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final searchPattern = '%$trimmed%';

    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId, count])
          ..where(_db.tracks.album.like(searchPattern) |
              _db.tracks.artist.like(searchPattern))
          ..groupBy([_db.tracks.album, _db.tracks.albumArtist, _db.tracks.year, _db.tracks.albumId])
          ..orderBy([OrderingTerm.asc(_db.tracks.album)])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final title = row.read(_db.tracks.album)!;
      return Album(
        id: row.read(_db.tracks.albumId) ?? 0,
        title: title,
        albumArtist: row.read(_db.tracks.albumArtist) ?? '',
        artistId: null,
        year: row.read(_db.tracks.year),
        trackCount: row.read(count) ?? 0,
        artworkKey: row.read(_db.tracks.albumId)?.toString(),
      );
    }).toList();
  }

  @override
  Future<List<Genre>> searchGenres(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final searchPattern = '%$trimmed%';

    final count = _db.tracks.id.count();
    final rows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.genre, count])
          ..where(_db.tracks.genre.like(searchPattern))
          ..groupBy([_db.tracks.genre])
          ..orderBy([OrderingTerm.asc(_db.tracks.genre)])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final name = row.read(_db.tracks.genre)!;
      return Genre(
        id: _idFromName(name),
        name: name,
        trackCount: row.read(count) ?? 0,
      );
    }).toList();
  }

  @override
  Future<List<FolderNode>> searchFolders(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final searchPattern = '%$trimmed%';

    final rows = await (_db.selectOnly(_db.tracks, distinct: true)
          ..addColumns([_db.tracks.filePath])
          ..where(_db.tracks.filePath.like(searchPattern)))
        .get();

    final matchingPaths =
        rows.map((r) => r.read(_db.tracks.filePath)).whereType<String>();

    final queryLower = trimmed.toLowerCase();
    final folderService = FolderService();
    final Set<String> matchedFolderPaths = {};

    for (final filePath in matchingPaths) {
      final dir = folderService.directoryOf(filePath);
      if (dir.isNotEmpty &&
          (dir.toLowerCase().contains(queryLower) ||
              folderService.getName(dir).toLowerCase().contains(queryLower))) {
        matchedFolderPaths.add(dir);
      }
    }

    final results = [
      for (final folderPath in matchedFolderPaths.take(limit))
        FolderNode(
          name: folderService.getName(folderPath),
          path: folderPath,
          isFolder: true,
        ),
    ];

    results.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  @override
  Future<SearchResults> searchAll(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SearchResults();
    }

    final results = await Future.wait([
      searchTracks(trimmed),
      searchArtists(trimmed),
      searchAlbums(trimmed),
      searchGenres(trimmed),
      searchFolders(trimmed),
    ]);

    return SearchResults(
      query: trimmed,
      tracks: results[0] as List<Track>,
      artists: results[1] as List<Artist>,
      albums: results[2] as List<Album>,
      genres: results[3] as List<Genre>,
      folders: results[4] as List<FolderNode>,
    );
  }

  @override
  Future<void> deleteTrack(String id) async {
    await (_db.delete(_db.tracks)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<Set<String>> getAllTrackIds() async {
    final rows = await _db.select(_db.tracks).get();
    return rows.map((row) => row.id).toSet();
  }

  @override
  Future<int> deleteTracksByIds(Set<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }

    return _db.transaction(() async {
      var deleted = 0;

      for (final id in ids) {
        deleted += await (_db.delete(_db.tracks)
              ..where((track) => track.id.equals(id)))
            .go();
      }

      return deleted;
    });
  }

  @override
  Future<void> purgeTrackRelations(Set<String> trackIds) async {
    if (trackIds.isEmpty) return;

    await _db.transaction(() async {
      // Favorites and per-song play history are keyed by track id.
      await (_db.delete(_db.favorites)
            ..where((r) => r.trackId.isIn(trackIds)))
          .go();
      await (_db.delete(_db.playHistory)
            ..where((r) => r.trackId.isIn(trackIds)))
          .go();

      // Playlist membership: drop the stale links, then compact the positions
      // of the surviving tracks in each affected playlist so `position` is
      // always contiguous (spec 24 — no partially updated playlists).
      final staleLinks = await (_db.select(_db.playlistTracks)
            ..where((r) => r.trackId.isIn(trackIds)))
          .get();
      if (staleLinks.isEmpty) return;
      final affectedPlaylists = {for (final r in staleLinks) r.playlistId};
      await (_db.delete(_db.playlistTracks)
            ..where((r) => r.trackId.isIn(trackIds)))
          .go();

      for (final playlistId in affectedPlaylists) {
        final remaining = await (_db.select(_db.playlistTracks)
              ..where((r) => r.playlistId.equals(playlistId))
              ..orderBy([(r) => OrderingTerm.asc(r.position)]))
            .get();
        await _db.batch((batch) {
          for (var i = 0; i < remaining.length; i++) {
            batch.update(
              _db.playlistTracks,
              PlaylistTracksCompanion(position: Value(i)),
              where: (r) =>
                  r.playlistId.equals(playlistId) &
                  r.trackId.equals(remaining[i].trackId),
            );
          }
        });
      }
    });
  }

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.tracks).go();
  }

  SimpleSelectStatement<$TracksTable, TrackEntry> _selectAllQuery(
      {bool onlyAvailable = true}) {
    final stmt = _db.select(_db.tracks);
    if (onlyAvailable) {
      stmt.where((t) => t.isAvailable.equals(true));
    }
    stmt.orderBy([(t) => OrderingTerm.asc(t.title)]);
    return stmt;
  }

  Track _mapRowToTrack(TrackEntry row) {
    return Track(
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album,
      albumArtist: row.albumArtist,
      genre: row.genre,
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
      albumArtUri: row.albumId?.toString(),
      isAvailable: row.isAvailable,
    );
  }

  String _idFromName(String name) {
    return name.trim().toLowerCase();
  }
}

/// Mock implementation of [MusicRepository] for tests.
class MockMusicRepository implements MusicRepository {
  final List<Track> _tracks = [];

  MockMusicRepository([List<Track>? initialTracks]) {
    if (initialTracks != null) {
      _tracks.addAll(initialTracks);
    }
  }

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    for (final track in tracks) {
      final index = _tracks.indexWhere((t) => t.id == track.id);
      if (index >= 0) {
        _tracks[index] = track.copyWith(isAvailable: true);
      } else {
        _tracks.add(track.copyWith(isAvailable: true));
      }
    }
  }

  @override
  Future<List<Track>> getAllTracks() async =>
      List.unmodifiable(_availableTracks());

  @override
  Future<int> getTrackCount() async => _availableTracks().length;

  @override
  Future<List<Track>> getRecentlyAddedTracks({int limit = 10}) async {
    final available = _availableTracks();
    return available.reversed.take(limit).toList();
  }

  List<Track> _availableTracks() =>
      _tracks.where((t) => t.isAvailable).toList();

  @override
  Stream<List<Track>> watchAllTracks() =>
      Stream.value(List.unmodifiable(_availableTracks()));

  @override
  Future<List<Artist>> getArtists() async {
    final artistNames = _tracks.map((t) => t.artist).toSet();
    return artistNames.map((name) {
      final count = _tracks.where((t) => t.artist == name).length;
      return Artist(
        id: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        trackCount: count,
      );
    }).toList();
  }

  @override
  Stream<List<Artist>> watchArtists() async* {
    yield await getArtists();
  }

  @override
  Future<List<Album>> getAlbums() async {
    final albumTitles = _tracks.map((t) => t.album).whereType<String>().toSet();
    return albumTitles.map((title) {
      final matching = _tracks.where((t) => t.album == title).toList();
      return Album(
        id: matching.first.albumId ?? 0,
        title: title,
        albumArtist: matching.first.albumArtist.isNotEmpty
            ? matching.first.albumArtist
            : matching.first.artist,
        artistId: matching.first.artistId,
        year: matching.first.year,
        trackCount: matching.length,
        artworkKey: matching.first.albumId?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbums() async* {
    yield await getAlbums();
  }

  @override
  Future<List<Genre>> getGenres() async {
    final genreNames = _tracks.map((t) => t.genre).whereType<String>().toSet();
    return genreNames.map((name) {
      final count = _tracks.where((t) => t.genre == name).length;
      return Genre(
        id: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        trackCount: count,
      );
    }).toList();
  }

  @override
  Stream<List<Genre>> watchGenres() async* {
    yield await getGenres();
  }

  @override
  Future<List<Track>> getTracksByArtist(String artistId) async {
    return _tracks.where((t) =>
        t.artist.toLowerCase().replaceAll(' ', '_') == artistId ||
        t.artist.toLowerCase() == artistId.toLowerCase()).toList();
  }

  @override
  Stream<List<Track>> watchTracksByArtist(String artistId) async* {
    yield await getTracksByArtist(artistId);
  }

  @override
  Future<List<Track>> getTracksByArtistId(int artistId) async {
    return _tracks.where((t) => t.artistId == artistId).toList();
  }

  @override
  Stream<List<Track>> watchTracksByArtistId(int artistId) async* {
    yield await getTracksByArtistId(artistId);
  }

  @override
  Future<List<Album>> getAlbumsByArtist(String artistId) async {
    final matchingTracks = _tracks.where((t) =>
        t.artist.toLowerCase().replaceAll(' ', '_') == artistId ||
        t.artist.toLowerCase() == artistId.toLowerCase());
    final albumTitles = matchingTracks.map((t) => t.album).whereType<String>().toSet();
    return albumTitles.map((title) {
      final matching = matchingTracks.where((t) => t.album == title).toList();
      return Album(
        id: matching.first.albumId ?? 0,
        title: title,
        albumArtist: matching.first.albumArtist.isNotEmpty
            ? matching.first.albumArtist
            : matching.first.artist,
        artistId: matching.first.artistId,
        year: matching.first.year,
        trackCount: matching.length,
        artworkKey: matching.first.albumId?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbumsByArtist(String artistId) async* {
    yield await getAlbumsByArtist(artistId);
  }

  @override
  Future<List<Album>> getAlbumsByArtistId(int artistId) async {
    final matchingTracks = _tracks.where((t) => t.artistId == artistId);
    final albumTitles = matchingTracks.map((t) => t.album).whereType<String>().toSet();
    return albumTitles.map((title) {
      final matching = matchingTracks.where((t) => t.album == title).toList();
      return Album(
        id: matching.first.albumId ?? 0,
        title: title,
        albumArtist: matching.first.albumArtist.isNotEmpty
            ? matching.first.albumArtist
            : matching.first.artist,
        artistId: matching.first.artistId,
        year: matching.first.year,
        trackCount: matching.length,
        artworkKey: matching.first.albumId?.toString(),
      );
    }).toList();
  }

  @override
  Stream<List<Album>> watchAlbumsByArtistId(int artistId) async* {
    yield await getAlbumsByArtistId(artistId);
  }

  @override
  Future<List<Track>> getTracksByAlbum(String albumId) async {
    final list = _tracks.where((t) =>
        t.album.toLowerCase().replaceAll(' ', '_') == albumId ||
        t.album.toLowerCase() == albumId.toLowerCase()).toList();

    list.sort((a, b) {
      final discA = a.discNumber ?? 1;
      final discB = b.discNumber ?? 1;
      final discCompare = discA.compareTo(discB);
      if (discCompare != 0) return discCompare;

      final trackA = a.trackNumber ?? 0;
      final trackB = b.trackNumber ?? 0;
      final trackCompare = trackA.compareTo(trackB);
      if (trackCompare != 0) return trackCompare;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return list;
  }

  @override
  Stream<List<Track>> watchTracksByAlbum(String albumId) async* {
    yield await getTracksByAlbum(albumId);
  }

  @override
  Future<List<Track>> getTracksByAlbumId(int albumId) async {
    return _tracks.where((t) => t.albumId == albumId).toList();
  }

  @override
  Stream<List<Track>> watchTracksByAlbumId(int albumId) async* {
    yield await getTracksByAlbumId(albumId);
  }

  @override
  Future<List<Track>> getTracksByGenre(String genreId) async {
    return _tracks.where((t) =>
        t.genre.toLowerCase().replaceAll(' ', '_') == genreId ||
        t.genre.toLowerCase() == genreId.toLowerCase()).toList();
  }

  @override
  Stream<List<Track>> watchTracksByGenre(String genreId) async* {
    yield await getTracksByGenre(genreId);
  }

  @override
  Future<List<Track>> searchTracks(String query, {int limit = 50}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _tracks.where((t) =>
        t.title.toLowerCase().contains(q) ||
        t.artist.toLowerCase().contains(q) ||
        t.album.toLowerCase().contains(q) ||
        t.fileName.toLowerCase().contains(q)).take(limit).toList();
  }

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final allArtists = await getArtists();
    return allArtists.where((a) => a.name.toLowerCase().contains(q)).take(limit).toList();
  }

  @override
  Future<List<Album>> searchAlbums(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final allAlbums = await getAlbums();
    return allAlbums.where((a) =>
        a.title.toLowerCase().contains(q) ||
        a.albumArtist.toLowerCase().contains(q)).take(limit).toList();
  }

  @override
  Future<List<Genre>> searchGenres(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final allGenres = await getGenres();
    return allGenres.where((g) => g.name.toLowerCase().contains(q)).take(limit).toList();
  }

  @override
  Future<List<FolderNode>> searchFolders(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final folderService = FolderService();
    final tracksByDir = folderService.groupTracksByDirectory(_tracks);
    final results = <FolderNode>[];

    for (final entry in tracksByDir.entries) {
      final folderName = folderService.getName(entry.key);
      if (entry.key.toLowerCase().contains(q) || folderName.toLowerCase().contains(q)) {
        results.add(FolderNode(
          path: entry.key,
          name: folderName,
          isFolder: true,
        ));
      }
    }

    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results.take(limit).toList();
  }

  @override
  Future<SearchResults> searchAll(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const SearchResults();
    final tracks = await searchTracks(q);
    final artists = await searchArtists(q);
    final albums = await searchAlbums(q);
    final genres = await searchGenres(q);
    final folders = await searchFolders(q);

    return SearchResults(
      query: q,
      tracks: tracks,
      artists: artists,
      albums: albums,
      genres: genres,
      folders: folders,
    );
  }

  @override
  Future<void> deleteTrack(String id) async {
    _tracks.removeWhere((t) => t.id == id);
  }

  @override
  Future<Set<String>> getAllTrackIds() async {
    return _tracks.map((t) => t.id).toSet();
  }

  @override
  Future<int> deleteTracksByIds(Set<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }

    final before = _tracks.length;
    _tracks.removeWhere((t) => ids.contains(t.id));
    return before - _tracks.length;
  }

  @override
  Future<void> purgeTrackRelations(Set<String> trackIds) async {
    // The mock only models the track table; collection relationships are
    // persisted by Drift-backed services, so nothing to do here.
  }

  @override
  Future<void> clearAll() async {
    _tracks.clear();
  }
}

/// Provider for the singleton [AppDatabase].
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

/// Provider for the singleton [MusicRepository].
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftMusicRepository(db);
});

/// Provider for the singleton [ArtistRepository].
final artistRepositoryProvider = Provider<ArtistRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ArtistRepository(db);
});

/// Provider for the singleton [AlbumRepository].
final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AlbumRepository(db);
});

/// Reactive stream provider for all tracks in the library.
final libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(musicRepositoryProvider).watchAllTracks();
});

/// Provider for the most recently added tracks, newest first.
final recentlyAddedTracksProvider =
    FutureProvider<List<Track>>((ref) async {
  return ref.watch(musicRepositoryProvider).getRecentlyAddedTracks();
});

/// Reactive stream provider for all artists in the library.
final libraryArtistsProvider = StreamProvider<List<Artist>>((ref) {
  return ref.watch(artistRepositoryProvider).watchArtists();
});

/// Reactive stream provider for all albums in the library.
final libraryAlbumsProvider = StreamProvider<List<Album>>((ref) {
  return ref.watch(musicRepositoryProvider).watchAlbums();
});

/// Reactive stream provider for all genres in the library.
final libraryGenresProvider = StreamProvider<List<Genre>>((ref) {
  return ref.watch(musicRepositoryProvider).watchGenres();
});

/// Reactive stream provider for tracks belonging to a specific artist.
final artistTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, artistId) {
  return ref.watch(musicRepositoryProvider).watchTracksByArtist(artistId);
});

/// Reactive stream provider for tracks belonging to a specific MediaStore artist ID.
final artistTracksByIdProvider =
    StreamProvider.family<List<Track>, int>((ref, artistId) {
  return ref.watch(musicRepositoryProvider).watchTracksByArtistId(artistId);
});

/// Reactive stream provider for albums belonging to a specific artist.
final artistAlbumsProvider =
    StreamProvider.family<List<Album>, String>((ref, artistId) {
  return ref.watch(musicRepositoryProvider).watchAlbumsByArtist(artistId);
});

/// Reactive stream provider for albums belonging to a specific MediaStore artist ID.
final artistAlbumsByIdProvider =
    StreamProvider.family<List<Album>, int>((ref, artistId) {
  return ref.watch(musicRepositoryProvider).watchAlbumsByArtistId(artistId);
});

/// Reactive stream provider for tracks belonging to a specific album, matched by
/// album **title**. Prefer [albumTracksByIdProvider] for MediaStore album ids.
final albumTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, albumId) {
  return ref.watch(musicRepositoryProvider).watchTracksByAlbum(albumId);
});

/// Reactive stream provider for tracks belonging to a specific MediaStore album
/// ID. This is what [AlbumDetailScreen] uses: the `Album` it is given carries the
/// MediaStore `album_id` as its `id`, so a title lookup matches nothing.
final albumTracksByIdProvider =
    StreamProvider.family<List<Track>, int>((ref, albumId) {
  return ref.watch(musicRepositoryProvider).watchTracksByAlbumId(albumId);
});

/// Reactive stream provider for tracks belonging to a specific genre.
final genreTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, genreId) {
  return ref.watch(musicRepositoryProvider).watchTracksByGenre(genreId);
});

/// Provider to execute SQLite search across all library categories.
final searchResultsProvider =
    FutureProvider.family<SearchResults, String>((ref, query) {
  return ref.watch(musicRepositoryProvider).searchAll(query);
});
