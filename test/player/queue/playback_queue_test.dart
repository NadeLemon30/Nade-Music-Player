import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/player/queue/playback_queue.dart';
import 'package:test_app/player/queue/queue_item.dart';

import '../../helpers/fake_audio_player_service.dart';

void main() {
  group('PlaybackQueue', () {
    test('starts empty', () {
      final queue = PlaybackQueue();

      expect(queue.isEmpty, isTrue);
      expect(queue.items, isEmpty);
      expect(queue.currentIndex, -1);
      expect(queue.currentItem, isNull);
      expect(queue.currentTrack, isNull);
      expect(queue.hasNext, isFalse);
      expect(queue.hasPrevious, isFalse);
    });

    test('setQueue builds items with unique ids and sets the current index', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3')],
        initialIndex: 1,
      );

      expect(queue.isEmpty, isFalse);
      expect(queue.items.length, 3);
      expect(queue.currentIndex, 1);
      expect(queue.currentItem!.track.title, 'Song 2');
      expect(queue.currentTrack!.title, 'Song 2');

      final ids = queue.items.map((e) => e.id).toSet();
      expect(ids.length, 3, reason: 'ids must be unique');
    });

    test('setQueue clamps out-of-range initialIndex', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2')], initialIndex: 99);

      expect(queue.currentIndex, 1);

      queue.setQueue([testTrack('1'), testTrack('2')], initialIndex: -5);
      expect(queue.currentIndex, 0);
    });

    test('setQueue with no tracks leaves the queue empty', () {
      final queue = PlaybackQueue();
      queue.setQueue([]);

      expect(queue.isEmpty, isTrue);
      expect(queue.currentIndex, -1);
    });

    test('isEmpty only reads the item count, not the current index', () {
      final queue = PlaybackQueue();
      queue.add(testTrack('1'));

      expect(queue.isEmpty, isFalse);
    });

    test('next advances through the queue and stops at the end', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2'), testTrack('3')]);

      expect(queue.hasNext, isTrue);
      expect(queue.next()!.track.title, 'Song 2');
      expect(queue.currentIndex, 1);
      expect(queue.hasNext, isTrue);
      expect(queue.next()!.track.title, 'Song 3');
      expect(queue.currentIndex, 2);
      expect(queue.hasNext, isFalse);
      expect(queue.next(), isNull);
      expect(queue.currentIndex, 2);
    });

    test('previous moves backward and stops at the first item', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2')], initialIndex: 1);

      expect(queue.hasPrevious, isTrue);
      expect(queue.previous()!.track.title, 'Song 1');
      expect(queue.currentIndex, 0);
      expect(queue.hasPrevious, isFalse);
      expect(queue.previous(), isNull);
      expect(queue.currentIndex, 0);
    });

    test('setCurrentIndex ignores out-of-range indexes', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2')]);

      queue.setCurrentIndex(5);
      expect(queue.currentIndex, 0);
      queue.setCurrentIndex(-1);
      expect(queue.currentIndex, 0);
      queue.setCurrentIndex(1);
      expect(queue.currentIndex, 1);
    });

    test('clear resets items and the current index', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1')]);
      queue.clear();

      expect(queue.isEmpty, isTrue);
      expect(queue.currentIndex, -1);
      expect(queue.currentItem, isNull);
    });

    test('items is unmodifiable (3E.4) — external mutation is rejected', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1')]);

      final view = queue.items;
      expect(() => view.clear(), throwsUnsupportedError);
      expect(() => view.add(QueueItem(id: 'ext', track: testTrack('2'))),
          throwsUnsupportedError);

      queue.clear();
      expect(queue.items, isEmpty);
    });

    test('add appends a track to the end and does not change the current item'
        ' (3E.5)', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1')]);

      queue.add(testTrack('2'));

      expect(queue.items.length, 2);
      expect(queue.items[1].track.title, 'Song 2');
      expect(queue.currentIndex, 0);
      expect(queue.currentTrack!.title, 'Song 1');
    });

    test('add still works on an empty queue', () {
      final queue = PlaybackQueue();
      queue.add(testTrack('1'));

      expect(queue.items.length, 1);
      expect(queue.items.single.track.title, 'Song 1');
      expect(queue.currentIndex, -1);
    });

    test('addNext inserts directly after the current item (3E.6)', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2'), testTrack('3')]);

      queue.addNext(testTrack('X'));

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 1', 'Song X', 'Song 2', 'Song 3'],
      );
      expect(queue.currentIndex, 0);
      expect(queue.currentTrack!.title, 'Song 1');
    });

    test('addNext ahead of the current item does not shift the current index'
        ' (3E.6)', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3')],
        initialIndex: 2,
      );

      queue.addNext(testTrack('X'));

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 1', 'Song 2', 'Song 3', 'Song X'],
      );
      expect(queue.currentIndex, 2);
      expect(queue.currentTrack!.title, 'Song 3');
    });

    test('removeAt skips an out-of-range index (3E.7)', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1')]);

      queue.removeAt(5);
      expect(queue.items.map((e) => e.track.title).toList(), ['Song 1']);

      queue.removeAt(-1);
      expect(queue.items.map((e) => e.track.title).toList(), ['Song 1']);
    });

    test('removeAt before the current item shifts the current index down'
        ' (3E.7)', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3')],
        initialIndex: 1,
      );

      queue.removeAt(0);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 2', 'Song 3'],
      );
      expect(queue.currentIndex, 0);
      expect(queue.currentTrack!.title, 'Song 2');
    });

    test('removeAt removes the current item by falling onto the next one'
        ' (3E.7)', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3')],
        initialIndex: 1,
      );

      queue.removeAt(1);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 1', 'Song 3'],
      );
      expect(queue.currentIndex, 1);
      expect(queue.currentTrack!.title, 'Song 3');
    });

    test('removeAt of the last remaining item resets the queue (3E.7)', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1')]);

      queue.removeAt(0);

      expect(queue.isEmpty, isTrue);
      expect(queue.currentIndex, -1);
      expect(queue.currentItem, isNull);
    });

    test('removeAt of the current last item snaps back to the new tail (3E.7)',
        () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3')],
        initialIndex: 2,
      );

      queue.removeAt(2);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 1', 'Song 2'],
      );
      expect(queue.currentIndex, 1);
      expect(queue.currentTrack!.title, 'Song 2');
    });

    test('move skips an out-of-range index (3E.8)', () {
      final queue = PlaybackQueue();
      queue.setQueue([testTrack('1'), testTrack('2')]);

      queue.move(3, 1);
      expect(queue.items.map((e) => e.track.title).toList(),
          ['Song 1', 'Song 2']);

      queue.move(0, 5);
      expect(queue.items.map((e) => e.track.title).toList(),
          ['Song 1', 'Song 2']);
    });

    test('move of the current item keeps it current at the new index (3E.8)',
        () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3'), testTrack('4')],
        initialIndex: 1,
      );

      queue.move(1, 3);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 1', 'Song 3', 'Song 4', 'Song 2'],
      );
      expect(queue.currentIndex, 3);
      expect(queue.currentTrack!.title, 'Song 2');
    });

    test('move an item after the current one up past it shifts the current'
        ' index (3E.8)', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3'), testTrack('4')],
        initialIndex: 1,
      );

      queue.move(3, 0);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 4', 'Song 1', 'Song 2', 'Song 3'],
      );
      expect(queue.currentIndex, 2);
      expect(queue.currentTrack!.title, 'Song 2');
    });

    test('move an item before the current one down past it keeps the current'
        ' item pinned (3E.8)', () {
      final queue = PlaybackQueue();
      queue.setQueue(
        [testTrack('1'), testTrack('2'), testTrack('3'), testTrack('4')],
        initialIndex: 2,
      );

      queue.move(0, 3);

      expect(
        queue.items.map((e) => e.track.title).toList(),
        ['Song 2', 'Song 3', 'Song 4', 'Song 1'],
      );
      expect(queue.currentIndex, 1);
      expect(queue.currentTrack!.title, 'Song 3');
    });
  });
}