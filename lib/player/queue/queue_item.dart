import '../../models/track.dart';

/// A single slot in the playback queue.
///
/// Wraps a [Track] with an [id] that is unique within the queue session so the
/// same track can appear multiple times and entries can be removed, reordered,
/// or persisted without relying on [Track] identity.
class QueueItem {
  final String id;

  final Track track;

  const QueueItem({required this.id, required this.track});

  @override
  bool operator ==(Object other) => other is QueueItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'QueueItem(id: $id, track: ${track.title})';
}