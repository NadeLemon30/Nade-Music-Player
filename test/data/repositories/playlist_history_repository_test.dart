import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/database/app_database.dart';
import 'package:test_app/data/repositories/playlist_history_repository.dart';

void main() {
  group('PlaylistHistoryRepository', () {
    late AppDatabase db;
    late PlaylistHistoryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = PlaylistHistoryRepository(db);
    });

    tearDown(() => db.close());

    test('recordPlay creates the row on first play', () async {
      await repo.recordPlay('p1');

      final count = await repo.getPlayCount('p1');
      expect(count, 1);
      final recent = await repo.getRecentlyPlayed();
      expect(recent.single.playlistId, 'p1');
      expect(recent.single.playCount, 1);
      expect(recent.single.lastPlayedAt, isNotNull);
    });

    test('recordPlay increments the count on replays', () async {
      await repo.recordPlay('p1');
      await repo.recordPlay('p1');

      expect(await repo.getPlayCount('p1'), 2);
      final recent = await repo.getRecentlyPlayed();
      expect(recent.single.playCount, 2);
    });

    test('getPlayCount returns 0 for an unplayed playlist', () async {
      expect(await repo.getPlayCount('never-played'), 0);
      expect(await repo.getRecentlyPlayed(), isEmpty);
    });

    test('getRecentlyPlayed orders by most recent first', () async {
      // Timestamps are wall-clock; record in sequence so p1 < p2 < p3.
      await repo.recordPlay('p1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.recordPlay('p2');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.recordPlay('p3');

      final recent = await repo.getRecentlyPlayed();
      expect(recent.map((e) => e.playlistId).toList(), ['p3', 'p2', 'p1']);
    });

    test('remove drops a single playlist from history', () async {
      await repo.recordPlay('p1');
      await repo.recordPlay('p2');

      await repo.remove('p1');

      expect(await repo.getPlayCount('p1'), 0);
      expect(await repo.getPlayCount('p2'), 1);
      final recent = await repo.getRecentlyPlayed();
      expect(recent.map((e) => e.playlistId).toList(), ['p2']);
    });

    test('clear empties the whole history', () async {
      await repo.recordPlay('p1');
      await repo.recordPlay('p2');

      await repo.clear();

      expect(await repo.getRecentlyPlayed(), isEmpty);
      expect(await repo.getPlayCount('p1'), 0);
      expect(await repo.getPlayCount('p2'), 0);
    });

    test('a fresh repository reading the same DB restores counts', () async {
      await repo.recordPlay('p1');
      await repo.recordPlay('p1');

      final restored = PlaylistHistoryRepository(db);
      expect(await restored.getPlayCount('p1'), 2);
      final recent = await restored.getRecentlyPlayed();
      expect(recent.single.playlistId, 'p1');
    });
  });
}