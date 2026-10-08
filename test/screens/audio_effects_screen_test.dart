import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/audio_effects_controller.dart';
import 'package:nades_music_player/models/audio_effects.dart';
import 'package:nades_music_player/screens/player/audio_effects_screen.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_service.dart';
import 'package:nades_music_player/services/audio_effects/native_effects_bridge.dart';

import '../helpers/fake_audio_effects.dart';

/// Spec §14: the audio-effects screen is a short hub — the equalizer (switch plus
/// a jump into the band screen) followed by the two native effects with their own
/// switch and strength slider. Spec §12/§13: an effect the platform does not
/// support is described and disabled, and playback carries on.
void main() {
  late FakeAudioEffectsBackend backend;
  late FakeNativeEffectsBridge nativeBridge;
  late AudioEffectsService service;
  late ProviderContainer container;
  late _SessionIds sessions;

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [audioEffectsServiceProvider.overrideWith((ref) => service)],
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AudioEffectsScreen()),
      ),
    );
    await settle(tester);
  }

  setUp(() {
    backend = FakeAudioEffectsBackend();
    nativeBridge = FakeNativeEffectsBridge();
    service = AudioEffectsService(
      backend: backend,
      nativeBridge: nativeBridge,
    );
    sessions = _SessionIds();
  });

  tearDown(() async {
    container.dispose();
    await sessions.close();
    await service.dispose();
  });

  testWidgets('lists the equalizer and both native effects', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);

    expect(find.widgetWithText(AppBar, 'Audio Effects'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Bass Boost'), findsOneWidget);
    expect(find.text('Virtualizer'), findsOneWidget);
  });

  testWidgets('opens the equalizer screen from the hub', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);

    await tester.tap(find.text('Edit bands and preset'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Equalizer'), findsOneWidget);
    expect(find.text('Preamp'), findsOneWidget);
  });

  testWidgets('the equalizer switch engages and bypasses the equalizer',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.pump();

    expect(backend.calls, contains('setEqualizerEnabled(true)'));
    expect(
      container.read(audioEffectsControllerProvider).equalizerEnabled,
      isTrue,
    );
  });

  testWidgets('an unsupported native effect is described, not applied',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);

    // No session yet: the platform has not reported the effects as usable.
    final bassTile = _tileFor(tester, 'Bass Boost');
    expect(tester.widget<SwitchListTile>(bassTile).onChanged, isNull);
    expect(find.text('Bass Boost unavailable on this device.'), findsOneWidget);
    expect(find.text('Virtualizer unavailable on this device.'), findsOneWidget);
  });

  testWidgets('enabling bass boost forwards the strength to the native side',
      (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();
    service.bindSessionIdStream(sessions.stream);
    sessions.add(1);
    await settle(tester);
    await tester.pump();

    final bassTile = _tileFor(tester, 'Bass Boost');
    expect(tester.widget<SwitchListTile>(bassTile).onChanged, isNotNull);

    await tester.tap(bassTile);
    await settle(tester);
    await tester.pump();

    expect(nativeBridge.lastBassBoostEnabled, isTrue);
    expect(
      container.read(audioEffectsControllerProvider).bassBoostEnabled,
      isTrue,
    );
  });

  testWidgets('a device-specific strength range is shown to the user',
      (tester) async {
    nativeBridge.support = const NativeEffectsSupport(
      bassBoost: true,
      virtualizer: true,
      bassBoostStrengthSupported: true,
      virtualizerStrengthSupported: true,
      bassBoostRange: StrengthRange(min: 0, max: 500),
      virtualizerRange: StrengthRange(min: 250, max: 1000),
    );
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();
    service.bindSessionIdStream(sessions.stream);
    sessions.add(1);
    await settle(tester);
    await tester.pump();

    expect(find.text('Device strength range: 0\u2013500'), findsOneWidget);
    expect(find.text('Device strength range: 250\u20131000'), findsOneWidget);
  });

  testWidgets('an effect whose strength is not adjustable keeps its switch',
      (tester) async {
    nativeBridge.support = const NativeEffectsSupport(
      bassBoost: true,
      virtualizer: false,
      bassBoostStrengthSupported: false,
    );
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();
    service.bindSessionIdStream(sessions.stream);
    sessions.add(1);
    await settle(tester);
    await tester.pump();

    // The effect itself is switchable, but no strength slider is offered.
    final bassTile = _tileFor(tester, 'Bass Boost');
    expect(tester.widget<SwitchListTile>(bassTile).onChanged, isNotNull);
    expect(
      find.text("This device doesn't let the Bass Boost strength be adjusted."),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNothing);

    await tester.tap(bassTile);
    await settle(tester);
    await tester.pump();
    expect(nativeBridge.lastBassBoostEnabled, isTrue);
  });

  testWidgets('the reset action restores the defaults', (tester) async {
    container = buildContainer();
    await pumpScreen(tester);
    await tester.pump();
    service.bindSessionIdStream(sessions.stream);
    sessions.add(1);
    await settle(tester);
    await tester.pump();

    await tester.tap(_tileFor(tester, 'Bass Boost'));
    await settle(tester);
    await tester.pump();
    await service.setVirtualizer(0.8);
    await settle(tester);

    await tester.tap(find.byTooltip('Reset audio effects'));
    await settle(tester);
    await tester.pump();

    final state = container.read(audioEffectsControllerProvider);
    expect(state.presetId, eqNormalPreset.id);
    expect(state.bassBoostEnabled, isFalse);
    expect(state.virtualizerStrength, 0);
  });
}

/// The [SwitchListTile] that carries [title].
Finder _tileFor(WidgetTester tester, String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(SwitchListTile),
    );

class _SessionIds {
  final _controller = StreamController<int?>.broadcast(sync: true);

  Stream<int?> get stream => _controller.stream;

  void add(int? id) => _controller.add(id);

  Future<void> close() => _controller.close();
}

/// Elapses a little fake time so pending microtasks (the service's restore, band
/// query and native apply) always run, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}
