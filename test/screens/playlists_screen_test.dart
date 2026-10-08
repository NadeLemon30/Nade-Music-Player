import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/library_controller.dart';
import 'package:nades_music_player/data/repositories/playlist_history_repository.dart';
import 'package:nades_music_player/models/playlist.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/screens/home/home_screen.dart';
import 'package:nades_music_player/screens/library/playlist_detail_screen.dart';
import 'package:nades_music_player/screens/library/playlists_screen.dart';
import 'package:nades_music_player/services/favorites/favorites_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';
import 'package:nades_music_player/services/playlists/playlist_service.dart';
import 'package:nades_music_player/widgets/track_tile.dart';

import '../helpers/fake_audio_player_service.dart';
import '../helpers/fake_library_controller.dart';
import '../helpers/noop_playlist_history_repository.dart';

void main() {
  /// Sample tracks used both as the playlist contents and the fake library
  /// snapshot (so the detail screen's prune-on-show keeps them).
  final libraryTracks = [
    testTrack('a'),
    testTrack('b'),
    testTrack('c'),
  ];

  final LibraryData libraryData = LibraryData(tracks: libraryTracks);

  ProviderContainer buildContainer({
    NoopPlaylistHistoryRepository? history,
  }) {
    return ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(FakeAudioPlayerService()),
        playHistoryServiceProvider
            .overrideWith((ref) => NoopPlayHistoryService()),
        favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        playlistHistoryRepositoryProvider.overrideWithValue(
          history ?? NoopPlaylistHistoryRepository(),
        ),
        libraryProviderOverride(libraryData),
      ],
    );
  }

  Future<void> pumpPlaylists(
    WidgetTester tester,
    ProviderContainer container,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlaylistsScreen()),
      ),
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    ProviderContainer container,
    String playlistId,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PlaylistDetailScreen(playlistId: playlistId)),
      ),
    );
  }

  Future<String> createPlaylist(
    WidgetTester tester,
    ProviderContainer container,
    String name,
  ) async {
    final service = container.read(playlistServiceProvider);
    return (await service.createPlaylist(name)).id;
  }

  group('PlaylistsScreen', () {
    /// The row menu for the playlist named [name] — order-independent, since the
    /// default Newest sort and ms-resolution `createdAt` make row order flaky.
    Finder rowMenu(String name) => find.descendant(
          of: find.widgetWithText(ListTile, name),
          matching: find.byType(PopupMenuButton<String>),
        );

    testWidgets('shows an empty state when no playlists exist', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpPlaylists(tester, container);
      await tester.pump();

      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.text('Create Playlist'), findsOneWidget);
    });

    testWidgets('creates a playlist from the empty-state button',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.text('Create Playlist'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Road Trip');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.textContaining('0 songs'), findsOneWidget);
    });

    testWidgets('lists playlists with their song counts', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final p1 = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(p1.id, testTrack('a'));
      await service.addTrackToPlaylist(p1.id, testTrack('b'));
      await service.createPlaylist('Gym');

      await pumpPlaylists(tester, container);
      await tester.pump();

      expect(find.text('Mix'), findsOneWidget);
      expect(find.textContaining('2 songs'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.textContaining('0 songs'), findsOneWidget);
    });

    testWidgets('renames a playlist through its popup menu', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Old Name');

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Scope the name field to the dialog: the screen now shows a persistent
      // search field (3K.1) that is itself a TextField.
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'New Name',
      );
      await tester.pump();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();

      expect(find.text('Old Name'), findsNothing);
      expect(find.text('New Name'), findsOneWidget);
    });

    testWidgets('deletes a playlist after confirmation', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Doomed');

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete playlist?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('No playlists yet'), findsOneWidget);
      expect(service.playlists, isEmpty);
    });

    testWidgets('opens the detail screen when a playlist is tapped',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, testTrack('a'));

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.text('Mix'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistDetailScreen), findsOneWidget);
      expect(find.text('Song a'), findsOneWidget);
    });

    testWidgets('playlist row menu offers Play/Shuffle/Play Next/Add to '
        'Queue/Add Songs/Rename/Delete', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, testTrack('a'));

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.text('Add Songs'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Play from the menu loads the playlist into the queue.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.queue.map((t) => t.id), ['a']);
      expect(state.isPlaying, isTrue);
    });

    testWidgets('row menu Play Next inserts the playlist after the current track '
        '(3K.4)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playing = await service.createPlaylist('Playing');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(playing.id, t);
      }
      final next = await service.createPlaylist('Next');
      await service.addTrackToPlaylist(next.id, testTrack('x'));
      await service.addTrackToPlaylist(next.id, testTrack('y'));

      await pumpPlaylists(tester, container);
      await tester.pump();

      // Start playback of "Playing" via its row menu.
      await tester.tap(rowMenu('Playing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(
        container.read(playerNotifierProvider).queue.map((t) => t.id),
        ['a', 'b', 'c'],
      );

      // "Play Next" on "Next" puts x,y right after the current track, before b.
      await tester.tap(rowMenu('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Next'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.currentTrack?.id, 'a', reason: 'playback is untouched');
      expect(state.queue.map((t) => t.id), ['a', 'x', 'y', 'b', 'c']);
    });

    testWidgets('row menu Add to Queue appends the playlist at the end (3K.5)',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playing = await service.createPlaylist('Playing');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(playing.id, t);
      }
      final q = await service.createPlaylist('Queue');
      await service.addTrackToPlaylist(q.id, testTrack('x'));
      await service.addTrackToPlaylist(q.id, testTrack('y'));

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(rowMenu('Playing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await tester.tap(rowMenu('Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Queue'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.currentTrack?.id, 'a');
      expect(state.queue.map((t) => t.id), ['a', 'b', 'c', 'x', 'y']);
    });

    testWidgets('Play and Shuffle record playlist-level history (3K.3)',
        (tester) async {
      final history = NoopPlaylistHistoryRepository();
      final container = buildContainer(history: history);
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playlist = await service.createPlaylist('Mix');
      await service.addTrackToPlaylist(playlist.id, testTrack('a'));

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(await history.getPlayCount(playlist.id), 1);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(await history.getPlayCount(playlist.id), 2);

      final recent = await history.getRecentlyPlayed();
      expect(recent.single.playlistId, playlist.id);
      expect(recent.single.playCount, 2);
    });

    testWidgets('filters playlists as you type (3K.1)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Road Trip');
      await service.createPlaylist('Gym Mix');

      await pumpPlaylists(tester, container);
      await tester.pump();

      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.text('Gym Mix'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'road',
      );
      await tester.pump();

      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.text('Gym Mix'), findsNothing);

      // Clearing restores the full list.
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.text('Gym Mix'), findsOneWidget);
    });

    testWidgets('shows a no-match state for an unfindable query (3K.1)',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Road Trip');

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.enterText(
        find.byType(TextField).first,
        'zzz',
      );
      await tester.pump();

      expect(find.text('No playlists match "zzz"'), findsOneWidget);
      expect(find.text('Road Trip'), findsNothing);
      expect(find.text('No playlists yet'), findsNothing);

      await tester.tap(find.text('Clear search'));
      await tester.pump();
      expect(find.text('Road Trip'), findsOneWidget);
    });

    testWidgets('defaults to Newest sort (3K.2)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Alpha');
      await service.createPlaylist('Beta');

      await pumpPlaylists(tester, container);
      await tester.pump();

      // Open the sort sheet: Newest is pre-selected by default.
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Newest'),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
        reason: 'Newest is the checked default',
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Oldest'),
          matching: find.byIcon(Icons.radio_button_off),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sort menu reorders by name (3K.2)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Cindy');
      await service.createPlaylist('Aaron');
      await service.createPlaylist('Bella');

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name (A-Z)'));
      await tester.pumpAndSettle();

      final aaronY = tester.getTopLeft(find.text('Aaron')).dy;
      final bellaY = tester.getTopLeft(find.text('Bella')).dy;
      final cindyY = tester.getTopLeft(find.text('Cindy')).dy;
      expect(aaronY, lessThan(bellaY));
      expect(bellaY, lessThan(cindyY));
    });

    testWidgets('search and sort combine: query filters, sort orders (3K.2)',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Spring Mix');
      await service.createPlaylist('Winter Mix');
      await service.createPlaylist('Fall Vibes');

      await pumpPlaylists(tester, container);
      await tester.pump();

      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name (Z-A)'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'mix');
      await tester.pump();

      expect(find.text('Spring Mix'), findsOneWidget);
      expect(find.text('Winter Mix'), findsOneWidget);
      expect(find.text('Fall Vibes'), findsNothing);

      final winterY = tester.getTopLeft(find.text('Winter Mix')).dy;
      final springY = tester.getTopLeft(find.text('Spring Mix')).dy;
      expect(winterY, lessThan(springY), reason: 'Z-A keeps "Winter" above "Spring"');
    });
  });

  group('PlaylistDetailScreen', () {
    testWidgets('shows an empty state for a playlist with no songs',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final id = await createPlaylist(tester, container, 'Empty Mix');
      await pumpDetail(tester, container, id);
      await tester.pump();

      expect(find.text('Empty Mix'), findsNWidgets(2)); // AppBar + empty-state header
      expect(find.text('No songs yet'), findsOneWidget);
      expect(
        find.text('Add songs from your library to start building this playlist.'),
        findsOneWidget,
      );
      expect(find.text('Add Songs'), findsOneWidget);
      expect(find.byType(TrackTile), findsNothing);
    });

    testWidgets('shows a not-found state for an unknown id', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpDetail(tester, container, 'does-not-exist');
      await tester.pump();

      expect(find.text('Playlist not found.'), findsOneWidget);
    });

    testWidgets('adds multiple songs through the multi-select picker',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final id = await createPlaylist(tester, container, 'Mix');

      await pumpDetail(tester, container, id);
      await tester.pump();

      await tester.tap(find.text('Add Songs'));
      await tester.pumpAndSettle();

      expect(find.text('Select Songs'), findsOneWidget);
      expect(find.byType(TrackTile), findsNWidgets(3));

      // Select Song a and Song c; leave Song b unchecked.
      await tester.tap(find.text('Song a'));
      await tester.tap(find.text('Song c'));
      await tester.pump();

      expect(find.text('Add 2 Songs'), findsOneWidget);
      await tester.tap(find.text('Add 2 Songs'));
      await tester.pumpAndSettle();

      // Back on the detail screen, both selected songs are listed in order.
      expect(find.byType(PlaylistDetailScreen), findsOneWidget);
      final service = container.read(playlistServiceProvider);
      expect(service.tracksForPlaylist(id).map((t) => t.id), ['a', 'c']);
      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Song c'), findsOneWidget);
      expect(find.text('Song b'), findsNothing);
    });

    testWidgets('lists the playlist songs with play controls', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      await pumpDetail(tester, container, id);
      await tester.pump();

      expect(find.text('Mix'), findsOneWidget);
      expect(find.textContaining('3 songs'), findsOneWidget);
      expect(find.byType(TrackTile), findsNWidgets(3));
      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
      expect(find.text('Song c'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
    });

    testWidgets('Play starts the playlist at the first song', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      await pumpDetail(tester, container, id);
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.currentTrack?.id, 'a');
      expect(state.queue.map((t) => t.id), ['a', 'b', 'c']);
      expect(state.isPlaying, isTrue);
    });

    testWidgets('Shuffle plays the playlist in shuffled mode', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      await pumpDetail(tester, container, id);
      await tester.pump();
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.queue.map((t) => t.id).toSet(), {'a', 'b', 'c'});
      expect(state.shuffleEnabled, isTrue);
    });

    testWidgets('removes a song from the playlist', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      await pumpDetail(tester, container, id);
      await tester.pump();

      await tester.tap(find.byTooltip('Playlist item options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from playlist'));
      await tester.pumpAndSettle();

      expect(find.byType(TrackTile), findsNWidgets(2));
      expect(service.tracksForPlaylist(id).map((t) => t.id), ['a', 'b']);
      expect(find.text('Song c'), findsNothing);
    });

    testWidgets('renames the playlist from the AppBar', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Old');

      await pumpDetail(tester, container, id);
      await tester.pump();

      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();

      // AppBar + empty-state header both render the playlist name.
      expect(find.text('Renamed'), findsNWidgets(2));
      expect(service.getPlaylist(id)?.name, 'Renamed');
    });

    testWidgets('detail header offers Play/Shuffle/Play Next/Add to Queue (spec 20)',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      await pumpDetail(tester, container, id);
      await tester.pump();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.byTooltip('Playlist actions'), findsNothing);
      expect(find.byTooltip('Add songs'), findsOneWidget);
      expect(find.byTooltip('Rename'), findsOneWidget);
    });

    testWidgets('header Play Next inserts the playlist after the current '
        'track (3K.4)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      // Play something else first so "current" is not the playlist's first song.
      container
          .read(playerNotifierProvider.notifier)
          .setQueue([testTrack('c')]);

      await pumpDetail(tester, container, id);
      await tester.pump();

      await tester.tap(find.text('Play Next'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.currentTrack?.id, 'c', reason: 'playback is untouched');
      expect(state.queue.map((t) => t.id), ['c', 'a', 'b', 'c']);
    });

    testWidgets('header Add to Queue appends the playlist at the end (3K.5)',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final id = await createPlaylist(tester, container, 'Mix');
      for (final t in libraryTracks) {
        await service.addTrackToPlaylist(id, t);
      }

      container
          .read(playerNotifierProvider.notifier)
          .setQueue([testTrack('c')]);

      await pumpDetail(tester, container, id);
      await tester.pump();

      await tester.tap(find.text('Add to Queue'));
      await tester.pumpAndSettle();

      final state = container.read(playerNotifierProvider);
      expect(state.currentTrack?.id, 'c');
      expect(state.queue.map((t) => t.id), ['c', 'a', 'b', 'c']);
    });
  });

  group('HomeScreen', () {
    Future<void> pumpHome(
      WidgetTester tester,
      ProviderContainer container,
    ) {
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
    }

    testWidgets('shows a "Your Playlists" row with song counts and See all',
        (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final playlist = await service.createPlaylist('Road Trip');
      await service.addTrackToPlaylist(playlist.id, testTrack('a'));
      await service.addTrackToPlaylist(playlist.id, testTrack('b'));

      await pumpHome(tester, container);
      await tester.pump();

      expect(find.text('Your Playlists'), findsOneWidget);
      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.text('2 songs'), findsOneWidget);

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistsScreen), findsOneWidget);
    });

    testWidgets('hides the playlists row when none exist', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await pumpHome(tester, container);
      await tester.pump();

      expect(find.text('Your Playlists'), findsNothing);
    });

    testWidgets(
        'shows Recently Played + All Playlists sections only when playlist '
        'history exists (spec 22)', (tester) async {
      final history = NoopPlaylistHistoryRepository();
      final container = buildContainer(history: history);
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      final workout = await service.createPlaylist('Workout');
      final study = await service.createPlaylist('Study');
      await history.recordPlay(workout.id);
      await history.recordPlay(workout.id);
      await history.recordPlay(study.id);

      await pumpPlaylists(tester, container);
      await tester.pump();
      await tester.pump();

      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('All Playlists'), findsOneWidget);
      // Each playlist appears once in the recent section and once under All.
      expect(find.text('Workout'), findsNWidgets(2));
      expect(find.text('Study'), findsNWidgets(2));

      // History order = most-played first (Workout sits above Study).
      expect(
        tester.getTopLeft(find.text('Workout').first).dy,
        lessThan(tester.getTopLeft(find.text('Study').first).dy),
      );
    });

    testWidgets(
        'renders a flat list (no sections) when no playlist history exists '
        '(spec 22)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(playlistServiceProvider);
      await service.createPlaylist('Mix');

      await pumpPlaylists(tester, container);
      await tester.pump();
      await tester.pump();

      expect(find.text('Recently Played'), findsNothing);
      expect(find.text('All Playlists'), findsNothing);
      expect(find.text('Mix'), findsOneWidget);
    });
  });

  group('PlaylistSort ordering (3K.2)', () {
    Playlist p(String id, String name, DateTime created) {
      return Playlist(id: id, name: name, createdAt: created);
    }

    final old = p('1', 'Zeta', DateTime(2024, 1, 1));
    final mid = p('2', 'Alpha', DateTime(2025, 6, 15));
    final fresh = p('3', 'Mid', DateTime(2026, 9, 12));

    test('newest orders by descending createdAt', () {
      expect(
        sortedPlaylists([old, mid, fresh], PlaylistSort.newest).map((x) => x.id),
        ['3', '2', '1'],
      );
    });

    test('oldest orders by ascending createdAt', () {
      expect(
        sortedPlaylists([fresh, mid, old], PlaylistSort.oldest).map((x) => x.id),
        ['1', '2', '3'],
      );
    });

    test('nameAZ sorts case-insensitively by name', () {
      expect(
        sortedPlaylists([fresh, old, mid], PlaylistSort.nameAZ)
            .map((x) => x.name),
        ['Alpha', 'Mid', 'Zeta'],
      );
    });

    test('nameZA reverses the name order', () {
      expect(
        sortedPlaylists([mid, old, fresh], PlaylistSort.nameZA)
            .map((x) => x.name),
        ['Zeta', 'Mid', 'Alpha'],
      );
    });

    test('never mutates the input list', () {
      final input = [old, mid, fresh];
      sortedPlaylists(input, PlaylistSort.nameZA);
      expect(input.map((x) => x.id), ['1', '2', '3']);
    });
  });
}