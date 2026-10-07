import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/database/app_database.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/data/repositories/playlist_repository.dart';
import 'package:test_app/models/track.dart';
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
    duration: null,
    filePath: '/Music/$id.mp3',
    fileName: '$id.mp3',
    fileSize: null,
    mimeType: null,
    isAvailable: true,
  );
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  group('PlaylistService', () {
    test('createPlaylist assigns a UUID id and keeps the display name', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Road Trip');

      expect(playlist.name, 'Road Trip');
      expect(_uuidPattern.hasMatch(playlist.id), isTrue,
          reason: 'playlist ids are UUIDs, never the name (3J.5)');
      expect(service.playlists.single.id, playlist.id);
      expect(service.count, 1);
    });

    test('createPlaylist trims the name and rejects empty names (3J.9)', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('  Road Trip  ');

      expect(playlist.name, 'Road Trip');
      expect(
        () => service.createPlaylist('   '),
        throwsArgumentError,
        reason: 'a whitespace-only name is empty after trimming',
      );
    });

    test('createPlaylist rejects names longer than 100 characters (3J.10)',
        () async {
      final service = PlaylistService(null);
      expect(
        () => service.createPlaylist('x' * 101),
        throwsArgumentError,
      );
      final playlist = await service.createPlaylist('x' * 100);
      expect(playlist.name.length, 100, reason: '100 chars is the limit');
    });

    test('renamePlaylist trims and still enforces the non-empty rule', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.renamePlaylist(playlist.id, '  Workout  ');

      expect(service.getPlaylist(playlist.id)?.name, 'Workout');
      expect(
        () => service.renamePlaylist(playlist.id, '   '),
        throwsArgumentError,
      );
    });

    test('two playlists can share a name but never an id', () async {
      final service = PlaylistService(null);
      final a = await service.createPlaylist('Mix');
      final b = await service.createPlaylist('Mix');

      expect(a.id, isNot(b.id));
      expect(service.count, 2);
    });

    test('renamePlaylist changes the name, not the id', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Old Name');

      await service.renamePlaylist(playlist.id, 'New Name');

      expect(service.getPlaylist(playlist.id)!.name, 'New Name');
      expect(service.getPlaylist(playlist.id)!.id, playlist.id);
    });

    test('deletePlaylist removes the playlist and its tracks', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));

      await service.deletePlaylist(playlist.id);

      expect(service.getPlaylist(playlist.id), isNull);
      expect(service.trackCount(playlist.id), 0);
      expect(service.count, 0);
    });

    test('addTrackToPlaylist appends and duplicate adds are no-ops', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      final a = buildTrack('1', 'A');
      await service.addTrackToPlaylist(playlist.id, a);
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));
      await service.addTrackToPlaylist(playlist.id, a);

      expect(service.trackCount(playlist.id), 2);
      expect(
        service.tracksForPlaylist(playlist.id).map((t) => t.id).toList(),
        ['1', '2'],
        reason: 'the duplicate add must not be inserted a second time',
      );
    });

    test('addTrackToPlaylist to a missing playlist is a no-op', () async {
      final service = PlaylistService(null);
      await service.addTrackToPlaylist('missing', buildTrack('1', 'A'));
      expect(service.count, 0);
    });

    test('playlistEntries carries 0-based positions', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));

      final entries = service.playlistEntries(playlist.id);
      expect(entries.map((e) => e.position).toList(), [0, 1]);
      expect(entries.map((e) => e.track.id).toList(), ['1', '2']);
    });

    test('contains reports membership in-memory', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));

      expect(service.contains(playlist.id, '1'), isTrue);
      expect(service.contains(playlist.id, '999'), isFalse);
    });

    test('removeTrackFromPlaylist removes and renumbers survivors', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('3', 'C'));

      await service.removeTrackFromPlaylist(playlist.id, '2');

      expect(
        service.tracksForPlaylist(playlist.id).map((t) => t.id).toList(),
        ['1', '3'],
      );
      expect(
        service.playlistEntries(playlist.id).map((e) => e.position).toList(),
        [0, 1],
        reason: 'positions are renumbered after removal',
      );
    });

    test('moveTrack reorders the playlist', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      for (var i = 1; i <= 5; i++) {
        await service.addTrackToPlaylist(playlist.id, buildTrack('$i', 'T$i'));
      }

      await service.moveTrack(playlist.id, 0, 4);

      expect(
        service.tracksForPlaylist(playlist.id).map((t) => t.id).toList(),
        ['2', '3', '4', '5', '1'],
      );
    });

    test('pruneMissingTracks removes playlist entries whose file is gone',
        () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('3', 'C'));

      await service.pruneMissingTracks({'1', '3'});

      expect(
        service.tracksForPlaylist(playlist.id).map((t) => t.id).toList(),
        ['1', '3'],
      );
      expect(service.trackCount(playlist.id), 2);
    });

    test('pruneMissingTracks never touches the playlists themselves', () async {
      final service = PlaylistService(null);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));

      await service.pruneMissingTracks({});

      expect(service.getPlaylist(playlist.id), isNotNull);
      expect(service.trackCount(playlist.id), 0);
    });

    test('emits updates through the stream', () async {
      final service = PlaylistService(null);
      final seen = <List<String>>[];
      final sub = service.playlistsStream.listen(
        (events) => seen.add(events.map((p) => p.name).toList()),
      );
      addTearDown(() => sub.cancel());

      final playlist = await service.createPlaylist('Mix');
      // Wait until the rename is observed on the stream (broadcast delivery
      // is asynchronous), then assert history.
      final renamed = service.playlistsStream
          .firstWhere((e) => e.single.name == 'Renamed')
          .then((e) => e.map((p) => p.name).toList());
      await service.renamePlaylist(playlist.id, 'Renamed');

      expect(await renamed, ['Renamed']);
      expect(
        seen.expand((e) => e).toList(),
        containsAll(['Mix', 'Renamed']),
      );
    });

    test('playlists and tracks persist across restarts (Drift-backed)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      // Seed tracks into the tracks table so restore can resolve them.
      final repo = DriftMusicRepository(db);
      await repo.saveTracks([
        buildTrack('1', 'A'),
        buildTrack('2', 'B'),
        buildTrack('3', 'C'),
      ]);

      final service = PlaylistService(PlaylistRepository(db));
      final playlist = await service.createPlaylist('Persisted');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('2', 'B'));
      await service.addTrackToPlaylist(playlist.id, buildTrack('3', 'C'));
      await service.moveTrack(playlist.id, 0, 2);

      // A fresh service reading the same DB restores both tables.
      final restored = PlaylistService(PlaylistRepository(db));
      await restored.ready;
      expect(restored.count, 1);
      expect(restored.playlists.single.name, 'Persisted');
      expect(restored.playlists.single.id, playlist.id);
      expect(
        restored.tracksForPlaylist(playlist.id).map((t) => t.id).toList(),
        ['2', '3', '1'],
        reason: 'custom order (positions) is preserved across restarts',
      );
    });

    test('rename persists across restarts (Drift-backed)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final service = PlaylistService(PlaylistRepository(db));
      final playlist = await service.createPlaylist('Before');
      await service.renamePlaylist(playlist.id, 'After');

      final restored = PlaylistService(PlaylistRepository(db));
      await restored.ready;
      expect(restored.playlists.single.name, 'After');
    });

    test('deleted playlists and entries are gone after restore', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final repo = DriftMusicRepository(db);
      await repo.saveTracks([buildTrack('1', 'A')]);

      final service = PlaylistService(PlaylistRepository(db));
      final a = await service.createPlaylist('Keep');
      final b = await service.createPlaylist('Drop');
      await service.addTrackToPlaylist(a.id, buildTrack('1', 'A'));
      await service.addTrackToPlaylist(b.id, buildTrack('1', 'A'));
      await service.deletePlaylist(b.id);

      final restored = PlaylistService(PlaylistRepository(db));
      await restored.ready;
      expect(restored.count, 1);
      expect(restored.playlists.single.name, 'Keep');
      expect(restored.trackCount(a.id), 1);
    });

    test(
        'addTracksToPlaylist appends a batch in selection order and dedupes '
        '(spec 24)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final service = PlaylistService(PlaylistRepository(db));
      final playlist = await service.createPlaylist('Mix');
      await service.addTracksToPlaylist(playlist.id, [
        buildTrack('1', 'A'),
        buildTrack('2', 'B'),
        buildTrack('1', 'A'),
        buildTrack('3', 'C'),
      ]);

      expect(
        service
            .tracksForPlaylist(playlist.id)
            .map((t) => t.id)
            .toList(),
        ['1', '2', '3'],
      );
    });

    test(
        'addTracksToPlaylist persists a batch atomically across restarts '
        '(spec 24)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final repo = DriftMusicRepository(db);
      await repo.saveTracks([
        buildTrack('1', 'A'),
        buildTrack('2', 'B'),
        buildTrack('3', 'C'),
      ]);

      final service = PlaylistService(PlaylistRepository(db));
      final playlist = await service.createPlaylist('Persisted');
      await service.addTrackToPlaylist(playlist.id, buildTrack('1', 'A'));
      // Bulk-adds 2+3 while 1 is already present (idempotent via composite PK).
      await service.addTracksToPlaylist(playlist.id, [
        buildTrack('2', 'B'),
        buildTrack('3', 'C'),
        buildTrack('1', 'A'),
      ]);
      expect(service.trackCount(playlist.id), 3);

      final restored = PlaylistService(PlaylistRepository(db));
      await restored.ready;
      expect(restored.trackCount(playlist.id), 3);
      expect(
        restored
            .tracksForPlaylist(playlist.id)
            .map((t) => t.id)
            .toList(),
        ['1', '2', '3'],
      );
    });
  });
}