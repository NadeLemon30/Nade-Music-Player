import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/library_controller.dart';
import 'package:nades_music_player/data/repositories/playlist_history_repository.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/screens/library/songs_list_screen.dart';
import 'package:nades_music_player/services/favorites/favorites_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';
import 'package:nades_music_player/services/playlists/playlist_service.dart';
import 'package:nades_music_player/widgets/track_tile.dart';

import '../helpers/fake_audio_player_service.dart';
import '../helpers/fake_library_controller.dart';
import '../helpers/noop_playlist_history_repository.dart';

void main() {
  final sampleTracks = [
    const Track(
      id: 'track_1',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/storage/music/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'track_2',
      title: 'In the End',
      artist: 'Linkin Park',
      album: 'Hybrid Theory',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 36),
      filePath: '/storage/music/in_the_end.mp3',
      fileName: 'in_the_end.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'track_3',
      title: 'Breaking the Habit',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 16),
      filePath: '/storage/music/breaking_the_habit.mp3',
      fileName: 'breaking_the_habit.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  testWidgets('SongsListScreen displays scanned songs with title, artist, and album',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(LibraryData(tracks: sampleTracks)),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        ],
        child: const MaterialApp(
          home: SongsListScreen(),
        ),
      ),
    );

    // Initial frame
    await tester.pump();

    // Verify header and song count
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Verify track list items
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('In the End'), findsOneWidget);
    expect(find.text('Breaking the Habit'), findsOneWidget);
    expect(find.text('Hybrid Theory'), findsOneWidget);
    expect(find.text('Meteora'), findsNWidgets(2));

    expect(find.byType(TrackTile), findsNWidgets(3));
  });

  testWidgets('SongsListScreen displays empty state when no songs are scanned',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(const LibraryData()),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        ],
        child: const MaterialApp(
          home: SongsListScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('No songs found'), findsOneWidget);
    expect(find.text('Tap scan to discover music on your device.'), findsOneWidget);
    expect(find.text('Scan Music'), findsOneWidget);
  });

  group('multi-select (spec 6)', () {
    final selectionTracks = [testTrack('a'), testTrack('b'), testTrack('c')];

    ProviderContainer buildContainer() {
      return ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(FakeAudioPlayerService()),
          playHistoryServiceProvider
              .overrideWith((ref) => NoopPlayHistoryService()),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
          playlistHistoryRepositoryProvider
              .overrideWithValue(NoopPlaylistHistoryRepository()),
          libraryProviderOverride(LibraryData(tracks: selectionTracks)),
        ],
      );
    }

    Future<void> pumpSongs(WidgetTester tester, ProviderContainer container) {
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SongsListScreen()),
        ),
      );
    }

    testWidgets('long-press enters selection mode with checkboxes and actions',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);

      await tester.longPress(find.text('Song a'));
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      // Header Play/Shuffle is replaced by the selection UI.
      expect(find.text('Play'), findsNothing);
      expect(find.text('Shuffle'), findsNothing);
    });

    testWidgets('tapping rows toggles selection and deselecting all exits',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song c'));
      await tester.pump();

      expect(find.text('2 selected'), findsOneWidget);

      // Deselect both: the last toggle exits selection mode.
      await tester.tap(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song c'));
      await tester.pump();

      expect(find.text('Songs'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('Add to Playlist opens the picker and adds selected songs',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final mix = await service.createPlaylist('Mix');

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song b'));
      await tester.pump();

      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Playlist'), findsOneWidget);
      expect(find.text('2 songs selected'), findsOneWidget);

      await tester.tap(find.text('Mix'));
      await tester.pumpAndSettle();

      expect(service.tracksForPlaylist(mix.id).map((t) => t.id),
          ['a', 'b']);
      // Back to normal browsing once the selection is applied.
      expect(find.text('Songs'), findsOneWidget);
    });

    testWidgets('Add to Queue enqueues the selected songs', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song b'));
      await tester.pump();

      await tester.tap(find.text('Queue'));
      await tester.pump();

      expect(
        container.read(playerNotifierProvider).queue.map((t) => t.id),
        ['a', 'b'],
      );
      expect(find.text('Added 2 songs to queue'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
    });

    testWidgets('Play Next queues the selected songs', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song b'));
      await tester.pump();

      await tester.tap(find.text('Play Next'));
      await tester.pump();

      expect(
        container.read(playerNotifierProvider).queue.map((t) => t.id),
        ['a', 'b'],
      );
      expect(find.text('Playing 2 songs next'), findsOneWidget);
    });

    testWidgets('Favorite adds the selected songs to favorites',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song b'));
      await tester.pump();

      await tester.tap(find.text('Favorite'));
      await tester.pump();

      final favorites = container.read(favoritesServiceProvider);
      expect(favorites.count, 2);
      expect(favorites.isFavoriteId('a'), isTrue);
      expect(favorites.isFavoriteId('b'), isTrue);
      expect(find.text('Added 2 songs to favorites'), findsOneWidget);
    });

    testWidgets('close button exits selection mode', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpSongs(tester, container);
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.text('Song b'));
      await tester.pump();

      await tester.tap(find.byTooltip('Exit selection'));
      await tester.pump();

      expect(find.text('Songs'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
