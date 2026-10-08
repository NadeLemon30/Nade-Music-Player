import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/database/app_database.dart';
import 'package:nades_music_player/data/repositories/audio_effects_preferences.dart';
import 'package:nades_music_player/models/audio_effects.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_backend.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_service.dart';
import 'package:nades_music_player/services/audio_effects/native_effects_bridge.dart';

import '../helpers/fake_audio_effects.dart';

void main() {
  group('EqPreset', () {
    test('resamples a preset curve onto the backend band count', () {
      const preset = EqPreset(id: 'test', label: 'Test', gains: [0, 10]);

      expect(preset.sampleFor(3), [0.0, 5.0, 10.0]);
      expect(preset.sampleFor(5), [0.0, 2.5, 5.0, 7.5, 10.0]);
      expect(preset.sampleFor(1), [0.0]);
      expect(preset.sampleFor(0), isEmpty);
    });

    test('clamps sampled gains to the backend range', () {
      const preset = EqPreset(id: 'test', label: 'Test', gains: [24, -24]);

      expect(preset.sampleFor(2, minDecibels: -12, maxDecibels: 12), [12.0, -12.0]);
    });

    test('offers the full spec preset list', () {
      expect(
        eqPresets.map((preset) => preset.label),
        containsAll(<String>[
          'Normal',
          'Acoustic',
          'Bass Booster',
          'Bass Reducer',
          'Classical',
          'Dance',
          'Deep',
          'Electronic',
          'Hip-Hop',
          'Jazz',
          'Pop',
          'Rock',
          'Vocal',
        ]),
      );
      // Normal is the reset target (spec §10).
      expect(eqPresets.first, same(eqNormalPreset));
    });

    test('presets only apply when the device has enough bands (spec §7)', () {
      // The built-in curves are five-point shapes.
      expect(eqPresets.every((preset) => preset.gains.length == 5), isTrue);
      expect(eqPresetsFor(5), eqPresets);
      expect(eqPresetsFor(10), eqPresets);
      // A 3-band equalizer cannot take a five-point curve without dropping
      // points, so nothing is offered.
      expect(eqPresetsFor(3), isEmpty);
      expect(eqPresetsFor(0), isEmpty);

      const threePoint = EqPreset(id: 'three', label: 'Three', gains: [1, 2, 3]);
      expect(threePoint.appliesTo(3), isTrue);
      expect(threePoint.appliesTo(10), isTrue);
      expect(threePoint.appliesTo(2), isFalse);
    });

    test('every built-in preset is unique and resamples to 5 bands', () {
      final ids = eqPresets.map((preset) => preset.id).toSet();
      expect(ids.length, eqPresets.length);
      for (final preset in eqPresets) {
        expect(preset.sampleFor(5), hasLength(5));
      }
      expect(eqPresetById('bass_booster')?.label, 'Bass Booster');
      expect(eqPresetById('nope'), isNull);
    });
  });

  group('band gain persistence codec', () {
    test('round-trips gains and rejects malformed payloads', () {
      expect(decodeBandGains(encodeBandGains([1.5, -2.0])), [1.5, -2.0]);
      expect(decodeBandGains(null), isEmpty);
      expect(decodeBandGains(''), isEmpty);
      expect(decodeBandGains('not json'), isEmpty);
      expect(decodeBandGains('{"a":1}'), isEmpty);
    });
  });

  group('StrengthRange', () {
    test('maps a normalized strength onto the reported range', () {
      const range = StrengthRange(min: 0, max: 500);
      expect(range.map(0), 0);
      expect(range.map(1), 500);
      expect(range.map(0.5), 250);
    });

    test('an offset range maps its endpoints exactly', () {
      const range = StrengthRange(min: 250, max: 1000);
      expect(range.map(0), 250);
      expect(range.map(1), 1000);
      expect(range.map(0.5), 625);
    });

    test('clamps values outside 0..1 and the reported range', () {
      const range = StrengthRange(min: 0, max: 500);
      expect(range.map(-3), 0);
      expect(range.map(7), 500);
      expect(const StrengthRange(min: 0, max: 10).map(0.45), 5);
    });

    test('knows whether it is the untested default range', () {
      expect(StrengthRange.full.isDefault, isTrue);
      expect(const StrengthRange(min: 0, max: 500).isDefault, isFalse);
    });
  });

  group('AudioEffectsService', () {
    late AppDatabase db;
    late AudioEffectsPreferences repository;
    late FakeAudioEffectsBackend backend;
    late FakeNativeEffectsBridge nativeBridge;
    late AudioEffectsService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = AudioEffectsPreferences(db);
      backend = FakeAudioEffectsBackend();
      nativeBridge = FakeNativeEffectsBridge();
      service = AudioEffectsService(
        preferences: repository,
        backend: backend,
        nativeBridge: nativeBridge,
      );
    });

    tearDown(() async {
      await service.dispose();
      await db.close();
    });

    test('initialize builds the dynamic band layout from the backend',
        () async {
      await service.initialize();
      await _pump();

      final state = service.state;
      expect(state.supported, isTrue);
      expect(state.parametersReady, isTrue);
      expect(state.bands, hasLength(5));
      expect(
        state.bands.map((band) => band.frequencyLabel),
        ['60', '230', '910', '3.6k', '14k'],
      );
      expect(state.minDecibels, -12);
      expect(state.maxDecibels, 12);
    });

    test('an unsupported backend reports unsupported instead of bands',
        () async {
      backend.config = EqBandsConfig.unsupported;
      final unsupportedService = AudioEffectsService(
        preferences: repository,
        backend: backend,
        nativeBridge: nativeBridge,
      );
      addTearDown(unsupportedService.dispose);

      await unsupportedService.initialize();
      await _pump();

      expect(unsupportedService.state.supported, isFalse);
      expect(unsupportedService.state.parametersReady, isFalse);
      expect(unsupportedService.state.bands, isEmpty);
    });

    test('bands that resolve late are applied when they arrive', () async {
      backend.resolveBandsImmediately = false;
      await service.initialize();
      await _pump();

      expect(service.state.resolved, isFalse);
      expect(service.state.parametersReady, isFalse);
      expect(service.state.bands, isEmpty);

      backend.resolveBands();
      await _pump();
      await _pump();

      expect(service.state.resolved, isTrue);
      expect(service.state.bands, hasLength(5));
      expect(backend.bandGains.length, 5);
    });

    test('band gains are clamped to the backend range', () async {
      await service.initialize();
      await _pump();

      await service.setBandGain(0, 40);
      await service.setBandGain(1, -40);
      await _pump();

      expect(service.state.bandGains[0], 12);
      expect(service.state.bandGains[1], -12);
      expect(backend.bandGains[0], 12);
      expect(backend.bandGains[1], -12);
    });

    test('editing a band clears the active preset (custom settings)', () async {
      await service.initialize();
      await _pump();

      await service.applyPresetById('bass_booster');
      expect(service.state.presetId, 'bass_booster');
      expect(service.state.isCustom, isFalse);

      await service.setBandGain(2, 3);
      expect(service.state.presetId, isNull);
      expect(service.state.isCustom, isTrue);
    });

    test('applying a preset writes every band to the backend', () async {
      await service.initialize();
      await _pump();

      await service.applyPresetById('electronic');
      await _pump();

      final gains = service.state.bandGains;
      expect(gains.first, lessThan(gains.last));
      for (var index = 0; index < 5; index++) {
        expect(backend.bandGains[index], gains[index]);
      }
      expect(service.state.presetId, 'electronic');
    });

    test('a preset only writes gains (spec §8)', () async {
      await service.initialize();
      await _pump();
      await service.setPreampGain(6);
      await _pump();

      final appliesBefore = nativeBridge.calls.length;

      await service.applyPresetById('rock');
      await _pump();

      // The preset only moves band gains — the preamp keeps its value and is not
      // re-sent to the engine at all.
      expect(service.state.preampDb, 6);
      expect(nativeBridge.calls.length, appliesBefore);
    });

    test('unknown preset ids are ignored', () async {
      await service.initialize();
      await _pump();

      await service.applyPresetById('does-not-exist');
      expect(service.state.presetId, isNull);
    });

    test('the preamp is forwarded to the native side and persisted', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(11);
      await _pump();

      await service.setPreampGain(4.5);
      await _pump();

      expect(service.state.preampDb, 4.5);
      expect(nativeBridge.lastPreampDb, 4.5);
      expect((await repository.load())!.preampDb, 4.5);
    });

    test('a rapid preamp drag applies the newest gain, not a stale one', () async {
      // Regression: every preamp mutation is fire-and-forget from the slider, so
      // a drag left a burst of pushes crossing the platform channel at once. They
      // complete out of order and the native side applies `setTargetGain` in
      // completion order, so the gain the effect ended up with was whichever value
      // happened to land last — usually an early one. With Android's "0 mB means no
      // amplification" that reads as a preamp that does nothing at all.
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);
      // Hold the second push open on the platform channel so a third change can
      // be issued while it is still in flight.
      final held = Completer<void>();
      nativeBridge.beforeApply = (index) async {
        if (index == 1) await held.future;
      };

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(7);
      await _pump();
      // The session's own re-application has gone out (apply #0).
      expect(nativeBridge.applyCallCount, 1);

      final first = service.setPreampGain(2);
      await _pump();
      final second = service.setPreampGain(10);
      await _pump();

      // The newer change coalesced into the push already on the channel instead
      // of racing it as a second concurrent call.
      expect(nativeBridge.applyCallCount, 2);

      held.complete();
      await first;
      await second;
      await _pump();

      // The newest value is what the effect ends up with, and it got there in a
      // follow-up push rather than by winning a race.
      expect(service.state.preampDb, 10);
      expect(nativeBridge.lastPreampDb, 10);
      expect(nativeBridge.applyCallCount, 3);
    });

    test('engaging the preamp starts at an audible gain', () async {
      // Android documents 0 mB as "no amplification", so switching the preamp on
      // while its gain was still at the bottom produced no sound whatsoever and
      // read as a dead switch until the slider was dragged.
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      await service.setPreampEnabled(true);
      await _pump();

      expect(service.state.preampEnabled, isTrue);
      expect(service.state.preampDb, AudioEffectsService.defaultPreampDb);
      expect(service.state.preampDb, greaterThan(0));
      expect(nativeBridge.lastPreampDb, AudioEffectsService.defaultPreampDb);
    });

    test('engaging the preamp never overwrites a gain the user chose', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      await service.setPreampGain(9);
      await service.setPreampEnabled(true);
      await _pump();

      expect(service.state.preampDb, 9);
      expect(nativeBridge.lastPreampDb, 9);
    });

    test('band gains are clamped to the range the backend reports (spec §6)',
        () async {
      backend.config = EqBandsConfig(
        supported: true,
        minDecibels: -6,
        maxDecibels: 6,
        bands: _bands(3),
      );
      await service.initialize();
      await _pump();

      expect(service.state.minDecibels, -6);
      expect(service.state.maxDecibels, 6);

      await service.setBandGain(0, 20);
      await service.setBandGain(1, -20);
      await _pump();

      expect(service.state.bandGains.first, 6);
      expect(service.state.bandGains[1], -6);
    });

    test('the preamp uses its own range, not the bands\' (spec §6)', () async {
      // The bands report a -6…+6 range; Android's loudness enhancer documents
      // 0 dB as "no amplification", so the preamp must not inherit the bands'
      // symmetric floor — it takes the range the platform reported instead.
      backend.config = EqBandsConfig(
        supported: true,
        minDecibels: -6,
        maxDecibels: 6,
        bands: _bands(3),
      );
      nativeBridge.support = const NativeEffectsSupport(
        preamp: true,
        preampMinDb: 0,
        preampMaxDb: 12,
      );
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      expect(service.state.preampMinDecibels, 0);
      expect(service.state.preampMaxDecibels, 12);
      expect(service.state.preampAvailable, isTrue);

      await service.setPreampGain(-8);
      await service.setPreampGain(30);
      await _pump();

      expect(service.state.preampDb, 12);
      expect(nativeBridge.lastPreampDb, 12);

      await service.setPreampGain(-8);
      await _pump();

      expect(service.state.preampDb, 0);
    });

    test('the preamp is engaged, not just tuned', () async {
      // Regression: an `AudioEffect` that is created but never enabled is
      // permanently bypassed, so a preamp that was only ever given a target gain
      // never produced any sound.
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      expect(nativeBridge.lastPreampEnabled, isFalse);

      await service.setPreampEnabled(true);
      await service.setPreampGain(8);
      await _pump();

      expect(nativeBridge.lastPreampEnabled, isTrue);
      expect(nativeBridge.lastPreampDb, 8);
      expect(service.state.preampEnabled, isTrue);
    });

    test('the preamp bypass keeps its gain (spec §11)', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      await service.setPreampEnabled(true);
      await service.setPreampGain(9);
      await _pump();
      await service.setPreampEnabled(false);
      await _pump();

      expect(nativeBridge.lastPreampEnabled, isFalse);
      expect(nativeBridge.lastPreampDb, 9);
      expect(service.state.preampDb, 9);
    });

    test('the preamp is applied once a session id exists, never before',
        () async {
      // A `LoudnessEnhancer` cannot be constructed before the player owns a
      // session, so nothing is sent until one is reported — and the restored
      // setting is applied the moment it is.
      await repository.save(
        const PersistedAudioEffectsSettings(preampEnabled: true, preampDb: 7),
      );
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();

      // Restored, but not sent anywhere yet.
      expect(service.state.preampEnabled, isTrue);
      expect(service.state.preampDb, 7);
      expect(service.state.nativeResolved, isFalse);
      expect(nativeBridge.calls, isEmpty);

      service.bindSessionIdStream(sessions.stream);
      sessions.add(9);
      await _pump();

      expect(nativeBridge.lastPreampEnabled, isTrue);
      expect(nativeBridge.lastPreampDb, 7);
      expect(service.state.nativeResolved, isTrue);
    });

    test('a preamp failure never disables the equalizer (spec §22)', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();
      expect(service.state.supported, isTrue);

      nativeBridge.support = const NativeEffectsSupport(
        preamp: false,
        bassBoost: true,
        virtualizer: true,
      );
      nativeBridge.failWith = StateError('loudness enhancer died');
      await service.setPreampEnabled(true);
      await service.setPreampGain(6);
      await _pump();

      expect(service.state.preampAvailable, isFalse);
      // The band sliders, presets and the equalizer itself are untouched.
      expect(service.state.supported, isTrue);
      expect(service.state.equalizerEnabled, isFalse);
      expect(service.state.bandCount, 5);
      expect(backend.bandGains.values, everyElement(0));

      // And the stored gain is kept so a device that recovers can be re-enabled.
      expect(service.state.preampDb, 6);
    });

    test('a device without a preamp is reported in the snapshot (spec §22)',
        () async {
      nativeBridge.support = const NativeEffectsSupport(
        preamp: false,
        bassBoost: true,
        virtualizer: true,
      );
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(4);
      await _pump();

      expect(service.state.preampAvailable, isFalse);
      expect(service.state.nativeResolved, isTrue);
    });

    test('native effects are applied once a session id is known', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      expect(nativeBridge.calls, isEmpty);

      service.bindSessionIdStream(sessions.stream);
      sessions.add(42);
      await _pump();

      expect(nativeBridge.lastSessionId, 42);
      expect(service.bassBoostSupported, isTrue);
      expect(service.virtualizerSupported, isTrue);
      // The preamp is reported from the same push.
      expect(service.state.preampAvailable, isTrue);
      expect(service.state.nativeResolved, isTrue);
    });

    test('a new session id re-binds the native effects', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);

      sessions.add(1);
      await _pump();
      sessions.add(2);
      await _pump();

      expect(nativeBridge.calls, ['apply(1)', 'apply(2)']);
      expect(nativeBridge.lastSessionId, 2);
    });

    test('a cleared session id releases the native effects', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(7);
      await _pump();

      sessions.add(null);
      await _pump();

      expect(nativeBridge.calls.last, 'release');
    });

    test('bass boost and virtualizer changes reach the native side', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(5);
      await _pump();

      await service.setBassBoostEnabled(true);
      await service.setBassBoost(0.75);
      await service.setVirtualizerEnabled(true);
      await service.setVirtualizer(0.25);
      await _pump();

      expect(nativeBridge.lastBassBoostEnabled, isTrue);
      expect(nativeBridge.lastBassBoostStrength, 0.75);
      expect(nativeBridge.lastVirtualizerEnabled, isTrue);
      expect(nativeBridge.lastVirtualizerStrength, 0.25);

      final persisted = await repository.load();
      expect(persisted!.bassBoostEnabled, isTrue);
      expect(persisted.bassBoostStrength, 0.75);
      expect(persisted.virtualizerEnabled, isTrue);
      expect(persisted.virtualizerStrength, 0.25);
    });

    test('strengths are clamped to 0..1', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(3);
      await _pump();

      await service.setBassBoost(4);
      await service.setVirtualizer(-1);
      await _pump();

      expect(service.state.bassBoostStrength, 1.0);
      expect(service.state.virtualizerStrength, 0.0);
    });

    test('the state reports the device strength capabilities the platform gave',
        () async {
      nativeBridge.support = const NativeEffectsSupport(
        bassBoost: true,
        virtualizer: true,
        bassBoostStrengthSupported: true,
        virtualizerStrengthSupported: false,
        bassBoostRange: StrengthRange(min: 0, max: 500),
        virtualizerRange: StrengthRange(min: 250, max: 1000),
      );
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      expect(service.state.bassBoostRange, StrengthRange.full);

      service.bindSessionIdStream(sessions.stream);
      sessions.add(3);
      await _pump();

      expect(service.state.bassBoostAvailable, isTrue);
      expect(service.state.virtualizerAvailable, isTrue);
      expect(service.state.bassBoostStrengthSupported, isTrue);
      expect(service.state.virtualizerStrengthSupported, isFalse);
      expect(service.state.bassBoostRange, const StrengthRange(min: 0, max: 500));
      expect(
        service.state.virtualizerRange,
        const StrengthRange(min: 250, max: 1000),
      );
    });

    test('restarting restores the persisted configuration', () async {
      await service.initialize();
      await _pump();
      await service.setEqualizerEnabled(true);
      await service.applyPresetById('rock');
      await service.setPreampGain(3);
      await _pump();

      final restoredBackend = FakeAudioEffectsBackend();
      final restoredBridge = FakeNativeEffectsBridge();
      final restored = AudioEffectsService(
        preferences: repository,
        backend: restoredBackend,
        nativeBridge: restoredBridge,
      );
      addTearDown(restored.dispose);

      await restored.initialize();
      await _pump();

      final state = restored.state;
      expect(state.equalizerEnabled, isTrue);
      expect(state.presetId, 'rock');
      expect(state.preampDb, 3);
      expect(state.bandGains, hasLength(5));
      expect(restoredBackend.bandGains[0], state.bandGains[0]);
      expect(restoredBackend.equalizerEnabled, isTrue);
    });

    test('a stored curve is resampled when the device reports fewer bands',
        () async {
      await service.initialize();
      await _pump();
      await service.applyPresetById('bass_booster');
      await _pump();
      final stored = service.state.bandGains;

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
      final threeBand = AudioEffectsService(
        preferences: repository,
        backend: backend,
        nativeBridge: nativeBridge,
      );
      addTearDown(threeBand.dispose);

      await threeBand.initialize();
      await _pump();

      expect(threeBand.state.bands, hasLength(3));
      // The first and last stored gains are preserved at the edges.
      expect(threeBand.state.bandGains.first, closeTo(stored.first, 0.001));
      expect(threeBand.state.bandGains.last, closeTo(stored.last, 0.001));
    });

    test('reset restores Normal, zero gains, and turns the native effects off',
        () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(9);
      await _pump();

      await service.applyPresetById('rock');
      await service.setEqualizerEnabled(true);
      await service.setPreampGain(6);
      await service.setBassBoostEnabled(true);
      await service.setBassBoost(0.8);
      await service.setVirtualizerEnabled(true);
      await _pump();

      await service.reset();
      await _pump();

      final state = service.state;
      expect(state.presetId, eqNormalPreset.id);
      expect(state.bandGains, everyElement(0));
      expect(state.preampDb, 0);
      expect(state.preampEnabled, isFalse);
      expect(nativeBridge.lastPreampDb, 0);
      expect(nativeBridge.lastPreampEnabled, isFalse);
      expect(state.bassBoostEnabled, isFalse);
      expect(state.bassBoostStrength, 0);
      expect(state.virtualizerEnabled, isFalse);
      expect(state.virtualizerStrength, 0);
      expect(nativeBridge.lastBassBoostEnabled, isFalse);
      // The equalizer's own switch is not part of the spec's reset list.
      expect(state.equalizerEnabled, isTrue);
    });

    test('initialize is idempotent', () async {
      await service.initialize();
      await service.initialize();
      await _pump();

      expect(service.state.bands, hasLength(5));
      expect(
        backend.calls.where((call) => call == 'setEqualizerEnabled(false)'),
        hasLength(1),
      );
    });

    test('dispose releases the native effects', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(11);
      await _pump();

      await service.dispose();
      await _pump();

      expect(nativeBridge.calls.last, 'release');
      // A second dispose must not throw.
      await service.dispose();
    });

    test('state changes are broadcast to listeners', () async {
      await service.initialize();
      await _pump();

      final seen = <bool>[];
      final subscription =
          service.stateStream.listen((state) => seen.add(state.equalizerEnabled));
      addTearDown(subscription.cancel);

      await service.setEqualizerEnabled(true);
      await service.setEqualizerEnabled(false);
      await _pump();

      expect(seen, [true, false]);
    });

    // Spec §17: the player must never wait for optional effects, and a failure
    // disables that one effect instead of breaking playback.
    test('ready completes after the restore and is awaitable', () async {
      await repository.save(
        const PersistedAudioEffectsSettings(equalizerEnabled: true, preampDb: 2),
      );

      await service.initialize();
      await service.ready;
      await _pump();

      expect(service.state.equalizerEnabled, isTrue);
      expect(service.state.preampDb, 2);
    });

    test('a failing preferences store still finishes initialization', () async {
      final failing = AudioEffectsService(
        preferences: _ThrowingPreferences(db),
        backend: backend,
        nativeBridge: nativeBridge,
      );
      addTearDown(failing.dispose);

      // Must neither throw nor hang: playback continues on the defaults.
      await failing.initialize();
      await failing.ready;
      await _pump();

      expect(failing.state.equalizerEnabled, isFalse);
      expect(failing.state.parametersReady, isTrue);
    });

    test('a failing backend leaves the effect disabled, not an exception',
        () async {
      final failingBackend = _FailingAudioEffectsBackend();
      final failing = AudioEffectsService(
        backend: failingBackend,
        nativeBridge: nativeBridge,
      );
      addTearDown(failing.dispose);

      await failing.initialize();
      await failing.ready;
      await _pump();

      // Band discovery threw, so no equalizer is offered — audio keeps playing.
      expect(failing.state.supported, isFalse);
      expect(failing.state.parametersReady, isFalse);
    });

    // Spec §18: the app-wide service is owned by the engine, not by the UI.
    test('a disposed provider container leaves the shared service alone',
        () async {
      globalAudioEffects = service;
      addTearDown(() => globalAudioEffects = null);

      final container = ProviderContainer();
      expect(container.read(audioEffectsServiceProvider), same(service));
      container.dispose();

      // The effects are still live for the background audio session.
      expect(nativeBridge.calls, isNot(contains('release')));
      await service.setEqualizerEnabled(true);
      await _pump();
      expect(service.state.equalizerEnabled, isTrue);
    });

    // Spec §20: output devices change, so effects must be re-appliable.
    test('reapplyEffects pushes the current settings again', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(6);
      await _pump();
      await service.setEqualizerEnabled(true);
      await service.setPreampGain(4);
      await service.setBandGain(2, 7);
      await _pump();

      backend.calls.clear();
      nativeBridge.calls.clear();

      await service.reapplyEffects();
      await _pump();

      expect(backend.calls, contains('setEqualizerEnabled(true)'));
      expect(backend.calls, contains('setBandGain(2, 7.0)'));
      // Every band is re-sent, not just the one that was last touched.
      expect(
        backend.calls.where((call) => call.startsWith('setBandGain(')),
        hasLength(5),
      );
      // The preamp is part of the same re-application, through the native side.
      expect(nativeBridge.calls, contains('apply(6)'));
      expect(nativeBridge.lastPreampDb, 4);
    });

    test('reapplyEffects re-pushes the native effects on the same session',
        () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(7);
      await _pump();
      await service.setBassBoostEnabled(true);
      await _pump();
      nativeBridge.calls.clear();

      await service.reapplyEffects();
      await _pump();

      expect(nativeBridge.calls, contains('apply(7)'));
      expect(nativeBridge.lastBassBoostEnabled, isTrue);
    });

    test('a new session re-sends the equalizer gains as well as the native '
        'effects', () async {
      // just_audio rebuilds its own AudioEffect from a snapshot taken at
      // platform-init time when Android hands over a new session, so a curve the
      // user set after startup would silently revert without this.
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);

      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      await service.setEqualizerEnabled(true);
      await service.setBandGain(1, -6);
      await _pump();
      backend.calls.clear();

      sessions.add(8);
      await _pump();

      expect(backend.calls, contains('setBandGain(1, -6.0)'));
      expect(nativeBridge.calls, contains('apply(8)'));
    });

    test('reapplyEffects never throws when the backend fails', () async {
      final failingBackend = _FailingAudioEffectsBackend();
      final failing = AudioEffectsService(
        backend: failingBackend,
        nativeBridge: nativeBridge,
      );
      addTearDown(failing.dispose);
      await failing.initialize();
      await failing.ready;

      // A device that dropped the effect mid-flight must not crash the app.
      await expectLater(failing.reapplyEffects(), completes);
    });
  });

  // Spec §22: a failure disables that one effect; playback and the UI carry on
  // with a plain message instead of an Android exception.
  group('AudioEffectsService failure isolation', () {
    late FakeAudioEffectsBackend backend;
    late FakeNativeEffectsBridge nativeBridge;
    late AudioEffectsService service;

    setUp(() {
      backend = FakeAudioEffectsBackend();
      nativeBridge = FakeNativeEffectsBridge();
      service = AudioEffectsService(
        backend: backend,
        nativeBridge: nativeBridge,
        delay: _immediateDelay,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('a slider change that fails disables the equalizer, not playback',
        () async {
      await service.initialize();
      await _pump();
      expect(service.state.supported, isTrue);
      // The first band update lands, then the platform effect starts failing.
      backend.failBandGainAfter = backend.bandGains.length + 1;

      // Must not throw out of the UI call.
      await expectLater(service.setBandGain(0, 9), completes);
      await _pump();

      // The effect is switched off in the snapshot, the stored curve is kept.
      expect(service.state.supported, isFalse);
      expect(service.state.parametersReady, isFalse);
      expect(service.state.bands.first.gain, 9);
    });

    test('every user-facing mutation survives a failing backend', () async {
      await service.initialize();
      await _pump();
      backend.failBandGainAfter = 0;
      final failingBackend = _FailingAudioEffectsBackend();
      final failing = AudioEffectsService(
        backend: failingBackend,
        nativeBridge: nativeBridge,
        delay: _immediateDelay,
      );
      addTearDown(failing.dispose);
      await failing.initialize();
      await failing.ready;

      await expectLater(failing.setEqualizerEnabled(true), completes);
      await expectLater(failing.setBandGain(0, 3), completes);
      await expectLater(failing.setPreampEnabled(true), completes);
      await expectLater(failing.setPreampGain(3), completes);
      await expectLater(failing.applyPresetById('rock'), completes);
      await expectLater(failing.setBassBoostEnabled(true), completes);
      await expectLater(failing.setBassBoost(0.5), completes);
      await expectLater(failing.setVirtualizerEnabled(true), completes);
      await expectLater(failing.setVirtualizer(0.5), completes);
      await expectLater(failing.reset(), completes);

      // It reports itself unavailable instead of pretending to be engaged.
      expect(failing.state.supported, isFalse);
      expect(failing.state.preampAvailable, isFalse);
    });

    test('a failing native bridge disables the native effects only', () async {
      final sessions = StreamController<int?>.broadcast(sync: true);
      addTearDown(sessions.close);
      await service.initialize();
      await _pump();
      service.bindSessionIdStream(sessions.stream);
      sessions.add(3);
      await _pump();
      expect(service.state.bassBoostAvailable, isTrue);
      expect(service.state.preampAvailable, isTrue);

      // The platform channel goes away (spec §22).
      nativeBridge.failWith = PlatformException(code: 'error');

      await expectLater(service.setBassBoostEnabled(true), completes);
      await expectLater(service.setPreampEnabled(true), completes);
      await _pump();

      // The equalizer keeps working; only the native effects are disabled.
      expect(service.state.bassBoostAvailable, isFalse);
      expect(service.state.virtualizerAvailable, isFalse);
      // Including the preamp — it is a native effect now, but on its own: the
      // band curve and presets are untouched.
      expect(service.state.preampAvailable, isFalse);
      expect(service.state.supported, isTrue);
      expect(service.state.bandCount, 5);
    });

    test('no raw platform message is ever put in the state', () async {
      await service.initialize();
      await _pump();
      backend.failBandGainAfter = 0;
      nativeBridge.failWith = PlatformException(
        code: 'error',
        message: 'java.lang.RuntimeException: audiofx blew up',
      );

      await service.setBandGain(0, 4);
      await service.setBassBoostEnabled(true);
      await _pump();

      // The state is a plain snapshot: no error text for the UI to leak.
      expect(service.state.toString(), isNot(contains('RuntimeException')));
      expect(service.state.toString(), isNot(contains('audiofx')));
    });
  });

  // Spec §24: a slider drag must not flood the platform — the UI follows the
  // slider immediately, the effect gets one coalesced update with the latest
  // value.
  group('AudioEffectsService slider throttling', () {
    late FakeAudioEffectsBackend backend;
    late List<void Function()> scheduled;
    late AudioEffectsService service;

    setUp(() async {
      backend = FakeAudioEffectsBackend();
      scheduled = <void Function()>[];
      service = AudioEffectsService(
        backend: backend,
        nativeBridge: FakeNativeEffectsBridge(),
        // A manual "timer" so the test controls exactly when a window closes.
        delay: (duration, action) {
          scheduled.add(action);
          return Future<void>.value();
        },
      );
      await service.initialize();
      await _pump();
      backend.calls.clear();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('a single change reaches the backend immediately', () async {
      await service.setBandGain(2, 6);
      await _pump();

      expect(backend.bandGains[2], 6);
    });

    test('a rapid burst is coalesced and the latest value wins', () async {
      // 20 slider events, as a fast drag would produce.
      for (var step = 0; step < 20; step++) {
        await service.setBandGain(0, (step - 10).toDouble());
      }
      await _pump();

      // The UI already shows the newest value.
      expect(service.state.bandGains.first, 9);

      // The platform got the leading value immediately, and nothing else yet.
      expect(_bandGainCalls(backend), ['setBandGain(0, -10.0)']);

      // Closing the coalescing window delivers exactly one update: the latest.
      for (final close in List<void Function()>.from(scheduled)) {
        close();
      }
      await _pump();

      expect(_bandGainCalls(backend), [
        'setBandGain(0, -10.0)',
        'setBandGain(0, 9.0)',
      ]);
      expect(backend.bandGains[0], 9);
    });

    test('a burst on different bands is coalesced per band', () async {
      for (var step = 0; step < 5; step++) {
        await service.setBandGain(0, (step - 2).toDouble());
        await service.setBandGain(1, (2 - step).toDouble());
      }
      await _pump();

      expect(_bandGainCalls(backend), [
        'setBandGain(0, -2.0)',
        'setBandGain(1, 2.0)',
      ]);

      for (final close in List<void Function()>.from(scheduled)) {
        close();
      }
      await _pump();

      expect(backend.bandGains[0], 2);
      expect(backend.bandGains[1], -2);
      // One trailing update per band, not one per slider event.
      expect(_bandGainCalls(backend), hasLength(4));
    });

    test('flushBandGains delivers a pending value on demand', () async {
      await service.setBandGain(3, 2);
      await service.setBandGain(3, 7);
      await _pump();

      await service.flushBandGains();
      await _pump();

      expect(backend.bandGains[3], 7);
    });

    test('dispose delivers a pending value instead of losing it', () async {
      await service.setBandGain(3, 2);
      await service.setBandGain(3, 8);
      await _pump();

      await service.dispose();
      await _pump();

      expect(backend.bandGains[3], 8);
    });

    test('a preset supersedes a pending slider value', () async {
      await service.setBandGain(0, 11);
      await _pump();

      await service.applyPresetById('rock');
      await _pump();

      // The armed window must not overwrite the preset curve afterwards.
      for (final close in List<void Function()>.from(scheduled)) {
        close();
      }
      await _pump();

      expect(service.state.presetId, 'rock');
      expect(backend.bandGains[0], service.state.bandGains[0]);
    });
  });

  group('AudioEffectsService without a backing store', () {
    test('mutations work without a repository', () async {
      final service = AudioEffectsService(
        backend: FakeAudioEffectsBackend(),
        nativeBridge: FakeNativeEffectsBridge(),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await _pump();
      await service.setEqualizerEnabled(true);
      await _pump();

      expect(service.state.equalizerEnabled, isTrue);
    });
  });
}

/// Lets pending microtasks/futures settle without a real clock dependency.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A delay that runs its action straight away — used where a test does not care
/// about coalescing and must not leave a pending timer behind.
Future<void> _immediateDelay(Duration duration, void Function() action) {
  action();
  return Future<void>.value();
}

/// The backend's `setBandGain` calls, in order.
List<String> _bandGainCalls(FakeAudioEffectsBackend backend) => backend.calls
    .where((call) => call.startsWith('setBandGain('))
    .toList(growable: false);

/// A preferences store that cannot be read (spec §17: the store is optional, so
/// a broken one must not stop playback or startup).
class _ThrowingPreferences extends AudioEffectsPreferences {
  _ThrowingPreferences(super.db);

  @override
  Future<PersistedAudioEffectsSettings?> load() async =>
      throw StateError('settings store unavailable');
}

/// A backend whose effect calls and band query always fail — models a device
/// that dropped the equalizer (or an engine that refuses it).
class _FailingAudioEffectsBackend extends AudioEffectsBackend {
  @override
  bool get isSupported => false;

  @override
  bool get equalizerEnabled => false;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async =>
      throw StateError('equalizer unavailable');

  @override
  Future<EqBandsConfig> get bands async => throw StateError('no bands');

  @override
  Future<void> setBandGain(int index, double gain) async =>
      throw StateError('equalizer unavailable');
}

/// A generic [count]-band layout (log-ish spacing) for backend fakes.
List<EqBand> _bands(int count) => List<EqBand>.generate(
      count,
      (index) => EqBand(
        index: index,
        centerFrequency: 60 * (index + 1),
        lowerFrequency: 30 * (index + 1),
        upperFrequency: 90 * (index + 1),
      ),
    );
