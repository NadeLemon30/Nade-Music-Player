import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/database/app_database.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';

Track buildTrack(String id, String title) {
  return Track(
    id: id,
    title: title,
    artist: 'Artist',
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
  group('PlayHistoryService', () {
    test('records tracks most recent first', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));

      expect(service.entries.map((e) => e.track.id).toList(), ['2', '1']);
    });

    test('de-duplicates by track id, moving the track to the top', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));
      await service.record(buildTrack('1', 'A'));

      expect(service.entries.length, 2);
      expect(service.entries.map((e) => e.track.id).toList(), ['1', '2']);
    });

    test('caps the number of entries', () async {
      final service = PlayHistoryService(null, 3);
      for (var i = 0; i < 6; i++) {
        await service.record(buildTrack('$i', 'Track $i'));
      }

      expect(service.entries.length, 3);
      expect(
        service.entries.map((e) => e.track.id).toList(),
        ['5', '4', '3'],
      );
    });

    test('clear removes all entries', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.clear();

      expect(service.entries, isEmpty);
    });

    test('emits updates through the stream', () async {
      final service = PlayHistoryService(null, 50);
      final seen = <List<PlayHistoryEntry>>[];
      service.entriesStream.listen(seen.add);
      final atLeastTwo = service.entriesStream.where((e) => e.length >= 2).first;

      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));
      await atLeastTwo;

      expect(seen.last.map((e) => e.track.id).toList(), ['2', '1']);
    });

    test('increments the play count on replay', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('1', 'A'));

      final entry = service.entries.single;
      expect(entry.playCount, 3);
    });

    test('saveResumePosition records a per-track resume position', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.saveResumePosition('1', const Duration(seconds: 45));

      final entry = service.entries.single;
      expect(entry.resumePosition, const Duration(seconds: 45));
    });

    test('saveResumePosition is a no-op for an unrecorded track', () async {
      final service = PlayHistoryService(null, 50);
      await service.saveResumePosition('nope', const Duration(seconds: 45));

      expect(service.entries, isEmpty);
    });

    test('removeEntry removes a single entry by track id', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));
      await service.record(buildTrack('3', 'C'));

      await service.removeEntry('2');

      expect(service.entries.map((e) => e.track.id).toList(), ['3', '1']);
    });

    test('getRecentlyPlayed returns most recent first up to the limit (3H.11)',
        () async {
      final service = PlayHistoryService(null, 50);
      for (var i = 0; i < 5; i++) {
        await service.record(buildTrack('$i', 'Track $i'));
      }

      final all = await service.getRecentlyPlayed();
      expect(all.map((e) => e.track.id).toList(), ['4', '3', '2', '1', '0']);

      final limited = await service.getRecentlyPlayed(limit: 2);
      expect(limited.map((e) => e.track.id).toList(), ['4', '3']);
    });

    test('getRecentlyPlayed drops duplicates, keeping the latest played (3H.12)',
        () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));
      await service.record(buildTrack('1', 'A'));

      final result = await service.getRecentlyPlayed();
      expect(result.map((e) => e.track.id).toList(), ['1', '2']);

      final entry = result.first;
      expect(entry.playCount, 2);
    });

    test('pruneMissingTracks lazily removes stale entries (3H.29)', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('1', 'A'));
      await service.record(buildTrack('2', 'B'));
      await service.record(buildTrack('3', 'C'));

      // Track '2' was deleted from storage; only '1' and '3' remain available.
      await service.pruneMissingTracks({'1', '3'});

      expect(service.entries.map((e) => e.track.id).toList(), ['3', '1']);
    });

    test('getRecentlyPlayedTracks omits unavailable tracks (3H.30)', () async {
      final service = PlayHistoryService(null, 50);
      await service.record(buildTrack('x', 'X'));
      await service.record(buildTrack('y', 'Y'));

      // Drop the stale 'x' entry before reading.
      await service.pruneMissingTracks({'y'});

      final tracks = await service.getRecentlyPlayedTracks();
      expect(tracks.map((t) => t.id).toList(), ['y']);
    });

    test(
      'replaying persists the entry move to the top across restarts (test 4)',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => db.close());
        final service = PlayHistoryService(db, 50);

        // Distinct wall-clock timestamps so each play advances last_played_at.
        Future<void> play(String id) async {
          await service.record(buildTrack(id, id.toUpperCase()));
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        await play('a');
        await play('b');
        await play('a');

        // Replaying A must move it back to the top of persisted ordering.
        final recent = await service.getRecentlyPlayed();
        expect(recent.map((e) => e.track.id).toList(), ['a', 'b']);
        expect(recent.first.playCount, 2);

        // A fresh service reading the same DB preserves that order.
        final restored = PlayHistoryService(db, 50);
        final persisted = await restored.getRecentlyPlayed();
        expect(persisted.map((e) => e.track.id).toList(), ['a', 'b']);
      },
    );
  });
}
