import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/controllers/library_controller.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/data/repositories/playlist_history_repository.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/player/player_controller.dart';
import 'package:test_app/screens/library/playlist_detail_screen.dart';
import 'package:test_app/screens/search/search_screen.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/services/playlists/playlist_service.dart';
import 'package:test_app/widgets/track_tile.dart';

import '../helpers/fake_audio_player_service.dart';
import '../helpers/fake_library_controller.dart';
import '../helpers/noop_playlist_history_repository.dart';

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

  testWidgets('SearchScreen displays search prompt and filter chips on initial load',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify search bar and filter chips
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Genres'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);

    // Initial prompt
    expect(find.text('Search your media library'), findsOneWidget);
  });

  testWidgets('Searching "mete" displays Albums (Meteora), Songs, and Folders',
      (WidgetTester tester) async {
    // Tall viewport so all categorized sections (including the Folders section
    // at the bottom of the lazy scroll view) render without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    // Enter query 'mete'
    await tester.enterText(find.byType(TextField), 'mete');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // debounce

    // Verify categorized sections
    expect(find.text('Albums'), findsAtLeastNWidgets(1));
    expect(find.text('Songs'), findsAtLeastNWidgets(1));
    expect(find.text('Folders'), findsAtLeastNWidgets(1));

    // Matching Album
    expect(find.text('Meteora'), findsAtLeastNWidgets(1));

    // Matching Songs
    expect(find.text('Somewhere I Belong'), findsOneWidget);
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('Faint'), findsOneWidget);

    expect(find.byType(TrackTile), findsNWidgets(3));
  });

  testWidgets('Filtering by Songs displays only tracks',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.enterText(find.byType(TextField), 'mete');
    await tester.pump(const Duration(milliseconds: 300));

    // Tap 'Songs (3)' filter chip
    await tester.tap(find.text('Songs (3)'));
    await tester.pump();

    expect(find.byType(TrackTile), findsNWidgets(3));
    expect(find.text('Somewhere I Belong'), findsOneWidget);
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('Faint'), findsOneWidget);
  });

  testWidgets('Searching for non-matching query displays empty results view',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.enterText(find.byType(TextField), 'nonexistentquery123');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No matches found'), findsOneWidget);
    expect(
      find.text('No songs, artists, albums, genres, folders, or playlists '
          'matching "nonexistentquery123".'),
      findsOneWidget,
    );
  });

  testWidgets('Clearing query resets to initial empty prompt',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.enterText(find.byType(TextField), 'daft');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('One More Time'), findsOneWidget);

    // Tap clear button
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('Search your media library'), findsOneWidget);
  });

  testWidgets('searching "favorites" surfaces the Playlists section and opens the detail (spec 16)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mockRepo = MockMusicRepository(sampleTracks);
    final playlistService = PlaylistService(null);
    await playlistService.createPlaylist('Electronic Favorites');
    await playlistService.createPlaylist('Study Mix');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(playlistService),
          audioPlayerServiceProvider
              .overrideWithValue(FakeAudioPlayerService()),
          playHistoryServiceProvider
              .overrideWith((ref) => NoopPlayHistoryService()),
          playlistHistoryRepositoryProvider
              .overrideWithValue(NoopPlaylistHistoryRepository()),
          libraryProviderOverride(const LibraryData()),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.enterText(find.byType(TextField), 'favorites');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // debounce

    // Playlists section is rendered with the matching playlist.
    expect(find.text('Playlists'), findsAtLeastNWidgets(1));
    expect(find.text('Electronic Favorites'), findsOneWidget);
    expect(find.text('Study Mix'), findsNothing);

    // Opens the playlist detail screen.
    await tester.tap(find.text('Electronic Favorites'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDetailScreen), findsOneWidget);
  });
}
