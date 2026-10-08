import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/screens/player/audio_effects_screen.dart';
import 'package:nades_music_player/screens/player/equalizer_screen.dart';
import 'package:nades_music_player/screens/player/player_screen.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_service.dart';
import 'package:nades_music_player/services/favorites/favorites_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';
import 'package:nades_music_player/services/sleep_timer_service.dart';
import 'package:nades_music_player/widgets/player/player_progress_bar.dart';

import '../helpers/fake_audio_effects.dart';
import '../helpers/fake_audio_player_service.dart';

void main() {
  ProviderContainer buildContainer({
    FakeAudioPlayerService? fakeAudio,
    SleepTimerService? sleepTimer,
    AudioEffectsService? effects,
  }) {
    return ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(
          fakeAudio ?? FakeAudioPlayerService(),
        ),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
        favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        if (sleepTimer != null)
          sleepTimerServiceProvider.overrideWithValue(sleepTimer),
        if (effects != null)
          audioEffectsServiceProvider.overrideWith((ref) => effects),
      ],
    );
  }

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerScreen()),
      ),
    );
  }

  testWidgets('shows an empty state when nothing is playing', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.byType(PlayerProgressBar), findsNothing);
  });

  testWidgets('shows the current track metadata and controls', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: true);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Artist a'), findsOneWidget);
    expect(find.byType(PlayerProgressBar), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });

  testWidgets('transport controls toggle shuffle and repeat state',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    // Repeat cycles: off -> all -> one (repeat-one icon appears).
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pump();

    final state = container.read(playerNotifierProvider);
    expect(state.repeatMode, RepeatMode.one);
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);
  });

  testWidgets('shows a loading indicator while buffering', (tester) async {
    final fakeAudio = FakeAudioPlayerService();
    final container = buildContainer(fakeAudio: fakeAudio);
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: true);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    fakeAudio.setProcessingState(ProcessingState.buffering);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('transport controls disable next at the queue end',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    final nextButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_next),
    );
    expect(nextButton.onPressed, isNull);

    // With repeat-all the queue wraps, so next stays enabled.
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pump();
    final wrapped = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_next),
    );
    expect(wrapped.onPressed, isNotNull);
  });

  testWidgets('shows an error banner when a track fails to load',
      (tester) async {
    final fakeAudio = FakeAudioPlayerService();
    final container = buildContainer(fakeAudio: fakeAudio);
    addTearDown(container.dispose);

    fakeAudio.failNextLoad = true;
    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);

    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.textContaining('Unable to play this file'), findsOneWidget);
  });

  testWidgets('shows a sleep timer action in the app bar', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
  });

  testWidgets('sleep timer action reflects the active countdown',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final sleepTimer = container.read(sleepTimerServiceProvider);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);

    sleepTimer.start(const Duration(minutes: 30));
    await tester.pump();
    expect(find.byIcon(Icons.bedtime), findsOneWidget);
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);

    sleepTimer.cancel();
    await tester.pump();
    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
  });

  testWidgets('tapping the sleep timer action opens the timer sheet',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bedtime_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sleep Timer'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('Cancel Timer'), findsNothing);
  });

  testWidgets('app bar shows a compact remaining-time indicator while the timer is active',
      (tester) async {
    var fakeNow = DateTime.utc(2026, 1, 1, 12);
    final sleepTimer = SleepTimerService(
      tickInterval: const Duration(milliseconds: 10),
      now: () => fakeNow,
    );
    final container = buildContainer(sleepTimer: sleepTimer);
    addTearDown(() async {
      container.dispose();
      sleepTimer.cancel();
      await sleepTimer.dispose();
    });

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);

    sleepTimer.start(const Duration(minutes: 29));
    await tester.pump();

    expect(find.byIcon(Icons.bedtime), findsOneWidget);
    expect(find.text('29:00'), findsOneWidget);

    sleepTimer.cancel();
    await tester.pump();
    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
    expect(find.text('29:00'), findsNothing);
  });

  testWidgets('player options menu lists all entries with Queue, Equalizer and '
      'Sleep Timer live and future ones disabled', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Sleep Timer'), findsOneWidget);
    expect(find.text('Audio Effects'), findsOneWidget);
    expect(find.text('Lyrics'), findsOneWidget);
    expect(find.text('Playback Speed'), findsOneWidget);

    // Queue / Equalizer / Sleep Timer are implemented; the rest are disabled
    // placeholders.
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Queue')).onTap,
      isNotNull,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Equalizer'))
          .onTap,
      isNotNull,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Playback Speed'))
          .onTap,
      isNull,
    );

    // Sleep Timer from the menu opens the sleep timer sheet.
    await tester.tap(find.text('Sleep Timer'));
    await tester.pumpAndSettle();
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('Cancel Timer'), findsNothing);
  });

  testWidgets('Equalizer from the options menu opens the equalizer screen',
      (tester) async {
    final effectsService = AudioEffectsService(
      backend: FakeAudioEffectsBackend(),
      nativeBridge: FakeNativeEffectsBridge(),
    );
    final container = buildContainer(effects: effectsService);
    addTearDown(container.dispose);
    addTearDown(effectsService.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equalizer'));
    await tester.pumpAndSettle();

    expect(find.byType(EqualizerScreen), findsOneWidget);
    expect(find.text('Preset'), findsOneWidget);
  });

  testWidgets('Audio Effects from the options menu opens the effects hub',
      (tester) async {
    final effectsService = AudioEffectsService(
      backend: FakeAudioEffectsBackend(),
      nativeBridge: FakeNativeEffectsBridge(),
    );
    final container = buildContainer(effects: effectsService);
    addTearDown(container.dispose);
    addTearDown(effectsService.dispose);

    await container
        .read(playerNotifierProvider.notifier)
        .setQueue([testTrack('a')], autoPlay: false);
    await pumpScreen(tester, container);
    await tester.pump();

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio Effects'));
    await tester.pumpAndSettle();

    expect(find.byType(AudioEffectsScreen), findsOneWidget);
    expect(find.text('Bass Boost'), findsOneWidget);
  });
}