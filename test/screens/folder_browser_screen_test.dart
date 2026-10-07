import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/player/player_controller.dart';
import 'package:test_app/screens/library/folder_browser_screen.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/services/playlists/playlist_service.dart';
import 'package:test_app/widgets/track_tile.dart';

import '../helpers/fake_audio_player_service.dart';

void main() {
  final sampleTracks = [
    // Music/Linkin Park/Hybrid Theory
    const Track(
      id: 't1',
      title: 'Papercut',
      artist: 'Linkin Park',
      album: 'Hybrid Theory',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 5),
      filePath: '/storage/emulated/0/Music/Linkin Park/Hybrid Theory/01 - Papercut.mp3',
      fileName: '01 - Papercut.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't2',
      title: 'One Step Closer',
      artist: 'Linkin Park',
      album: 'Hybrid Theory',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 2, seconds: 35),
      filePath: '/storage/emulated/0/Music/Linkin Park/Hybrid Theory/02 - One Step Closer.mp3',
      fileName: '02 - One Step Closer.mp3',
      fileSize: null,
      mimeType: null,
    ),
    // Music/Linkin Park/Meteora
    const Track(
      id: 't3',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/storage/emulated/0/Music/Linkin Park/Meteora/13 - Numb.mp3',
      fileName: '13 - Numb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    // Music/Daft Punk/Discovery
    const Track(
      id: 't4',
      title: 'One More Time',
      artist: 'Daft Punk',
      album: 'Discovery',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 5, seconds: 20),
      filePath: '/storage/emulated/0/Music/Daft Punk/Discovery/01 - One More Time.mp3',
      fileName: '01 - One More Time.mp3',
      fileSize: null,
      mimeType: null,
    ),
    // Music/Various Artists (Metadata: Linkin Park, but FilePath: Various Artists)
    const Track(
      id: 't5',
      title: 'In the End (Remix)',
      artist: 'Linkin Park',
      album: 'Reanimation',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 40),
      filePath: '/storage/emulated/0/Music/Various Artists/in_the_end_remix.mp3',
      fileName: 'in_the_end_remix.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  testWidgets('FolderBrowserScreen displays normalized root folders based on filePath',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Root shows normalized top-level folders (technical /storage/emulated/0
    // prefix hidden, so we surface the first meaningful folder under Music).
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Folders (3)'), findsOneWidget);

    // Top-level folders derived strictly from physical file paths:
    // Linkin Park, Daft Punk, Various Artists
    expect(find.text('Linkin Park'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
    expect(find.text('Various Artists'), findsOneWidget);
  });

  testWidgets('Navigating into a subfolder opens child directories and tracks',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(
            folderPath: '/storage/emulated/0/Music/Linkin Park',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Current folder header
    expect(find.text('Linkin Park'), findsAtLeastNWidgets(1));
    expect(find.text('Folders (2)'), findsOneWidget);

    // Child directories
    expect(find.text('Hybrid Theory'), findsOneWidget);
    expect(find.text('Meteora'), findsOneWidget);

    // Physical path label is shown
    expect(
      find.text('/storage/emulated/0/Music/Linkin Park'),
      findsOneWidget,
    );
  });

  testWidgets('Navigating into a leaf folder displays direct audio files with TrackTiles',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(
            folderPath: '/storage/emulated/0/Music/Linkin Park/Hybrid Theory',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hybrid Theory'), findsAtLeastNWidgets(1));
    expect(find.text('Files (2)'), findsOneWidget);

    // Direct tracks
    expect(find.text('Papercut'), findsOneWidget);
    expect(find.text('One Step Closer'), findsOneWidget);
    expect(find.byType(TrackTile), findsNWidgets(2));
  });

  testWidgets('Folder browser strictly uses filePath: track in Various Artists stays in Various Artists',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(
            folderPath: '/storage/emulated/0/Music/Various Artists',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Various Artists'), findsAtLeastNWidgets(1));
    expect(find.text('Files (1)'), findsOneWidget);
    expect(find.text('In the End (Remix)'), findsOneWidget);
  });

  testWidgets('FolderBrowserScreen displays empty state when no files exist',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository([]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No music folders found'), findsOneWidget);
    expect(find.text('Scan Storage'), findsOneWidget);
  });

  testWidgets('Add Folder to Playlist offers the folder contents recursively',
      (tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
          audioPlayerServiceProvider.overrideWithValue(FakeAudioPlayerService()),
          playHistoryServiceProvider
              .overrideWith((ref) => NoopPlayHistoryService()),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(
          home: FolderBrowserScreen(
            folderPath: '/storage/emulated/0/Music/Linkin Park',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip('Add Folder to Playlist'), findsOneWidget);

    await tester.tap(find.byTooltip('Add Folder to Playlist'));
    await tester.pumpAndSettle();

    // Recursive contents: Hybrid Theory (t1, t2) + Meteora (t3).
    expect(find.text('Choose Playlist'), findsOneWidget);
    expect(find.text('3 songs selected'), findsOneWidget);
  });
}
