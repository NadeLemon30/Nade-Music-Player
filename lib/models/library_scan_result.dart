/// Result of a single library synchronization pass.
///
/// Captures how many songs were added, updated, and removed by comparing a fresh
/// MediaStore scan against the persisted SQLite library.
class LibraryScanResult {
  final int added;
  final int updated;
  final int removed;
  final int total;

  const LibraryScanResult({
    required this.added,
    required this.updated,
    required this.removed,
    required this.total,
  });
}
