import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/controllers/library_controller.dart';
import 'package:test_app/screens/library/library_screen.dart';
import 'package:test_app/screens/library/recently_played_screen.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/services/playlists/playlist_service.dart';

import '../helpers/fake_audio_player_service.dart';
import '../helpers/fake_library_controller.dart';

void main() {
  const expectedEntryOrder = [
    'Songs',
    'Albums',
    'Artists',
    'Folders',
    'Favorites',
    'Recently Played',
    'Playlists',
  ];

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProviderOverride(const LibraryData()),
          playHistoryServiceProvider
              .overrideWith((ref) => NoopPlayHistoryService()),
          favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
          playlistServiceProvider.overrideWithValue(PlaylistService(null)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('lists and orders the spec 11 collections, with no Genres',
      (tester) async {
    await pumpLibrary(tester);

    for (final title in expectedEntryOrder) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Genres'), findsNothing);

    final tops = <double>[];
    for (final title in expectedEntryOrder) {
      tops.add(tester.getTopLeft(find.text(title)).dy);
    }
    for (var i = 1; i < expectedEntryOrder.length; i++) {
      expect(tops[i - 1] < tops[i], isTrue,
          reason: '${expectedEntryOrder[i - 1]} must come before '
              '${expectedEntryOrder[i]}');
    }
  });

  testWidgets('tapping Recently Played opens RecentlyPlayedScreen',
      (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('Recently Played'));
    await tester.pumpAndSettle();

    expect(find.byType(RecentlyPlayedScreen), findsOneWidget);
  });
}