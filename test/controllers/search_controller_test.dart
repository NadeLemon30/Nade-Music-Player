import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/search_controller.dart';
import 'package:nades_music_player/data/repositories/music_repository.dart';
import 'package:nades_music_player/models/search_results.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/services/playlists/playlist_service.dart';

void main() {
  final sampleTracks = [
    const Track(
      id: '1',
      title: 'Somewhere I Belong',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: 'Nu Metal',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/storage/Music/Linkin Park/Meteora/03 - Somewhere I Belong.mp3',
      fileName: '03 - Somewhere I Belong.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: '2',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: 'Alternative Rock',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/storage/Music/Linkin Park/Meteora/13 - Numb.mp3',
      fileName: '13 - Numb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: '3',
      title: 'Faint',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: 'Nu Metal',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/storage/Music/Linkin Park/Meteora/07 - Faint.mp3',
      fileName: '07 - Faint.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: '4',
      title: 'One More Time',
      artist: 'Daft Punk',
      album: 'Discovery',
      albumArtist: '',
      genre: 'French House',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/storage/Music/Daft Punk/Discovery/01 - One More Time.mp3',
      fileName: '01 - One More Time.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  group('SearchControllerNotifier', () {
    test('submitQuery searches across songs, artists, albums, genres, and folders', () async {
      final mockRepo = MockMusicRepository(sampleTracks);
      final container = ProviderContainer(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchControllerProvider.notifier);

      // Search for 'mete'
      await notifier.submitQuery('mete');

      final state = container.read(searchControllerProvider);
      expect(state.query, 'mete');
      expect(state.isLoading, isFalse);
      expect(state.results.isEmpty, isFalse);

      // Albums: Meteora
      expect(state.results.albums.length, 1);
      expect(state.results.albums.first.title, 'Meteora');

      // Songs: Somewhere I Belong, Numb, Faint
      expect(state.results.tracks.length, 3);
      expect(
        state.results.tracks.map((t) => t.title),
        containsAll(['Somewhere I Belong', 'Numb', 'Faint']),
      );

      // Folders: Meteora folder
      expect(state.results.folders.length, 1);
      expect(state.results.folders.first.name, 'Meteora');

      // Recent searches recorded
      expect(state.recentSearches, contains('mete'));
    });

    test('submitQuery finds playlists by name from the live playlist data (spec 16)',
        () async {
      final mockRepo = MockMusicRepository(sampleTracks);
      final playlistService = PlaylistService(null);
      await playlistService.createPlaylist('Electronic Favorites');
      await playlistService.createPlaylist('Study Mix');
      final container = ProviderContainer(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          playlistServiceProvider.overrideWithValue(playlistService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchControllerProvider.notifier);
      await notifier.submitQuery('electr');

      final state = container.read(searchControllerProvider);
      expect(state.results.playlists.length, 1);
      expect(state.results.playlists.first.name, 'Electronic Favorites');

      await notifier.submitQuery('zzz');
      expect(container.read(searchControllerProvider).results.playlists, isEmpty);
    });

    test('Filter changes update activeFilter in state', () {
      final container = ProviderContainer(
        overrides: [
          musicRepositoryProvider.overrideWithValue(MockMusicRepository(sampleTracks)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchControllerProvider.notifier);

      notifier.setFilter(SearchFilter.albums);
      expect(container.read(searchControllerProvider).activeFilter, SearchFilter.albums);

      notifier.setFilter(SearchFilter.playlists);
      expect(container.read(searchControllerProvider).activeFilter, SearchFilter.playlists);
    });

    test('clearQuery resets query and results but preserves recent searches', () async {
      final container = ProviderContainer(
        overrides: [
          musicRepositoryProvider.overrideWithValue(MockMusicRepository(sampleTracks)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchControllerProvider.notifier);
      await notifier.submitQuery('daft');

      expect(container.read(searchControllerProvider).query, 'daft');
      expect(container.read(searchControllerProvider).results.tracks.length, 1);

      notifier.clearQuery();

      final clearedState = container.read(searchControllerProvider);
      expect(clearedState.query, isEmpty);
      expect(clearedState.results.isEmpty, isTrue);
      expect(clearedState.recentSearches, contains('daft'));
    });

    test('Recent searches can be removed and cleared', () async {
      final container = ProviderContainer(
        overrides: [
          musicRepositoryProvider.overrideWithValue(MockMusicRepository(sampleTracks)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchControllerProvider.notifier);
      await notifier.submitQuery('linkin');
      await notifier.submitQuery('daft');

      expect(container.read(searchControllerProvider).recentSearches.length, 2);

      notifier.removeRecentSearch('linkin');
      expect(container.read(searchControllerProvider).recentSearches, ['daft']);

      notifier.clearRecentSearches();
      expect(container.read(searchControllerProvider).recentSearches, isEmpty);
    });
  });
}
