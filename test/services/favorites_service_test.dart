import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/database/app_database.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/services/favorites/favorites_service.dart';

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
    duration: null,
    filePath: '/Music/$id.mp3',
    fileName: '$id.mp3',
    fileSize: null,
    mimeType: null,
    isAvailable: true,
  );
}

void main() {
  group('FavoritesService', () {
    test('addFavorite stores a track and reflects it in fast lookups', () async {
      final service = FavoritesService(null);
      final track = buildTrack('1', 'A');
      await service.addFavorite(track);

      expect(service.count, 1);
      expect(service.isFavorite(track), isTrue);
      expect(service.isFavoriteId('1'), isTrue);
      expect(service.favoriteIds, contains('1'));
      expect(service.entries.single.track.id, '1');
    });

    test('addFavorite is idempotent (no duplicates)', () async {
      final service = FavoritesService(null);
      final track = buildTrack('1', 'A');
      await service.addFavorite(track);
      await service.addFavorite(track);
      await service.addFavorite(track);

      expect(service.count, 1);
      expect(service.entries.length, 1);
    });

    test('toggleFavorite adds then removes a track', () async {
      final service = FavoritesService(null);
      final track = buildTrack('1', 'A');

      final added = await service.toggleFavorite(track);
      expect(added, isTrue);
      expect(service.isFavorite(track), isTrue);

      final removed = await service.toggleFavorite(track);
      expect(removed, isFalse);
      expect(service.isFavorite(track), isFalse);
      expect(service.count, 0);
    });

    test('removeFavorite and removeFavoriteId drop the track', () async {
      final service = FavoritesService(null);
      final track = buildTrack('1', 'A');
      await service.addFavorite(track);

      await service.removeFavorite(track);
      expect(service.count, 0);

      await service.addFavorite(track);
      await service.removeFavoriteId('1');
      expect(service.count, 0);
    });

    test('entries are most-recently-favorited first by default', () async {
      final service = FavoritesService(null);
      await service.addFavorite(buildTrack('1', 'A'));
      await service.addFavorite(buildTrack('2', 'B'));
      await service.addFavorite(buildTrack('3', 'C'));

      expect(
        service.entries.map((e) => e.track.id).toList(),
        ['3', '2', '1'],
      );
    });

    test('emits updates through the stream', () async {
      final service = FavoritesService(null);
      final seen = <List<String>>[];
      service.entriesStream.listen(
        (e) => seen.add(e.map((x) => x.track.id).toList()),
      );

      await service.addFavorite(buildTrack('1', 'A'));
      await service.addFavorite(buildTrack('2', 'B'));
      // Wait for the remove to be reflected on the stream.
      final afterRemove = service.entriesStream
          .firstWhere((e) => !e.any((x) => x.track.id == '1'))
          .then((e) => e.map((x) => x.track.id).toList());
      await service.removeFavoriteId('1');
      final finalState = await afterRemove;

      expect(finalState, ['2']);
      expect(service.count, 1);
      expect(seen.last, ['2']);
    });

    test('clearFavorites removes everything', () async {
      final service = FavoritesService(null);
      await service.addFavorite(buildTrack('1', 'A'));
      await service.addFavorite(buildTrack('2', 'B'));
      await service.clearFavorites();

      expect(service.count, 0);
      expect(service.entries, isEmpty);
    });

    test('favoriteTracksAvailable omits unavailable tracks', () async {
      final service = FavoritesService(null);
      await service.addFavorite(buildTrack('a', 'A'));
      await service.addFavorite(buildTrack('b', 'B'));

      // b is no longer present in the library.
      await service.pruneMissingTracks({'a'});

      expect(service.favoriteTracks.map((t) => t.id).toList(), ['a']);
    });

    test('sort by artist groups favorites by artist name', () async {
      final service = FavoritesService(null);
      service.sort = FavoriteSort.artist;
      await service.addFavorite(buildTrack('1', 'Zed', artist: 'Beta'));
      await service.addFavorite(buildTrack('2', 'Alpha', artist: 'Alpha'));

      expect(
        service.entries.map((e) => e.track.id).toList(),
        ['2', '1'],
      );
    });

    test('sort by title orders favorites by track title', () async {
      final service = FavoritesService(null);
      service.sort = FavoriteSort.title;
      await service.addFavorite(buildTrack('1', 'Zebra'));
      await service.addFavorite(buildTrack('2', 'Apple'));
      await service.addFavorite(buildTrack('3', 'Mango'));

      expect(
        service.entries.map((e) => e.track.id).toList(),
        ['2', '3', '1'],
      );
    });

    test('pruneMissingTracks lazily removes favorites whose file is gone',
        () async {
      final service = FavoritesService(null);
      await service.addFavorite(buildTrack('1', 'A'));
      await service.addFavorite(buildTrack('2', 'B'));
      await service.addFavorite(buildTrack('3', 'C'));

      await service.pruneMissingTracks({'1', '3'});

      expect(service.favoriteIds, {'1', '3'});
      expect(service.entries.map((e) => e.track.id).toList(), ['3', '1']);
    });

    test('favorites persist across restarts (Drift-backed)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final service = FavoritesService(db);

      await service.addFavorite(buildTrack('a', 'A'));
      await service.addFavorite(buildTrack('b', 'B'));

      // A fresh service reading the same DB restores the favorites.
      final restored = FavoritesService(db);
      await restored.ready;
      expect(restored.favoriteIds, {'a', 'b'});
      expect(restored.isFavoriteId('a'), isTrue);
    });
  });
}
