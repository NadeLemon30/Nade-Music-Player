import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';

/// A resolved playlist entry (Phase 3J): a [track] at its 0-based [position]
/// within the playlist's custom ordering — distinct from the raw
/// [`PlaylistTrack`] membership link model.
class PlaylistEntry {
  final Track track;
  final int position;

  const PlaylistEntry({
    required this.track,
    required this.position,
  });
}

/// Persistent user-created playlists backed by the Drift `playlists` +
/// `playlist_tracks` tables (Phase 3J).
///
/// Keeps an in-memory mirror of the playlist headers and per-playlist ordered
/// track lists so UI builds never round-trip the database. The four "song
/// collections" stay architecturally separate (3J.2): this service owns
/// playlists; Favorites, play history, and the playback queue each keep their
/// own models/service.
///
/// The default constructor requires [db]; the no-arg form is used by test
/// stubs that override all persistence.
class PlaylistService {
  final PlaylistRepository? _repository;

  /// In-memory playlist headers, in creation order (newest appended).
  final List<Playlist> _playlists = [];

  /// Per-playlist ordered track lists: playlist id -> tracks (position = index).
  final Map<String, List<Track>> _tracksByPlaylist = {};

  /// Resolves once the persisted playlists have been restored into memory.
  /// Every mutation awaits [ready] first, so a slow initial [restore] can never
  /// clobber state that was created before it finished.
  late final Future<void> _ready;

  final StreamController<List<Playlist>> _controller =
      StreamController<List<Playlist>>.broadcast();

  PlaylistService([this._repository]) {
    // Eagerly restore persisted playlists so lookups are warm on first use.
    _ready = _restore();
  }

  /// Completes once persisted playlists have been restored into memory.
  Future<void> get ready => _ready;

  /// Live list of playlist headers (creation order).
  Stream<List<Playlist>> get playlistsStream => _controller.stream;

  /// Snapshot of the current playlist headers.
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  /// Whether the service has a backing datastore (false only in test stubs).
  bool get hasBackingStore => _repository != null;

  /// Closes the broadcast stream used by [playlistsStream].
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _ensureLoaded() => ready;

  /// Returns the playlist header with [id], or null when it does not exist.
  Playlist? getPlaylist(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  /// The number of playlists.
  int get count => _playlists.length;

  /// The ordered [PlaylistEntry]s in playlist [playlistId] (resolved [Track]
  /// + position).
  List<PlaylistEntry> playlistEntries(String playlistId) {
    final tracks = _tracksByPlaylist[playlistId] ?? const <Track>[];
    return List.unmodifiable(
      List.generate(
        tracks.length,
        (i) => PlaylistEntry(track: tracks[i], position: i),
      ),
    );
  }

  /// The ordered [Track]s in playlist [playlistId].
  List<Track> tracksForPlaylist(String playlistId) {
    return List.unmodifiable(_tracksByPlaylist[playlistId] ?? const []);
  }

  /// The number of tracks currently in playlist [playlistId].
  int trackCount(String playlistId) {
    return _tracksByPlaylist[playlistId]?.length ?? 0;
  }

  /// Whether [trackId] is already a member of playlist [playlistId] (O(n),
  /// in-memory only).
  bool contains(String playlistId, String trackId) {
    return _tracksByPlaylist[playlistId]?.any((t) => t.id == trackId) ?? false;
  }

  /// Creates a new playlist named [name]. Returns the created [Playlist].
  /// Playlist ids are random UUIDs (3J.5), so names are never treated as ids.
  ///
  /// Validation (3J.9/3J.10): the name is trimmed; must be 1..100 characters
  /// after trimming. Duplicate names are allowed (the id is the identity).
  Future<Playlist> createPlaylist(String name) async {
    await _ensureLoaded();
    final trimmed = _validatedName(name);

    final repository = _repository;
    final playlist = repository != null
        ? await repository.create(trimmed)
        : Playlist(id: generateUuidV4(), name: trimmed, createdAt: DateTime.now());

    _playlists.add(playlist);
    _tracksByPlaylist[playlist.id] = [];
    _emit();
    return playlist;
  }

  /// Renames the playlist with [id]. No-op when it does not exist. The name is
  /// trimmed and must be 1..100 characters after trimming (3J.9/3J.10).
  Future<void> renamePlaylist(String id, String name) async {
    await _ensureLoaded();
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;

    final trimmed = _validatedName(name);
    _playlists[index] = _playlists[index].copyWith(name: trimmed);
    _emit();

    await _repository?.rename(id, trimmed);
  }

  /// Deletes the playlist with [id] and all of its tracks (ON DELETE CASCADE).
  Future<void> deletePlaylist(String id) async {
    await _ensureLoaded();
    _playlists.removeWhere((p) => p.id == id);
    _tracksByPlaylist.remove(id);
    _emit();

    await _repository?.delete(id);
  }

  /// Appends [track] to playlist [playlistId]. No-op when the track is already
  /// a member or the playlist does not exist (3J.3 composite PK).
  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    await _ensureLoaded();
    final list = _tracksByPlaylist[playlistId];
    if (list == null || list.any((t) => t.id == track.id)) return;

    list.add(track);
    _emit();

    await _repository?.addTrack(playlistId, track.id);
  }

