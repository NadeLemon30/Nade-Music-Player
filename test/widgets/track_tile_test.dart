import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/widgets/track_options_sheet.dart';
import 'package:nades_music_player/widgets/track_tile.dart';

void main() {
  const testTrack = Track(
    id: 'test_1',
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
  );

  group('TrackTile Tests', () {
    testWidgets('Renders title, artist, album, and formatted duration',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackTile(
              track: testTrack,
              showDivider: true,
            ),
          ),
        ),
      );

      expect(find.text('Numb'), findsOneWidget);
      expect(find.text('Linkin Park'), findsOneWidget);
      expect(find.text('Meteora'), findsOneWidget);
      expect(find.text('03:07'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('Tapping track tile triggers onTap callback',
        (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackTile(
              track: testTrack,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TrackTile));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('Long press opens track options bottom sheet with all required actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TrackTile(
                track: testTrack,
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(TrackTile));
      await tester.pumpAndSettle();

      // Verify bottom sheet actions
      expect(find.text('Play Now'), findsOneWidget);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('View Album (Meteora)'), findsOneWidget);
      expect(find.text('View Artist (Linkin Park)'), findsOneWidget);
      expect(find.text('Track Details'), findsOneWidget);
    });

    testWidgets('Track options callbacks fire correctly when provided',
        (WidgetTester tester) async {
      bool addedToQueue = false;
      bool addedToPlaylist = false;
      bool favorited = false;
      bool viewedAlbum = false;
      bool viewedArtist = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showTrackOptionsSheet(
                  context,
                  testTrack,
                  onAddToQueue: () => addedToQueue = true,
                  onAddToPlaylist: () => addedToPlaylist = true,
                  onFavorite: () => favorited = true,
                  onViewAlbum: () => viewedAlbum = true,
                  onViewArtist: () => viewedArtist = true,
                ),
                child: const Text('Open Options'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      // Test Add to Queue callback
      await tester.tap(find.text('Add to Queue'));
      await tester.pumpAndSettle();
      expect(addedToQueue, isTrue);

      // Reopen sheet for Add to Playlist callback
      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add to Playlist'));
      await tester.pumpAndSettle();
      expect(addedToPlaylist, isTrue);

      // Reopen sheet for Favorite callback
      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();
      expect(favorited, isTrue);

      // Reopen sheet for View Album callback
      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Album (Meteora)'));
      await tester.pumpAndSettle();
      expect(viewedAlbum, isTrue);

      // Reopen sheet for View Artist callback
      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Artist (Linkin Park)'));
      await tester.pumpAndSettle();
      expect(viewedArtist, isTrue);
    });
  });
}
