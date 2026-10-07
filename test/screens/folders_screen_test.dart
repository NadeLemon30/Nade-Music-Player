import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/screens/library/folders_screen.dart';
import 'package:test_app/widgets/track_tile.dart';

void main() {
  final sampleTracks = [
    const Track(
      id: 't0',
      title: 'Loose Track',
      artist: 'Linkin Park',
      album: '',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 1, seconds: 1),
      filePath: '/storage/emulated/0/Music/Linkin Park/loose.mp3',
      fileName: 'loose.mp3',
      fileSize: null,
      mimeType: null,
    ),
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
  ];

  Future<void> pumpFolders(WidgetTester tester, MockMusicRepository repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: FoldersScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('FoldersScreen shows the initial path directory contents',
      (WidgetTester tester) async {
    final repo = MockMusicRepository(sampleTracks);
    await pumpFolders(tester, repo);

    // Initial path is dirname of first available track: Linkin Park
    expect(find.text('Linkin Park'), findsAtLeastNWidgets(1));
    expect(
      find.text('/storage/emulated/0/Music/Linkin Park'),
      findsOneWidget,
    );

    // Subfolders and loose file
    expect(find.text('Folders (2)'), findsOneWidget);
    expect(find.text('Hybrid Theory'), findsOneWidget);
    expect(find.text('Meteora'), findsOneWidget);

    expect(find.text('Files (1)'), findsOneWidget);
    expect(find.text('Loose Track'), findsOneWidget);
  });

  testWidgets('FoldersScreen drills into a subfolder showing its tracks',
      (WidgetTester tester) async {
    final repo = MockMusicRepository(sampleTracks);
    await pumpFolders(tester, repo);

    await tester.tap(find.text('Hybrid Theory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hybrid Theory'), findsAtLeastNWidgets(1));
    expect(find.text('Files (2)'), findsOneWidget);
    expect(find.text('Papercut'), findsOneWidget);
    expect(find.text('One Step Closer'), findsOneWidget);
    expect(find.byType(TrackTile), findsNWidgets(2));
  });

  testWidgets('FoldersScreen empty shows "No music found"',
      (WidgetTester tester) async {
    final repo = MockMusicRepository([]);
    await pumpFolders(tester, repo);

    expect(find.text('No music found'), findsOneWidget);
  });

  testWidgets(
      'folder row offers Play/Shuffle/Add to Queue/Add to Playlist but no Play Next',
      (WidgetTester tester) async {
    final repo = MockMusicRepository(sampleTracks);
    await pumpFolders(tester, repo);

    expect(find.byTooltip('Folder options'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Folder options').first);
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Add to Playlist'), findsOneWidget);
    expect(find.text('Play Next'), findsNothing);
  });
}
