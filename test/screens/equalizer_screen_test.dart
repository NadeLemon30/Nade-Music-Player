import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/controllers/audio_effects_controller.dart';
import 'package:test_app/models/audio_effects.dart';
import 'package:test_app/player/player_controller.dart';
import 'package:test_app/screens/player/equalizer_screen.dart';
import 'package:test_app/services/audio_effects/audio_effects_service.dart';
import 'package:test_app/services/audio_effects/native_effects_bridge.dart';


import '../helpers/fake_audio_effects.dart';
import '../helpers/fake_audio_player_service.dart';

void main() {
late FakeAudioEffectsBackend backend;
  late FakeNativeEffectsBridge nativeBridge;
  late AudioEffectsService service;
  late ProviderContainer container;

  /// The player would report this once a track is playing. Without it the
  /// preamp cannot exist at all (an `AudioEffect` needs a live audio session),
  /// so it would show a waiting state instead of its slider.
  late StreamController<int?> sessions;

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [audioEffectsServiceProvider.overrideWith((ref) => service)],
    );
  }

/// Simulates the player reporting an audio session, which is what makes the
  /// native effects (preamp, bass boost, virtualizer) usable.
  ///
  /// Nothing is awaited here on purpose: the caller follows with `settle`, whose
  /// pumps flush the microtasks the push runs on. A real `Future.delayed` would
  /// never fire under `testWidgets`' fake clock.
  void bindSession([int sessionId = 5]) {
    service.bindSessionIdStream(sessions.stream);
    sessions.add(sessionId);
  }



Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EqualizerScreen()),
      ),
    );
    // The service restores + resolves its band layout asynchronously, so let the
    // microtasks run and rebuild.
    await settle(tester);
    // Then the player reports its audio session, which is what the native
    // effects (preamp, bass boost, virtualizer) need before they can exist.
    bindSession();
    await settle(tester);
  }


  setUp(() {
    backend = FakeAudioEffectsBackend();
    nativeBridge = FakeNativeEffectsBridge();
    sessions = StreamController<int?>.broadcast(sync: true);
    service = AudioEffectsService(
      backend: backend,
      nativeBridge: nativeBridge,
      // Widget tests must not leave the slider-throttle window (spec §24) pending
      // at the end of a test, so the window closes immediately here.
      delay: (duration, action) {
        action();
        return Future<void>.value();
      },
    );
  });

