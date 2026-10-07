import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/controllers/library_controller.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/models/artist.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/screens/library/artist_detail_screen.dart';
import 'package:test_app/screens/library/artists_list_screen.dart';
import 'package:test_app/widgets/track_tile.dart';

import '../helpers/fake_library_controller.dart';

void main() {
  final sampleTracks = [
    const Track(
      id: 't1',
      title: 'Rolling in the Deep',
      artist: 'Adele',
      album: '21',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 48),
      filePath: '/music/adele.mp3',
      fileName: 'adele.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't2',
      title: 'Faded',
      artist: 'Alan Walker',
      album: 'Different World',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 32),
      filePath: '/music/alan_walker.mp3',
      fileName: 'alan_walker.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't3',
      title: 'Do I Wanna Know?',
      artist: 'Arctic Monkeys',
      album: 'AM',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 4, seconds: 32),
      filePath: '/music/am.mp3',
      fileName: 'am.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't4',
      title: 'I Want It That Way',
      artist: 'Backstreet Boys',
      album: 'Millennium',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 33),
      filePath: '/music/bsb.mp3',
      fileName: 'bsb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't5',
      title: 'In the End',
      artist: 'Linkin Park',
      album: 'Hybrid Theory',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 36),
      filePath: '/music/in_the_end.mp3',
      fileName: 'in_the_end.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't6',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/music/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't7',
      title: 'Faint',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 2, seconds: 42),
      filePath: '/music/faint.mp3',
      fileName: 'faint.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 't8',
      title: 'Breaking the Habit',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 16),
      filePath: '/music/breaking_the_habit.mp3',
      fileName: 'breaking_the_habit.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  testWidgets('ArtistsListScreen groups artists alphabetically with section headers',
      (WidgetTester tester) async {
    const artists = [
      Artist(id: 'a1', name: 'Adele', trackCount: 1),
      Artist(id: 'a2', name: 'Alan Walker', trackCount: 1),
      Artist(id: 'a3', name: 'Arctic Monkeys', trackCount: 1),
      Artist(id: 'a4', name: 'Backstreet Boys', trackCount: 1),
      Artist(id: 'a5', name: 'Linkin Park', trackCount: 4),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(LibraryData(artists: artists)),
        ],
        child: const MaterialApp(
          home: ArtistsListScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify app bar
    expect(find.text('Artists'), findsOneWidget);

    // Verify alphabetical section headers. Matched by the header's own
    // text style: artist avatars also render a bare initial letter
    // (Adele, Alan Walker and Arctic Monkeys all contribute an "A"), so a
    // plain text finder matches all four.
    Finder sectionHeader(String letter) => find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == letter &&
              widget.style?.fontWeight == FontWeight.bold &&
              widget.style?.color == Theme.of(
                tester.element(find.byType(ArtistsListScreen)),
              ).colorScheme.primary,
        );

    expect(sectionHeader('A'), findsOneWidget);
    expect(sectionHeader('B'), findsOneWidget);
    expect(sectionHeader('L'), findsOneWidget);

    // Verify artist names
    expect(find.text('Adele'), findsOneWidget);
    expect(find.text('Alan Walker'), findsOneWidget);
    expect(find.text('Arctic Monkeys'), findsOneWidget);
    expect(find.text('Backstreet Boys'), findsOneWidget);
    expect(find.text('Linkin Park'), findsOneWidget);
  });

  testWidgets('Selecting an artist opens ArtistDetailScreen with albums and songs',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleTracks);
    const linkinPark = Artist(
      id: 'linkin_park',
      name: 'Linkin Park',
      trackCount: 4,
    );

    // A tall viewport so all four song rows are laid out: the songs list is a
    // lazily-built sliver, so the trailing rows are never built in a short
    // test surface and the assertions below cannot find them.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: ArtistDetailScreen(artist: linkinPark),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Artist Header
    expect(find.text('Linkin Park'), findsAtLeastNWidgets(1));
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Verify Albums section. Scoped to the albums list, because each song's
    // TrackTile also renders its album name as a subtitle.
    expect(find.text('Albums'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView).last,
        matching: find.text('Hybrid Theory'),
      ),
      findsOneWidget,
    );
    expect(find.text('Meteora'), findsAtLeastNWidgets(1));

    // Verify Songs section
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('In the End'), findsOneWidget);
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('Faint'), findsOneWidget);
    expect(find.text('Breaking the Habit'), findsOneWidget);

    expect(find.byType(TrackTile), findsNWidgets(4));
  });

  testWidgets(
      'artist row offers the collection context menu (Play/Shuffle/Play '
      'Next/Add to Queue/Add to Playlist)', (WidgetTester tester) async {
    const linkinPark = Artist(id: 'lp', name: 'Linkin Park', trackCount: 4);
    const adele = Artist(id: 'adele', name: 'Adele', trackCount: 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(LibraryData(
            artists: const [linkinPark, adele],
            tracks: sampleTracks,
          )),
        ],
        child: const MaterialApp(
          home: ArtistsListScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.tap(find.byTooltip('Artist options').first);
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Add to Playlist'), findsOneWidget);
  });
}
