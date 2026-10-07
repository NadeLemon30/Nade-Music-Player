import 'dart:math';

import '../../models/track.dart';
import 'queue_item.dart';

/// Owns the ordered playback queue and the index of the current track.
///
/// Every slot is a [QueueItem] carrying a session-unique [QueueItem.id], so the
/// same track may appear more than once and modifications never depend on track
/// identity.
///
/// The queue deliberately exposes [items] as an unmodifiable view (3E.4):
/// `_items` is never handed out directly, so external code cannot
/// `queue.items.clear()` and bypass the queue's rules. All mutation — add,
/// remove, reorder, replay, shuffle — must go through this class. That becomes
/// critical once Shuffle, Repeat, Play Next, reordering, and queue persistence
/// are introduced.
class PlaybackQueue {
  final List<QueueItem> _items = [];

  int _currentIndex = -1;

  /// A read-only snapshot of the queue in playback order.
  ///
  /// Returned as [List.unmodifiable] so callers can only observe the queue;
  /// any change goes through the owning `PlaybackQueue` methods.
  List<QueueItem> get items =>
      List.unmodifiable(_items);

  int get currentIndex => _currentIndex;

  QueueItem? get currentItem {
    if (_currentIndex < 0 ||
        _currentIndex >= _items.length) {
      return null;
    }

    return _items[_currentIndex];
  }

  Track? get currentTrack =>
      currentItem?.track;

  bool get isEmpty => _items.isEmpty;

  bool get hasNext =>
      _currentIndex >= 0 &&
      _currentIndex < _items.length - 1;

  bool get hasPrevious =>
      _currentIndex > 0;

  void clear() {
    _items.clear();
    _currentIndex = -1;
  }

  void setQueue(
    List<Track> tracks, {
    int initialIndex = 0,
  }) {
    _items.clear();

    for (final track in tracks) {
      _items.add(
        QueueItem(
          id: _createId(),
          track: track,
        ),
      );
    }

    if (_items.isEmpty) {
      _currentIndex = -1;
      return;
    }

    _currentIndex = initialIndex.clamp(
      0,
      _items.length - 1,
    );
  }

  QueueItem? next() {
    if (!hasNext) {
      return null;
    }

    _currentIndex++;

    return currentItem;
  }

  QueueItem? previous() {
    if (!hasPrevious) {
      return null;
    }

    _currentIndex--;

    return currentItem;
  }

  void setCurrentIndex(int index) {
    if (index < 0 ||
        index >= _items.length) {
      return;
    }

    _currentIndex = index;
  }

  /// Appends [track] to the end of the queue, after the current item and after
  /// everything already queued (3E.5).
  void add(
    Track track,
  ) {
    _items.add(
      QueueItem(
        id: _createId(),
        track: track,
      ),
    );
  }

  /// Inserts [track] directly after the current item, so it plays next
  /// (3E.6). Unlike [add], which appends to the very end of the queue.
  void addNext(
    Track track,
  ) {
    final insertIndex =
        _currentIndex + 1;

    _items.insert(
      insertIndex,
      QueueItem(
        id: _createId(),
        track: track,
      ),
    );
  }

  /// Removes the item at [index], keeping the current index pointing at the
  /// same playing item (3E.7). Removing the current item itself makes the
  /// following item current; removing the last item snaps back to the new tail.
  void removeAt(
    int index,
  ) {
    if (index < 0 ||
        index >= _items.length) {
      return;
    }

    _items.removeAt(index);

    if (_items.isEmpty) {
      _currentIndex = -1;
      return;
    }

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _items.length) {
        _currentIndex =
            _items.length - 1;
      }
    }
  }

  /// Moves the item at [oldIndex] to [newIndex], keeping the current index
  /// pinned to the same playing item (3E.8) — even when that item is the one
  /// being moved.
  void move(
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 ||
        oldIndex >= _items.length) {
      return;
    }

    if (newIndex < 0 ||
        newIndex >= _items.length) {
      return;
    }

    final item = _items.removeAt(
      oldIndex,
    );

    _items.insert(
      newIndex,
      item,
    );

    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
      return;
    }

    if (oldIndex < _currentIndex &&
        newIndex >= _currentIndex) {
      _currentIndex--;
      return;
    }

    if (oldIndex > _currentIndex &&
        newIndex <= _currentIndex) {
      _currentIndex++;
    }
  }

  String _createId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(100000)}';
  }
}