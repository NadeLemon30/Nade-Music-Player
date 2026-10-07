/// In-memory state tracking the last time the library was synchronized.
///
/// This is temporary application state (not persisted to SQLite). Persistent
/// settings like this will later live in a dedicated settings table.
class LibraryScanState {
  DateTime? lastScan;

  bool get hasScanned => lastScan != null;

  void markScanned() {
    lastScan = DateTime.now();
  }
}
