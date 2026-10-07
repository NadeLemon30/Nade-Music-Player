import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/database/app_database.dart';
import 'package:test_app/data/repositories/album_repository.dart';
import 'package:test_app/data/repositories/artist_repository.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/data/repositories/playlist_repository.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/services/playlists/playlist_service.dart';

Track buildTrack(String id, String title, {String artist = 'Artist'}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: '',
    albumArtist: '',
    genre: '',
    year: null,
    trackNumber: null,
    discNumber: null,
    duration: const Duration(minutes: 3),
    filePath: '/Music/$id.mp3',
    fileName: '$id.mp3',
    fileSize: 1000,
    mimeType: 'audio/mpeg',
    isAsset: false,
    albumArtUri: null,
  );
}

void main() {
  group('DriftMusicRepository.purgeTrackRelations', () {
    test(
        'removes a deleted track from favorites, play history, and playlists '
        'while keeping the playlists themselves (spec 23/24)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final a = buildTrack('a', 'Song A');
      final b = buildTrack('b', 'Song B');
      final c = buildTrack('c', 'Song C');
      final d = buildTrack('d', 'Song D');

      final musicRepo = DriftMusicRepository(db);
      await musicRepo.saveTracks([a, b, c, d]);

      final favorites = FavoritesService(db);
      final history = PlayHistoryService(db);
      final playlists = PlaylistService(PlaylistRepository(db));
      final workout = await playlists.createPlaylist('Workout');

      await favorites.addFavorite(a);
      await favorites.addFavorite(b);
      await history.record(a);
      await history.record(b);
      await history.record(c);
      await playlists.addTracksToPlaylist(workout.id, [a, b, c, d]);

      // The scan no longer sees track B.
      await musicRepo.deleteTracksByIds({'b'});
      await musicRepo.purgeTrackRelations({'b'});

      // DB-level: the playlist survives, B is gone, positions stay contiguous.
      expect(await PlaylistRepository(db).getTrackIds(workout.id),
          ['a', 'c', 'd']);

      // Mirror sync — the same calls LibraryController/LibraryScanController
      // make after synchronize() so the in-memory services match the DB.
      final available = await musicRepo.getAllTrackIds();
      await favorites.pruneMissingTracks(available);
      await history.pruneMissingTracks(available);
      await playlists.pruneMissingTracks(available);

      expect(favorites.favoriteIds, {'a'});
      expect(
        history.entries.map((e) => e.track.id).toSet(),
        {'a', 'c'},
      );
      expect(playlists.count, 1);
      expect(
        playlists
            .tracksForPlaylist(workout.id)
            .map((t) => t.id)
            .toList(),
        ['a', 'c', 'd'],
      );
    });

    test('is a no-op for an empty set (spec 23)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final musicRepo = DriftMusicRepository(db);
      await musicRepo.saveTracks([buildTrack('a', 'Song A')]);
      final favorites = FavoritesService(db);
      await favorites.addFavorite(buildTrack('a', 'Song A'));

      await musicRepo.purgeTrackRelations(const {});

      expect(favorites.favoriteIds, {'a'});
    });
  });

  group('DriftMusicRepository album/artist id lookups', () {
    /// A track tagged with real MediaStore ids, so the album/artist link paths
    /// are exercised the way the scanner populates them.
    Track taggedTrack(
      String id,
      String title, {
      required String artist,
      required String album,
      int artistId = 7,
      int albumId = 42,
      int? discNumber = 1,
      int? trackNumber = 1,
    }) {
      return Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        albumArtist: artist,
        genre: '',
        artistId: artistId,
        year: 2003,
        trackNumber: trackNumber,
        discNumber: discNumber,
        duration: const Duration(minutes: 3),
        filePath: '/Music/$id.mp3',
        fileName: '$id.mp3',
        fileSize: 1000,
        mimeType: 'audio/mpeg',
        isAsset: false,
        albumArtUri: null,
        albumId: albumId,
      );
    }

    test(
        'saveTracks persists artistId so artists survive a scan + sync '
        '(the artists page was empty)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final musicRepo = DriftMusicRepository(db);
      await musicRepo.saveTracks([
        taggedTrack('s1', 'One', artist: 'Linkin Park', album: 'Hybrid Theory'),
        taggedTrack('s2', 'Two', artist: 'Linkin Park', album: 'Hybrid Theory'),
      ]);

      // The row must keep the MediaStore ids, otherwise the normalized
      // `artists`/`albums` tables are rebuilt empty.
      final rows = await db.select(db.tracks).get();
      expect(rows.map((r) => r.artistId), everyElement(7));
      expect(rows.map((r) => r.albumId), everyElement(42));

      final artistRepo = ArtistRepository(db);
      await artistRepo.synchronizeArtists();
      final artists = await artistRepo.getAllArtists();
      expect(artists, hasLength(1));
      expect(artists.single.name, 'Linkin Park');
      // Counts come from tracks.artistId, so a dropped column shows up as 0.
      expect(artists.single.trackCount, 2);

      final albumRepo = AlbumRepository(db);
      await albumRepo.synchronizeAlbums();
      final albums = await albumRepo.getAllAlbums();
      expect(albums, hasLength(1));
      expect(albums.single.id, 42);
      expect(albums.single.title, 'Hybrid Theory');
    });

    test(
        'watchTracksByAlbumId returns an album\'s tracks when given the '
        'MediaStore album id (album detail showed no songs)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final musicRepo = DriftMusicRepository(db);
      await musicRepo.saveTracks([
        taggedTrack('s1', 'One', artist: 'Linkin Park', album: 'Hybrid Theory',
            discNumber: 1, trackNumber: 1),
        taggedTrack('s2', 'Two', artist: 'Linkin Park', album: 'Hybrid Theory',
            discNumber: 1, trackNumber: 2),
        taggedTrack('s3', 'Other', artist: 'Adele', album: '19', albumId: 99),
      ]);

      final tracks = await musicRepo.watchTracksByAlbumId(42).first;
      expect(tracks.map((t) => t.id).toSet(), {'s1', 's2'});
      // Ordered by disc + track number.
      expect(tracks.map((t) => t.title).toList(), ['One', 'Two']);

      // A different album id must not leak tracks.
      final other = await musicRepo.watchTracksByAlbumId(99).first;
      expect(other.map((t) => t.id).toList(), ['s3']);

      // An unknown id yields nothing rather than everything.
      expect(await musicRepo.watchTracksByAlbumId(1234).first, isEmpty);

      // Documents the bug this replaced: the *title* lookup cannot resolve the
      // album id the UI actually holds.
      expect(await musicRepo.watchTracksByAlbum('42').first, isEmpty);
    });

    test('watchTracksByArtistId resolves an artist\'s songs by MediaStore id',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final musicRepo = DriftMusicRepository(db);
      await musicRepo.saveTracks([
        taggedTrack('s1', 'One', artist: 'Linkin Park', album: 'Hybrid Theory'),
        taggedTrack('s2', 'Other', artist: 'Adele', album: '19', artistId: 8),
      ]);

      final tracks = await musicRepo.watchTracksByArtistId(7).first;
      expect(tracks.map((t) => t.id).toList(), ['s1']);
      expect(await musicRepo.watchTracksByArtistId(8).first, hasLength(1));
      expect(await musicRepo.watchTracksByArtistId(999).first, isEmpty);
    });
  });
}