  /// Appends [tracks] to playlist [playlistId] as one unit (spec 24): the
  /// backing writes run inside a single transaction so a multi-track add can
  /// never leave a partially updated playlist. Idempotent — tracks already in
  /// the playlist are skipped, and the in-memory + persisted order is the
  /// caller's selection order minus the already-present ones.
  Future<void> addTracksToPlaylist(
    String playlistId,
    List<Track> tracks,
  ) async {
    await _ensureLoaded();
    if (tracks.isEmpty) return;
    final list = _tracksByPlaylist[playlistId];
    if (list == null) return;

    final existingIds = {for (final t in list) t.id};
    final toAdd = <Track>[];
    for (final t in tracks) {
      // Skip tracks already in the playlist AND duplicates within the batch,
      // so the in-memory order always matches the persisted selection order.
      if (existingIds.contains(t.id)) continue;
      existingIds.add(t.id);
      toAdd.add(t);
    }
    if (toAdd.isEmpty) return;

    list.addAll(toAdd);
    _emit();

    await _repository
        ?.addTracks(playlistId, [for (final t in toAdd) t.id]);
  }

  /// Removes [trackId] from playlist [playlistId] and renumbers the survivors.
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    await _ensureLoaded();
    final list = _tracksByPlaylist[playlistId];
    if (list == null) return;
    final before = list.length;
    list.removeWhere((t) => t.id == trackId);
    if (list.length == before) return;
    _emit();

    final repository = _repository;
    if (repository != null) {
      await repository.removeTrack(playlistId, trackId);
      await repository
          .setTrackOrder(playlistId, [for (final t in list) t.id]);
    }
  }

  /// Moves the track at [oldIndex] to [newIndex] within playlist [playlistId]
  /// (0-based, clamped). Rewrites the position column for every affected row.
  Future<void> moveTrack(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await _ensureLoaded();
    final list = _tracksByPlaylist[playlistId];
    if (list == null || list.isEmpty) return;
    final from = oldIndex.clamp(0, list.length - 1);
    final to = newIndex.clamp(0, list.length - 1);
    if (from == to) return;

    final track = list.removeAt(from);
    list.insert(to, track);
    _emit();

    await _repository?.reorderTracks(playlistId, from, to);
  }

  /// Lazy removal of playlist entries whose music file has been deleted (3J.1
  /// "Handle deleted music files"). Called when a playlist screen is shown
  /// (matching the favorites/history prune pattern). [availableTrackIds] are
  /// the tracks still present in the library; any playlist entry outside that
  /// set is dropped from memory and the `playlist_tracks` table. The song
  /// file itself is untouched.
  Future<void> pruneMissingTracks(Set<String> availableTrackIds) async {
    await _ensureLoaded();

    final repository = _repository;
    for (final entry in _tracksByPlaylist.entries.toList()) {
      final list = entry.value;
      final before = list.length;
      list.removeWhere((t) => !availableTrackIds.contains(t.id));
      if (list.length != before) {
        _emit();
        await repository
            ?.setTrackOrder(entry.key, [for (final t in list) t.id]);
      }
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_playlists));
    }
  }

  /// Validates a playlist name per 3J.9/3J.10: trimmed, 1..100 characters.
  /// Returns the trimmed name or throws [ArgumentError].
  String _validatedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty');
    }
    if (trimmed.length > 100) {
      throw ArgumentError.value(
        name,
        'name',
        'Playlist name cannot exceed 100 characters',
      );
    }
    return trimmed;
  }

  Future<void> _restore() async {
    final repository = _repository;
    if (repository == null) return;

    try {
      final playlists = await repository.getAll();
      _playlists
        ..clear()
        ..addAll(playlists);

      _tracksByPlaylist
        ..clear()
        ..addEntries(playlists.map((p) => MapEntry(p.id, <Track>[])));

      final trackById = await repository.getTracksById();
      final links = await repository.getAllTracks();
      for (final link in links) {
        final list = _tracksByPlaylist[link.playlistId];
        if (list == null) continue;
        final track = trackById[link.trackId];
        if (track != null) list.add(track);
      }
    } catch (_) {
      // Non-fatal: fall back to an empty playlist list for this session.
    }
  }
}

/// Provider exposing the singleton [PlaylistService], backed by Drift through
/// [PlaylistRepository].
final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final service = PlaylistService(ref.watch(playlistRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// The user's playlists, as a reactive [StreamProvider] of playlists.
final playlistsProvider = StreamProvider<List<Playlist>>((ref) async* {
  final service = ref.watch(playlistServiceProvider);
  await service.ready;
  yield service.playlists;
  yield* service.playlistsStream;
});