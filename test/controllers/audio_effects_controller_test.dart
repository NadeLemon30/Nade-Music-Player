import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/controllers/audio_effects_controller.dart';
import 'package:nades_music_player/models/audio_effects.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';

import '../helpers/fake_audio_effects.dart';
import '../helpers/fake_audio_player_service.dart';

void main() {
  group('AudioEffectsNotifier', () {
    late FakeAudioEffectsBackend backend;
    late FakeNativeEffectsBridge nativeBridge;
    late AudioEffectsService service;
    late ProviderContainer container;

    ProviderContainer buildContainer() {
      return ProviderContainer(
        overrides: [audioEffectsServiceProvider.overrideWith((ref) => service)],
      );
    }

    setUp(() {
      backend = FakeAudioEffectsBackend();
      nativeBridge = FakeNativeEffectsBridge();
      service = AudioEffectsService(
        backend: backend,
        nativeBridge: nativeBridge,
      );
    });

    /// Instantiates the notifier (which kicks off restore + band discovery) and
    /// waits until the backend's band layout has landed in its state.
    Future<AudioEffectsNotifier> readyController() async {
      final controller =
          container.read(audioEffectsControllerProvider.notifier);
      for (var attempt = 0; attempt < 20; attempt++) {
        await _pump();
        if (container.read(audioEffectsControllerProvider).parametersReady ||
            !container.read(audioEffectsControllerProvider).supported) {
          break;
        }
      }
      return controller;
    }

    tearDown(() async {
      container.dispose();
      await service.dispose();
    });

    test('mirrors the service state once the bands resolve', () async {
      container = buildContainer();
      expect(container.read(audioEffectsControllerProvider).bands, isEmpty);

      await _pump();

      final state = container.read(audioEffectsControllerProvider);
      expect(state.supported, isTrue);
      expect(state.bands, hasLength(5));
    });

    test('forwards mutations to the service', () async {
      container = buildContainer();
      final controller = await readyController();

      await controller.setEqualizerEnabled(true);
      await controller.setBandGain(0, 6);
      await controller.setPreampEnabled(true);
      await controller.setPreampGain(2);
      await _pump();

      final state = container.read(audioEffectsControllerProvider);
      expect(state.equalizerEnabled, isTrue);
      expect(state.bandGains.first, 6);
      expect(state.preampEnabled, isTrue);
      expect(state.preampDb, 2);
      expect(backend.bandGains[0], 6);
    });

    test('applies a preset by id', () async {
      container = buildContainer();
      final controller = await readyController();

      await controller.applyPresetById('jazz');
      await _pump();

      expect(container.read(audioEffectsControllerProvider).presetId, 'jazz');
    });

    test('reset restores Normal, zeroed gains and off native effects', () async {
      container = buildContainer();
      final controller = await readyController();

      await controller.applyPresetById('rock');
      await controller.setEqualizerEnabled(true);
      await controller.setPreampGain(5);
      await controller.setBassBoostEnabled(true);
      await _pump();
      await controller.reset();
      await _pump();

      final state = container.read(audioEffectsControllerProvider);
      expect(state.presetId, 'normal');
      expect(state.bandGains, everyElement(0));
      expect(state.preampDb, 0);
      expect(state.bassBoostEnabled, isFalse);
      expect(state.virtualizerEnabled, isFalse);
    });

    test('reset leaves playback, queue and library state untouched', () async {
      final player = FakeAudioPlayerService();
      addTearDown(player.dispose);
      container = ProviderContainer(
        overrides: [
          audioEffectsServiceProvider.overrideWith((ref) => service),
          audioPlayerServiceProvider.overrideWithValue(player),
          playHistoryServiceProvider.overrideWith(
            (ref) => NoopPlayHistoryService(),
          ),
        ],
      );
      final controller = await readyController();
      final playerNotifier = container.read(playerNotifierProvider.notifier);

      await playerNotifier.setQueue([testTrack('a'), testTrack('b')]);
      await _pump();
      final before = container.read(playerNotifierProvider);

      await controller.applyPresetById('rock');
      await controller.setBassBoostEnabled(true);
      await controller.reset();
      await _pump();

      final after = container.read(playerNotifierProvider);
      expect(after.queue, hasLength(2));
      expect(after.currentTrack?.id, before.currentTrack?.id);
      expect(after.position, before.position);
      expect(after.duration, before.duration);
      // Nothing in the effects layer paused, stopped, seeked or re-queued.
      expect(player.playCount, 1);
      expect(player.pauseCount, 0);
      expect(player.stopCount, 0);
      expect(player.seekCount, 0);
    });

    test('exposes the native effect availability', () async {
      final sessions = _SessionIds();
      addTearDown(sessions.close);
      container = buildContainer();
      final controller = await readyController();

      // Before the player owns a session nothing can be asked, so nothing is
      // claimed — "unknown" is not "unavailable".
      expect(container.read(audioEffectsControllerProvider).nativeResolved,
          isFalse);

      service.bindSessionIdStream(sessions.stream);

      sessions.add(1);
      await _pump();

      expect(controller.bassBoostSupported, isTrue);
      expect(controller.virtualizerSupported, isTrue);
      // The preamp is a native effect too, and reports from the same push.
      expect(container.read(audioEffectsControllerProvider).nativeResolved,
          isTrue);
      expect(container.read(audioEffectsControllerProvider).preampAvailable,
          isTrue);
    });

    test('an unsupported backend leaves the controller unsupported', () async {
      backend.config = EqBandsConfig.unsupported;
      container = buildContainer();
      final controller = await readyController();

      expect(controller.isSupported, isFalse);
    });

    // Spec §19: changing equalizer settings must not interrupt the current
    // song, the playback position, the queue or background playback.
    test('changing settings never interrupts the current song', () async {
      final player = FakeAudioPlayerService();
      addTearDown(player.dispose);
      container = ProviderContainer(
        overrides: [
          audioEffectsServiceProvider.overrideWith((ref) => service),
          audioPlayerServiceProvider.overrideWithValue(player),
          playHistoryServiceProvider.overrideWith(
            (ref) => NoopPlayHistoryService(),
          ),
        ],
      );
      final controller = await readyController();
      final playerNotifier = container.read(playerNotifierProvider.notifier);

      await playerNotifier.setQueue([testTrack('a'), testTrack('b')]);
      // Give the engine a real duration/position so the assertion is about a
      // genuinely mid-song, playing state.
      player.emitDuration(const Duration(minutes: 3));
      player.emitPosition(const Duration(seconds: 30));
      await _pump();
      final before = container.read(playerNotifierProvider);
      expect(before.isPlaying, isTrue);
      expect(before.position, const Duration(seconds: 30));
      final mediaItems = player.mediaItemUpdateCount;

      // Every kind of settings change a user can make.
      await controller.setEqualizerEnabled(true);
      await controller.applyPresetById('rock');
      await controller.setBandGain(0, 8);
      await controller.setPreampGain(3);
      await controller.setBassBoostEnabled(true);
      await controller.setBassBoost(0.6);
      await controller.setVirtualizerEnabled(true);
      await controller.setVirtualizer(0.4);
      await _pump();

      final after = container.read(playerNotifierProvider);
      expect(after.isPlaying, isTrue);
      expect(after.currentTrack?.id, before.currentTrack?.id);
      expect(after.position, before.position);
      expect(after.duration, before.duration);
      expect(after.queue, hasLength(2));
      // No reload, pause, stop or seek leaked out of the effects layer.
      expect(player.setFileCount, 1);
      expect(player.playCount, 1);
      expect(player.pauseCount, 0);
      expect(player.stopCount, 0);
      expect(player.seekCount, 0);
      // The lock-screen/notification metadata is untouched and still correct.
      expect(player.mediaItemUpdateCount, mediaItems);
      expect(player.lastMediaItem?.id, before.currentTrack?.id);
    });

    // Spec §20: the device-change hook reaches the service.
    test('reapplyEffects forwards to the service and keeps playback', () async {
      final player = FakeAudioPlayerService();
      addTearDown(player.dispose);
      container = ProviderContainer(
        overrides: [
          audioEffectsServiceProvider.overrideWith((ref) => service),
          audioPlayerServiceProvider.overrideWithValue(player),
          playHistoryServiceProvider.overrideWith(
            (ref) => NoopPlayHistoryService(),
          ),
        ],
      );
      final controller = await readyController();
      final playerNotifier = container.read(playerNotifierProvider.notifier);

      await playerNotifier.setQueue([testTrack('a')]);
      await controller.setBandGain(1, 5);
      await _pump();
      backend.calls.clear();
      final before = container.read(playerNotifierProvider);

      await controller.reapplyEffects();
      await _pump();

      expect(backend.calls, contains('setBandGain(1, 5.0)'));
      final after = container.read(playerNotifierProvider);
      expect(after.currentTrack?.id, before.currentTrack?.id);
      expect(after.position, before.position);
      expect(player.setFileCount, 1);
    });
  });
}

class _SessionIds {
  final _controller = StreamController<int?>.broadcast(sync: true);

  Stream<int?> get stream => _controller.stream;

  void add(int? id) => _controller.add(id);

  Future<void> close() => _controller.close();
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
