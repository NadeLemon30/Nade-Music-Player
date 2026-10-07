import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/player/player_controller.dart';
import 'package:test_app/services/favorites/favorites_service.dart';
import 'package:test_app/services/playback/play_history_service.dart';
import 'package:test_app/services/sleep_timer_service.dart';
import 'package:test_app/widgets/mini_player.dart';

import '../helpers/fake_audio_player_service.dart';

void main() {
  final track = testTrack('a');

  Widget wrap(Widget child) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('shows pause while playing, play while paused', (tester) async {
    await tester.pumpWidget(
      wrap(
        MiniPlayer(
          track: track,
          isPlaying: true,
          onPlayPause: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled), findsNothing);

    await tester.pumpWidget(
      wrap(
        MiniPlayer(
          track: track,
          isPlaying: false,
          onPlayPause: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
  });

  testWidgets('shows a loading indicator instead of play/pause while buffering',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        MiniPlayer(
          track: track,
          isPlaying: false,
          isBuffering: true,
          onPlayPause: () {},
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled), findsNothing);
    expect(find.byIcon(Icons.pause_circle_filled), findsNothing);
  });

  testWidgets('shows a compact bedtime indicator while the sleep timer is active',
      (tester) async {
    var fakeNow = DateTime.utc(2026, 1, 1, 12);
    final sleepTimer = SleepTimerService(
      tickInterval: const Duration(milliseconds: 10),
      now: () => fakeNow,
    );
    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(
          FakeAudioPlayerService(),
        ),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
        favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        sleepTimerServiceProvider.overrideWithValue(sleepTimer),
      ],
    );
    addTearDown(() async {
      container.dispose();
      sleepTimer.cancel();
      await sleepTimer.dispose();
    });

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: ConnectedMiniPlayer(handleBottomInset: false),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.bedtime), findsNothing);

    sleepTimer.start(const Duration(minutes: 29));
    await tester.pump();

    expect(find.byIcon(Icons.bedtime), findsOneWidget);
    expect(find.text('29:00'), findsOneWidget);

    sleepTimer.cancel();
    await tester.pump();
    expect(find.byIcon(Icons.bedtime), findsNothing);
    expect(find.text('29:00'), findsNothing);
  });
}