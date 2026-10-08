import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/repositories/music_repository.dart';
import 'package:nades_music_player/main.dart';

void main() {
  testWidgets('MusicPlayerApp UI smoke test', (WidgetTester tester) async {
    final mockRepo = MockMusicRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MusicPlayerApp(),
      ),
    );

    // Pump frames to render UI
    await tester.pump();

    // Verify Library Screen presence
    expect(find.text('Music Library'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recently Played'), findsOneWidget);

    // Scroll to reveal the remaining lazily-built content in spec 11 order.
    await tester.scrollUntilVisible(
      find.text('Playlists'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Playlists'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recently Added'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Recently Added'), findsOneWidget);
  });
}
