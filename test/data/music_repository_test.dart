import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/database/app_database.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/models/track.dart';

void main() {
  late AppDatabase db;
  late DriftMusicRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftMusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DriftMusicRepository', () {
    const track1 = Track(
      id: '1',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: 'Linkin Park',
      genre: 'Alternative Rock',
      year: 2003,
      trackNumber: 13,
      discNumber: 1,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/storage/emulated/0/Music/01 - Numb.mp3',
      fileName: '01 - Numb.mp3',
      fileSize: 7458921,
      mimeType: 'audio/mpeg',
    );

    const track2 = Track(
      id: '2',
      title: 'Faint',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: 'Linkin Park',
      genre: 'Alternative Rock',
      year: 2003,
      trackNumber: 7,
      discNumber: 1,
      duration: Duration(minutes: 2, seconds: 42),
      filePath: '/storage/emulated/0/Music/02 - Faint.mp3',
      fileName: '02 - Faint.mp3',
      fileSize: 6458921,
      mimeType: 'audio/mpeg',
    );

    const track3 = Track(
      id: '3',
      title: 'Get Lucky',
      artist: 'Daft Punk',
      album: 'Random Access Memories',
      albumArtist: 'Daft Punk',
      genre: 'Disco / Funk',
      year: 2013,
      trackNumber: 8,
      discNumber: 1,
      duration: Duration(minutes: 6, seconds: 9),
      filePath: '/storage/emulated/0/Music/get_lucky.mp3',
      fileName: 'get_lucky.mp3',
      fileSize: 14782012,
      mimeType: 'audio/mpeg',
    );

    test('saves tracks and normalizes artists, albums, and genres into relational tables', () async {
      await repository.saveTracks([track1, track2, track3]);

      final allTracks = await repository.getAllTracks();
      expect(allTracks.length, 3);

      final artists = await repository.getArtists();
      expect(artists.length, 2);
      final lpArtist = artists.firstWhere((a) => a.name == 'Linkin Park');
      expect(lpArtist.trackCount, 2);

      final albums = await repository.getAlbums();
      expect(albums.length, 2);
      final meteora = albums.firstWhere((a) => a.title == 'Meteora');
      expect(meteora.trackCount, 2);
      expect(meteora.albumArtist, 'Linkin Park');

      final genres = await repository.getGenres();
      expect(genres.length, 2);
      final altRock = genres.firstWhere((g) => g.name == 'Alternative Rock');
      expect(altRock.trackCount, 2);
    });

    test('queries tracks by artist', () async {
      await repository.saveTracks([track1, track2, track3]);

      final artists = await repository.getArtists();
      final lp = artists.firstWhere((a) => a.name == 'Linkin Park');

      final lpTracks = await repository.getTracksByArtist(lp.id);
      expect(lpTracks.length, 2);
      expect(lpTracks.map((t) => t.title), containsAll(['Numb', 'Faint']));
    });

    test('queries tracks by album', () async {
      await repository.saveTracks([track1, track2, track3]);

      final albums = await repository.getAlbums();
      final ram = albums.firstWhere((a) => a.title == 'Random Access Memories');

      final ramTracks = await repository.getTracksByAlbum(ram.title);
      expect(ramTracks.length, 1);
      expect(ramTracks.first.title, 'Get Lucky');
    });

    test('queries tracks by genre', () async {
      await repository.saveTracks([track1, track2, track3]);

      final genres = await repository.getGenres();
      final funk = genres.firstWhere((g) => g.name == 'Disco / Funk');

      final funkTracks = await repository.getTracksByGenre(funk.id);
      expect(funkTracks.length, 1);
      expect(funkTracks.first.title, 'Get Lucky');
    });

    test('deletes track and clears database', () async {
      await repository.saveTracks([track1, track2]);
      await repository.deleteTrack('1');

      final remaining = await repository.getAllTracks();
      expect(remaining.length, 1);
      expect(remaining.first.id, '2');

      await repository.clearAll();
      expect(await repository.getAllTracks(), isEmpty);
    });

    test('returns the most recently added tracks, limited', () async {
      await repository.saveTracks([track1, track2, track3]);

      final recent = await repository.getRecentlyAddedTracks(limit: 2);
      expect(recent.length, 2);
      final ids = recent.map((t) => t.id).toSet();
      expect(ids.every((i) => const {'1', '2', '3'}.contains(i)), isTrue);

      final all = await repository.getRecentlyAddedTracks();
      expect(all.length, 3);
    });
  });
}
