import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';
import 'package:nades_music_player/widgets/player/player_progress_bar.dart';

import '../helpers/fake_audio_player_service.dart';

void main() {
  ProviderContainer buildContainer({FakeAudioPlayerService? fakeAudio}) {
    return ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(
          fakeAudio ?? FakeAudioPlayerService(),
        ),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
      ],
    );
  }

  Future<void> pumpBar(
    WidgetTester tester,
    ProviderContainer container,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerProgressBar())),
      ),
    );
  }

  testWidgets('shows position and duration', (tester) async {
    final fakeAudio = FakeAudioPlayerService();
    final container = buildContainer(fakeAudio: fakeAudio);
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    fakeAudio.emitDuration(const Duration(minutes: 3));
    await pumpBar(tester, container);
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);

    fakeAudio.emitPosition(const Duration(seconds: 42));
    await tester.pump();
    expect(find.text('00:42'), findsOneWidget);
  });

  testWidgets('seeks only on release, not while dragging', (tester) async {
    final fakeAudio = FakeAudioPlayerService();
    final container = buildContainer(fakeAudio: fakeAudio);
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    fakeAudio.emitDuration(const Duration(minutes: 3));
    fakeAudio.emitPosition(const Duration(minutes: 1));
    await pumpBar(tester, container);
    await tester.pump();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(fakeAudio.lastSeek, isNull);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(fakeAudio.lastSeek, isNotNull);
    expect(fakeAudio.lastSeek!, greaterThan(const Duration(minutes: 1)));
  });

  testWidgets('is disabled when the duration is unknown', (tester) async {
    final fakeAudio = FakeAudioPlayerService();
    final container = buildContainer(fakeAudio: fakeAudio);
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpBar(tester, container);
    await tester.pump();

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(fakeAudio.lastSeek, isNull);
    expect(find.text('00:00'), findsNWidgets(2));
  });
}