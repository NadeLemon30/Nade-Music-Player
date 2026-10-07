import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_effects.dart';
import '../services/audio_effects/audio_effects_service.dart';

/// Riverpod controller for the equalizer + audio effects (Phase 4B, spec §2).
///
/// A thin reactive shell over [AudioEffectsService]: it mirrors the service's
/// immutable [AudioEffectsState] (so the UI rebuilds from one source of truth)
/// and forwards every mutation. The service — not this controller — owns the
/// engine, the native effects, and persistence.
class AudioEffectsNotifier extends Notifier<AudioEffectsState> {
  AudioEffectsService get _service => ref.read(audioEffectsServiceProvider);

  @override
  AudioEffectsState build() {
    final service = ref.watch(audioEffectsServiceProvider);
    final subscription = service.stateStream.listen((next) {
      state = next;
    });
    ref.onDispose(subscription.cancel);

    // Restores persisted settings and resolves the backend's band layout.
    unawaited(service.initialize());

    return service.state;
  }

  /// Whether the platform exposes a usable equalizer.
  bool get isSupported => state.supported;

  /// Whether bass boost is available on this device.
  bool get bassBoostSupported => _service.bassBoostSupported;

  /// Whether the spatial virtualizer is available on this device.
  bool get virtualizerSupported => _service.virtualizerSupported;

  /// Engages or bypasses the equalizer.
  ///
  /// Bypassing only stops the effect from processing audio — the preset, the band
  /// gains and the preamp stay stored, so switching it back on restores them
  /// exactly as they were (spec §11).
  Future<void> setEqualizerEnabled(bool enabled) =>
      _service.setEqualizerEnabled(enabled);

  /// Sets the gain (dB) of the band at [index].
  ///
  /// The UI follows the slider immediately; the effect update itself is
  /// coalesced so a fast drag cannot flood the platform (spec §24), and it
  /// never reloads or restarts the player (spec §23).
  Future<void> setBandGain(int index, double gain) =>
      _service.setBandGain(index, gain);

  /// Pushes any band gain still waiting behind a throttle window.
  Future<void> flushBandGains() => _service.flushBandGains();

  /// Engages or bypasses the preamp (independent of the equalizer switch).
  Future<void> setPreampEnabled(bool enabled) =>
      _service.setPreampEnabled(enabled);

  /// Sets the preamp gain (dB), clamped to the preamp's own range.
  Future<void> setPreampGain(double decibels) => _service.setPreampGain(decibels);

  /// Engages or bypasses bass boost.
  Future<void> setBassBoostEnabled(bool enabled) =>
      _service.setBassBoostEnabled(enabled);

  /// Sets the bass boost strength (0.0–1.0).
  Future<void> setBassBoost(double strength) => _service.setBassBoost(strength);

  /// Engages or bypasses the spatial (virtualizer) effect.
  Future<void> setVirtualizerEnabled(bool enabled) =>
      _service.setVirtualizerEnabled(enabled);

  /// Sets the virtualizer strength (0.0–1.0).
  Future<void> setVirtualizer(double strength) =>
      _service.setVirtualizer(strength);

  /// Applies a named preset (resampled onto the backend's band count).
  Future<void> applyPreset(EqPreset preset) => _service.applyPreset(preset);

  /// Applies a preset by id.
  Future<void> applyPresetById(String id) => _service.applyPresetById(id);

  /// Flattens the EQ/preamp and switches every effect off.
  Future<void> reset() => _service.reset();

  /// Re-applies every effect to the current audio session (spec §20).
  ///
  /// The hook for output-device changes (headphones, Bluetooth, USB DAC): the
  /// settings are re-sent as they are, so playback, position and queue are
  /// untouched.
  Future<void> reapplyEffects() => _service.reapplyEffects();
}

/// The app's single audio-effects controller (Phase 4B).
final audioEffectsControllerProvider =
    NotifierProvider<AudioEffectsNotifier, AudioEffectsState>(
  AudioEffectsNotifier.new,
);
