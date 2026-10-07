import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/player/player_controller.dart';
import 'package:test_app/screens/queue/queue_screen.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/widgets/track_tile.dart';

import '../helpers/fake_audio_player_service.dart';

void main() {
  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(FakeAudioPlayerService()),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
        favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
      ],
    );
  }

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: QueueScreen()),
      ),
    );
  }

  testWidgets('shows an empty state when the queue is empty', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.text('Queue is empty'), findsOneWidget);
  });

  testWidgets('splits the queue into Playing and Up Next sections',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a'), testTrack('b'), testTrack('c')],
            autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.text('Playing'), findsOneWidget);
    expect(find.text('Up Next'), findsOneWidget);
    expect(find.byType(TrackTile), findsNWidgets(3));
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);
    expect(find.text('Song c'), findsOneWidget);
    expect(find.text('2 songs'), findsOneWidget);
    expect(find.text('Clear Queue'), findsOneWidget);
  });

  testWidgets('tapping the playing track toggles play and pause',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final player = container.read(playerNotifierProvider.notifier);
    await player.setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(container.read(playerNotifierProvider).isPlaying, isTrue);

    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(container.read(playerNotifierProvider).isPlaying, isFalse);
  });

  testWidgets('jumps to an up-next track and removes queued entries',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final player = container.read(playerNotifierProvider.notifier);
    await player.setQueue(
      [testTrack('a'), testTrack('b'), testTrack('c')],
      autoPlay: false,
    );
    await pumpScreen(tester, container);
    await tester.pump();

    // Jump to the second track: it becomes the pinned Playing entry.
    await tester.tap(find.text('Song b'));
    await tester.pumpAndSettle();

    var state = container.read(playerNotifierProvider);
    expect(state.currentIndex, 1);
    expect(state.currentTrack?.id, 'b');

    // The remaining up-next entry (Song c) can now be removed.
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from queue'));
    await tester.pumpAndSettle();

    state = container.read(playerNotifierProvider);
    expect(state.queue.map((t) => t.id), ['a', 'b']);
    expect(state.currentIndex, 1);
    expect(find.text('Nothing up next'), findsOneWidget);
  });

  testWidgets('reorders an up-next track via its drag handle', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final player = container.read(playerNotifierProvider.notifier);
    await player.setQueue(
      [testTrack('a'), testTrack('b'), testTrack('c'), testTrack('d')],
      autoPlay: false,
    );
    await pumpScreen(tester, container);
    await tester.pump();

    // Up next is b, c, d; drag the last handle (Song d) above Song b.
    final handle = find.byIcon(Icons.drag_handle).at(2);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final state = container.read(playerNotifierProvider);
    expect(state.queue.map((t) => t.id), ['a', 'd', 'b', 'c']);
    expect(state.currentIndex, 0);
    expect(state.currentTrack?.id, 'a');
  });

  testWidgets('clears the whole queue from the bottom button', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final player = container.read(playerNotifierProvider.notifier);
    await player.setQueue([testTrack('a'), testTrack('b')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.text('Clear Queue'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Queue is empty'), findsOneWidget);
  });
}