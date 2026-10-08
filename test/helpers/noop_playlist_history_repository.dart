import 'package:nades_music_player/data/repositories/playlist_history_repository.dart';

/// Lightweight in-memory stub of [PlaylistHistoryRepository] for widget and
/// unit tests that never touch a real Drift database.
class NoopPlaylistHistoryRepository
    implements PlaylistHistoryRepository {
  final Map<String, int> _counts = {};

  @override
  Future<void> recordPlay(String playlistId) async {
    _counts[playlistId] = (_counts[playlistId] ?? 0) + 1;
  }

  @override
  Future<List<PlaylistHistoryEntry>> getRecentlyPlayed() async {
    final entries = <PlaylistHistoryEntry>[
      for (final e in _counts.entries)
        PlaylistHistoryEntry(
          playlistId: e.key,
          playCount: e.value,
          lastPlayedAt: DateTime(2026, 1, 1),
        ),
    ];
    return entries..sort((a, b) => b.playCount.compareTo(a.playCount));
  }

  @override
  Future<int> getPlayCount(String playlistId) async {
    return _counts[playlistId] ?? 0;
  }

  @override
  Future<void> remove(String playlistId) async {
    _counts.remove(playlistId);
  }

  @override
  Future<void> clear() async {
    _counts.clear();
  }
}