tearDown(() async {
    container.dispose();
    await service.dispose();
    await sessions.close();
  });

  testWidgets('renders a slider for every band the backend reports',
      (tester) async {
container = buildContainer();
    await pumpScreen(tester);

    expect(find.widgetWithText(AppBar, 'Equalizer'), findsOneWidget);

    expect(find.text('Preset'), findsOneWidget);
    // 5 band sliders + preamp. The bass boost / virtualizer sliders only appear
    // once the native bridge reports support (i.e. with a live audio session).
    expect(find.byType(Slider), findsNWidgets(6));
    expect(find.text('60'), findsOneWidget);
    expect(find.text('14k'), findsOneWidget);
  });

  testWidgets('offers every built-in preset the bands can take', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    for (final preset in eqPresets) {
      expect(
        find.widgetWithText(ChoiceChip, preset.label),
        findsOneWidget,
        reason: '${preset.label} should be offered on a 5-band equalizer',
      );
    }
    expect(find.byType(ChoiceChip), findsNWidgets(eqPresets.length));
  });

  testWidgets('rebuilds the layout for a different band count', (tester) async {
    backend.config = EqBandsConfig(
      supported: true,
      minDecibels: -10,
      maxDecibels: 10,
      bands: const [
        EqBand(index: 0, centerFrequency: 100, lowerFrequency: 20, upperFrequency: 500),
        EqBand(index: 1, centerFrequency: 1000, lowerFrequency: 500, upperFrequency: 4000),
        EqBand(index: 2, centerFrequency: 10000, lowerFrequency: 4000, upperFrequency: 20000),
      ],
    );
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(find.text('100'), findsOneWidget);
    expect(find.text('10k'), findsOneWidget);
    expect(find.text('60'), findsNothing);
    // The gain range comes from the backend (spec §6), so the dB scale shows
    // ±10 — never a hard-coded ±12.
    expect(find.text('+10 dB'), findsOneWidget);
    expect(find.text('-10 dB'), findsOneWidget);
    expect(find.text('+12 dB'), findsNothing);
    expect(find.text('-12 dB'), findsNothing);
  });

  testWidgets('hides presets that cannot be applied to the reported bands',
      (tester) async {
    backend.config = EqBandsConfig(
      supported: true,
      minDecibels: -12,
      maxDecibels: 12,
      bands: const [
        EqBand(index: 0, centerFrequency: 100, lowerFrequency: 20, upperFrequency: 500),
        EqBand(index: 1, centerFrequency: 1000, lowerFrequency: 500, upperFrequency: 4000),
        EqBand(index: 2, centerFrequency: 10000, lowerFrequency: 4000, upperFrequency: 20000),
      ],
    );
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(
        find.textContaining('No presets fit this device'),
        findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('shows a waiting message until the bands are known',
      (tester) async {
    backend.resolveBandsImmediately = false;
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();

    expect(
      find.textContaining('Band information appears'),
      findsOneWidget,
    );
    expect(find.text('Preset'), findsNothing);

    // Once the platform reports its layout the sliders appear.
    // `runAsync` escapes the test's fake clock so the pending future the service
    // is awaiting actually completes.
    await tester.runAsync(() async {
      backend.resolveBands();
      await Future<void>.delayed(Duration.zero);
    });
    await settle(tester);

    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
  });

  testWidgets('an unsupported backend disables the controls', (tester) async {
    backend.config = EqBandsConfig.unsupported;
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(
      find.text('The equalizer is not available on this device.'),
      findsOneWidget,
    );
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).onChanged, isNull);
  });

  testWidgets('the equalizer switch toggles the backend', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();

    expect(find.text('On'), findsOneWidget);
    expect(backend.equalizerEnabled, isTrue);
  });

  testWidgets('band sliders are disabled while the equalizer is off',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);

    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();

    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNotNull);
  });

  testWidgets('tapping a preset chip applies the curve to the backend',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bass Booster'));

    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bass Booster'));

    await tester.pump();
    await settle(tester);
    await tester.pump();

    expect(
      container.read(audioEffectsControllerProvider).presetId,
      'bass_booster',
    );
    expect(
      backend.bandGains[0],
      greaterThan(backend.bandGains[4] ?? 0),
    );
  });

  testWidgets('a custom curve switches the chip row to Custom',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bass Booster'));

    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bass Booster'));

    await tester.pump();
    await settle(tester);
    await tester.pump();
    expect(find.widgetWithText(Chip, 'Custom'), findsNothing);

    await service.setBandGain(1, 4);
    await settle(tester);
    await tester.pump();

    expect(find.widgetWithText(Chip, 'Custom'), findsOneWidget);
  });

  testWidgets('the equalizer screen owns only the equalizer', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Equalizer'), findsOneWidget);
    expect(find.text('Preamp'), findsOneWidget);
    // The native effects moved to the audio-effects hub (spec §14).
    expect(find.text('Bass Boost'), findsNothing);
    expect(find.text('Virtualizer'), findsNothing);
  });

  testWidgets('bypassing the equalizer keeps the stored curve (spec §11)',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    // The preset row can scroll the list, so bring the switch back into view
    // before tapping it.
    Future<void> tapEqSwitch() async {
      await tester.ensureVisible(find.byType(SwitchListTile).first);
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile).first);
      await settle(tester);
      await tester.pump();
    }

    // Engage first (the chips are only live while the equalizer is engaged), then
    // shape the curve, then bypass it.
    await tapEqSwitch();
    expect(
      container.read(audioEffectsControllerProvider).equalizerEnabled,
      isTrue,
    );

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Rock'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rock'));
    await settle(tester);
    await tester.pump();
    await service.setPreampGain(5);
    await settle(tester);

    await tapEqSwitch();

    final bypassed = container.read(audioEffectsControllerProvider);
    expect(bypassed.equalizerEnabled, isFalse);
    // The preset, the band gains and the preamp all survive the bypass.
    expect(bypassed.presetId, 'rock');
    expect(bypassed.bandGains, isNot(everyElement(0)));
    expect(bypassed.preampDb, 5);

    await tapEqSwitch();

    final reEngaged = container.read(audioEffectsControllerProvider);
    expect(reEngaged.equalizerEnabled, isTrue);
    expect(reEngaged.presetId, bypassed.presetId);
    expect(reEngaged.bandGains, bypassed.bandGains);
    expect(reEngaged.preampDb, 5);
  });

  // The preamp is a separate effect with its own engage switch and its own
  // range: Android's loudness enhancer documents 0 dB as "no amplification" and
  // only ever boosts, so it must not be wired to the equalizer's switch or the
  // bands' symmetric ±12 dB range.
  testWidgets('the preamp has its own switch and its own range', (tester) async {
    // The device reports a narrower preamp range than the platform's 0…+20 dB.
    nativeBridge.support = const NativeEffectsSupport(
      preamp: true,
      preampMinDb: 0,
      preampMaxDb: 12,
      bassBoost: true,
      virtualizer: true,
      bassBoostStrengthSupported: true,
      virtualizerStrengthSupported: true,
    );
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    // The equalizer switch is first; the preamp's is the second.
    expect(find.byType(SwitchListTile), findsNWidgets(2));

    final preampSlider = find.byType(Slider).last;
    expect(tester.widget<Slider>(preampSlider).min, 0);
    expect(tester.widget<Slider>(preampSlider).max, 12);

    // Enabling the equalizer must not enable the preamp.
    await tester.ensureVisible(find.byType(SwitchListTile).first);
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();
    final controller = container.read(audioEffectsControllerProvider);
    expect(controller.equalizerEnabled, isTrue);
    expect(controller.preampEnabled, isFalse);
  });

  testWidgets('the preamp switch engages it independently of the equalizer',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    Future<void> tapPreampSwitch() async {
      await tester.ensureVisible(find.byType(SwitchListTile).last);
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile).last);
      await settle(tester);
      await tester.pump();
    }

    // The preamp switch is off and the equalizer stays off.
    await tapPreampSwitch();

    final engaged = container.read(audioEffectsControllerProvider);
    expect(engaged.preampEnabled, isTrue);
    expect(engaged.equalizerEnabled, isFalse);
    // The preamp goes through the native side with the live session, and it is
    // genuinely engaged there — not just remembered in the state.
    expect(nativeBridge.lastSessionId, 5);
    expect(nativeBridge.lastPreampEnabled, isTrue);

    // And bypassing it keeps the stored gain (spec §11).
    await service.setPreampGain(7);
    await settle(tester);
    await tapPreampSwitch();

    final bypassed = container.read(audioEffectsControllerProvider);
    expect(bypassed.preampEnabled, isFalse);
    expect(bypassed.preampDb, 7);
    expect(bypassed.equalizerEnabled, isFalse);
    // Bypassed on the native side too, still holding the gain.
    expect(nativeBridge.lastPreampEnabled, isFalse);
    expect(nativeBridge.lastPreampDb, 7);
  });

  testWidgets('an unavailable preamp says so and disables its switch',
      (tester) async {
    nativeBridge.support = const NativeEffectsSupport(
      preamp: false,
      bassBoost: true,
      virtualizer: true,
    );
    container = buildContainer();
    await pumpScreen(tester);
    await settle(tester);

    expect(
      find.text('The preamp is not available on this device.'),
      findsOneWidget,
    );
    final switchListTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile).last,
    );
    expect(switchListTile.onChanged, isNull);
    // The preamp slider is gone; the five band sliders remain.
    expect(find.byType(Slider), findsNWidgets(5));
  });

  testWidgets('before any playback the preamp waits instead of claiming the '
      'device has none', (tester) async {
    // An `AudioEffect` cannot be constructed before the player owns a session,
    // so "not asked yet" must not read as "not available" (which is what told
    // users their phone had no preamp when they simply had not played a song).
    container = buildContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EqualizerScreen()),
      ),
    );
    await settle(tester);

    expect(
      find.text('The preamp becomes available once music is playing.'),
      findsOneWidget,
    );
    expect(
      find.text('The preamp is not available on this device.'),
      findsNothing,
    );
    // And it becomes a real, adjustable control once the session exists.
    bindSession();
    await settle(tester);

    expect(
      find.text('The preamp becomes available once music is playing.'),
      findsNothing,
    );
    expect(find.byType(Slider), findsNWidgets(6));
  });

  // Spec §23: a slider change is a single band-gain update — the player is
  // never rebuilt and the current track is never reloaded.
  // Spec §24: the UI follows the slider immediately, the effect update is
  // coalesced so a fast drag cannot flood the platform.
  testWidgets('dragging a band slider updates the effect without touching the '
      'player (specs §23/§24)', (tester) async {
    // A manual "timer" lets this test decide when the coalescing window closes,
    // so the drag's updates can be counted deterministically.
    final scheduled = <void Function()>[];
    service = AudioEffectsService(
      backend: backend,
      nativeBridge: nativeBridge,
      delay: (duration, action) {
        scheduled.add(action);
        return Future<void>.value();
      },
    );
    final player = FakeAudioPlayerService();
    addTearDown(player.dispose);
    container = ProviderContainer(
      overrides: [
        audioEffectsServiceProvider.overrideWith((ref) => service),
        audioPlayerServiceProvider.overrideWithValue(player),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EqualizerScreen()),
      ),
    );
    await settle(tester);
    bindSession();
    await settle(tester);
    backend.calls.clear();
    nativeBridge.calls.clear();

    // The band sliders are only live while the equalizer is engaged.
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    backend.calls.clear();

    // Drag the first band slider across its travel.
    await tester.drag(find.byType(Slider).first, const Offset(0, -300));
    await settle(tester);

    // The UI state followed the drag straight away (spec §24).
    final state = container.read(audioEffectsControllerProvider);
    expect(state.bandGains.first, isNot(0));

    // The platform saw the leading update only; the rest of the drag is
    // still waiting behind the window.
    final bandCalls = backend.calls
        .where((call) => call.startsWith('setBandGain('))
        .toList();
    expect(bandCalls, hasLength(1));
    expect(bandCalls.single, startsWith('setBandGain(0, '));
    // No other part of the effect chain was touched by the drag.
    expect(
      backend.calls.where((call) => !call.startsWith('setBandGain(')),
      isEmpty,
    );

    // Closing the window sends the drag's final value, still only for band 0.
    for (final close in List<void Function()>.from(scheduled)) {
      close();
    }
    await settle(tester);
    expect(
      backend.calls
          .where((call) => call.startsWith('setBandGain('))
          .length,
      lessThanOrEqualTo(2),
    );

    // Nothing rebuilt the player or reloaded the current track (spec §23).
    expect(player.setFileCount, 0);
    expect(player.loadedPath, isNull);
    expect(player.playCount, 0);
    expect(player.pauseCount, 0);
    expect(player.stopCount, 0);
  });
}

/// Elapses a little fake time so pending microtasks (the service's restore and
/// band query) always run, then rebuilds. A bare `tester.pump()` only flushes
/// microtasks when a frame happens to be scheduled, which makes these async
/// hand-offs flaky.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}


