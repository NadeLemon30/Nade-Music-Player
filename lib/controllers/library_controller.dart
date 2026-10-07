import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/album_repository.dart';
import '../data/repositories/artist_repository.dart';
import '../data/repositories/music_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/favorites/favorites_service.dart';
import '../services/playback/play_history_service.dart';
import '../services/playlists/playlist_service.dart';
import 'library_scan_controller.dart';

/// Immutable snapshot of the library's primary collections.
///
/// Screens display this data; they never own it. [LibraryController] loads and
/// refreshes it from the repositories, making it the central point the library
/// UI reads from.
class LibraryData {
  final List<Track> tracks;
  final List<Artist> artists;
  final List<Album> albums;
  final bool loading;
  final bool isScanning;
  final String? error;

  const LibraryData({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.loading = false,
    this.isScanning = false,
    this.error,
  });

  LibraryData copyWith({
    List<Track>? tracks,
    List<Artist>? artists,
    List<Album>? albums,
    bool? loading,
    bool? isScanning,
    String? error,
    bool clearError = false,
  }) {
    return LibraryData(
      tracks: tracks ?? this.tracks,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      loading: loading ?? this.loading,
      isScanning: isScanning ?? this.isScanning,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Riverpod notifier that owns library data and hands it to the UI.
///
/// This is the single central point from which library screens obtain their
/// tracks, artists, and albums — they display the data but never load it.
class LibraryController extends Notifier<LibraryData> {
  MusicRepository get _musicRepository => ref.read(musicRepositoryProvider);
  ArtistRepository get _artistRepository =>
      ref.read(artistRepositoryProvider);
  AlbumRepository get _albumRepository => ref.read(albumRepositoryProvider);

  @override
  LibraryData build() {
    // Kick off an initial load; the UI renders the empty state meanwhile.
    Future.microtask(load);
    return const LibraryData();
  }

  /// Loads tracks, artists, and albums from the repositories.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final tracks = await _musicRepository.getAllTracks();
      final artists = await _artistRepository.getAllArtists();
      final albums = await _albumRepository.getAllAlbums();

      state = state.copyWith(
        tracks: tracks,
        artists: artists,
        albums: albums,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Re-loads library data from the repositories.
  Future<void> refresh() => load();

  /// Scans MediaStore, synchronizes SQLite, then reloads the controller.
  ///
  /// This is the single entry point every library screen uses to refresh —
  /// screens never talk to the scanner directly. They simply react to the
  /// updated controller state ([LibraryData.loading] / [LibraryData.isScanning]).
  Future<void> scanAndRefresh() async {
    if (state.isScanning) return;

    state = state.copyWith(isScanning: true, clearError: true);

    try {
      await ref.read(musicLibrarySyncServiceProvider).synchronize();
      // Spec 23: mirror the DB-level relationship purge into the in-memory
      // favorites / play-history / playlist collections so the UI reflects a
      // deleted track everywhere (the playlists themselves survive).
      await _syncCollectionMirrors();
      await load();
      state = state.copyWith(isScanning: false);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  /// Drops deleted-track entries from the in-memory collection mirrors using
  /// the set of tracks still present in the database after a scan (spec 23).
  Future<void> _syncCollectionMirrors() async {
    final availableIds = await _musicRepository.getAllTrackIds();
    await ref.read(favoritesServiceProvider).pruneMissingTracks(availableIds);
    await ref.read(playHistoryServiceProvider).pruneMissingTracks(availableIds);
    await ref.read(playlistServiceProvider).pruneMissingTracks(availableIds);
  }
}

/// Provider exposing [LibraryController] and [LibraryData].
final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryData>(LibraryController.new);
