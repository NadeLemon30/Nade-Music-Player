import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/library_controller.dart';
import 'package:nades_music_player/data/repositories/music_repository.dart';
import 'package:nades_music_player/models/album.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/screens/library/album_detail_screen.dart';
import 'package:nades_music_player/screens/library/albums_list_screen.dart';

import '../helpers/fake_library_controller.dart';

void main() {
  // Sample tracks intentionally inserted in non-track-number order to verify discNumber + trackNumber sorting
  final sampleMeteoraTracks = [
    const Track(
      id: 'm_4',
      title: 'Lying from You',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumId: 1,
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: 4,
      discNumber: 1,
      duration: Duration(minutes: 2, seconds: 55),
      filePath: '/music/lying_from_you.mp3',
      fileName: 'lying_from_you.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'm_1',
      title: 'Foreword',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumId: 1,
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: 1,
      discNumber: 1,
      duration: Duration(seconds: 13),
      filePath: '/music/foreword.mp3',
      fileName: 'foreword.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'm_3',
      title: 'Somewhere I Belong',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumId: 1,
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: 3,
      discNumber: 1,
      duration: Duration(minutes: 3, seconds: 33),
      filePath: '/music/somewhere_i_belong.mp3',
      fileName: 'somewhere_i_belong.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'm_2',
      title: "Don't Stay",
      artist: 'Linkin Park',
      album: 'Meteora',
      albumId: 1,
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: 2,
      discNumber: 1,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/music/dont_stay.mp3',
      fileName: 'dont_stay.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  testWidgets('AlbumsListScreen displays albums in a grid',
      (WidgetTester tester) async {
    const meteora = Album(
      id: 1,
      title: 'Meteora',
      albumArtist: 'Linkin Park',
      artistId: 1,
      year: 2003,
      trackCount: 4,
      artworkKey: '1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(LibraryData(albums: [meteora])),
        ],
        child: const MaterialApp(
          home: AlbumsListScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('1 album'), findsOneWidget);
    expect(find.text('Meteora'), findsOneWidget);
    expect(find.text('Linkin Park'), findsOneWidget);
  });

  testWidgets(
      'album grid card offers Play/Shuffle/Play Next/Add to Queue/Add to Playlist',
      (WidgetTester tester) async {
    const meteora = Album(
      id: 1,
      title: 'Meteora',
      albumArtist: 'Linkin Park',
      artistId: 1,
      year: 2003,
      trackCount: 4,
      artworkKey: '1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(LibraryData(
            albums: const [meteora],
            tracks: sampleMeteoraTracks,
          )),
        ],
        child: const MaterialApp(
          home: AlbumsListScreen(),
        ),
      ),
    );

    await tester.pump();

    await tester.tap(find.byTooltip('Album options'));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Add to Playlist'), findsOneWidget);
  });

  testWidgets(
      'AlbumDetailScreen orders tracks by discNumber + trackNumber (not alphabetical)',
      (WidgetTester tester) async {
final mockRepo = MockMusicRepository(sampleMeteoraTracks);
      const meteora = Album(
        id: 1,
        title: 'Meteora',
        albumArtist: 'Linkin Park',
        artistId: 1,
        year: 2003,
        trackCount: 4,
        artworkKey: '1',
      );

      // A tall viewport so all four rows are laid out: the track list is a
      // lazily-built sliver, so the last row is never built in a short test
      // surface and the ordering assertions below cannot see it.
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: AlbumDetailScreen(album: meteora),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Album Header details
    expect(find.text('Meteora'), findsAtLeastNWidgets(1));
    expect(find.text('Linkin Park'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Verify 2-digit track numbers
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('04'), findsOneWidget);

    // Verify Tracks are in exact trackNumber order: 01 Foreword, 02 Don't Stay, 03 Somewhere I Belong, 04 Lying from You
    final forewordPos = tester.getTopLeft(find.text('Foreword')).dy;
    final dontStayPos = tester.getTopLeft(find.text("Don't Stay")).dy;
    final somewherePos = tester.getTopLeft(find.text('Somewhere I Belong')).dy;
    final lyingPos = tester.getTopLeft(find.text('Lying from You')).dy;

    expect(forewordPos < dontStayPos, isTrue,
        reason: 'Foreword (track 1) should be above Don\'t Stay (track 2)');
    expect(dontStayPos < somewherePos, isTrue,
        reason: 'Don\'t Stay (track 2) should be above Somewhere I Belong (track 3)');
    expect(somewherePos < lyingPos, isTrue,
        reason: 'Somewhere I Belong (track 3) should be above Lying from You (track 4)');
  });
}
