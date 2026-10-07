import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../models/audio_effects.dart';

/// The equalizer surface the [AudioEffectsService] drives, abstracted away from
/// `just_audio` so the service can be unit-tested without a platform channel or
/// a real player.
///
/// The real implementation ([JustAudioEffectsBackend]) is built on just_audio's
/// own `AudioPipeline`, which is inserted into the app's **single** player
/// (spec §1 — no second player, no second audio session): the pipeline attaches
/// `android.media.audiofx.Equalizer` to the same audio session the player already
/// owns, and just_audio re-applies the band gains and the enabled flag on every
/// source load, so the EQ survives track changes and background/notification
/// playback.
///
/// The preamp is deliberately **not** on this path. just_audio's
/// `AndroidLoudnessEnhancer` is silently inaudible when a write lands before the
/// effect is attached to a live session, and its effect is rebuilt from a
/// snapshot taken at platform-init time on every audio-session change, so a gain
/// the user set afterwards reverts. The preamp therefore rides the native
/// `MethodChannel` bridge with the bass boost and virtualizer
/// (`native_effects_bridge.dart`), which is bound to the session id the player
/// actually reports.
abstract class AudioEffectsBackend {
  /// Whether this platform/backend exposes a usable equalizer.
  bool get isSupported;

  /// Whether the equalizer is currently engaged.
  bool get equalizerEnabled;

  /// Engages or bypasses the equalizer. Safe to call before the player has
  /// loaded anything: the backend stores the flag and applies it as soon as the
  /// effect becomes active.
  Future<void> setEqualizerEnabled(bool enabled);

  /// The backend's band configuration.
  ///
  /// On Android the effect only reports its bands once the player has loaded its
  /// first source, so this future can stay pending for a long time (and forever
  /// in unit tests — those use a fake backend instead).
  Future<EqBandsConfig> get bands;

  /// Sets the gain (in decibels) of the band at [index].
  Future<void> setBandGain(int index, double gain);
}

/// `just_audio`-backed [AudioEffectsBackend] (Phase 4B).
///
/// Exposes just_audio's equalizer. [audioPipeline] must be handed to the app's
/// one `ja.AudioPlayer` at construction time; the effect object can then only be
/// *tuned* (enabled/disabled, band gains) from here.
class JustAudioEffectsBackend extends AudioEffectsBackend {
  JustAudioEffectsBackend() : _equalizer = ja.AndroidEqualizer() {
    _pipeline = ja.AudioPipeline(
      androidAudioEffects: <ja.AndroidAudioEffect>[_equalizer],
    );
  }

  final ja.AndroidEqualizer _equalizer;

  late final ja.AudioPipeline _pipeline;

  /// The pipeline to attach to the app's single audio player.
  ja.AudioPipeline get audioPipeline => _pipeline;

  /// Android is the only platform with these effects today; unit tests are
  /// treated as available so the plumbing can be exercised without a device.
  static bool get _backendAvailable =>
      !kIsWeb && (Platform.isAndroid || _isUnitTest);

  static bool get _isUnitTest =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  @override
  bool get isSupported => _backendAvailable;

  @override
  bool get equalizerEnabled => _equalizer.enabled;

  @override
  Future<void> setEqualizerEnabled(bool enabled) =>
      _equalizer.setEnabled(enabled);

  @override
  Future<EqBandsConfig> get bands async {
    if (!_backendAvailable) return EqBandsConfig.unsupported;
    try {
      final parameters = await _equalizer.parameters;
      return EqBandsConfig(
        supported: true,
        minDecibels: parameters.minDecibels,
        maxDecibels: parameters.maxDecibels,
        bands: parameters.bands
            .map(
              (band) => EqBand(
                index: band.index,
                centerFrequency: band.centerFrequency,
                lowerFrequency: band.lowerFrequency,
                upperFrequency: band.upperFrequency,
                gain: band.gain,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      // The device has no usable Equalizer effect (or the platform call
      // failed) — the UI falls back to "unsupported" instead of crashing.
      return EqBandsConfig.unsupported;
    }
  }

  @override
  Future<void> setBandGain(int index, double gain) async {
    if (!_backendAvailable) return;
    final parameters = await _equalizer.parameters;
    if (index < 0 || index >= parameters.bands.length) return;
    await parameters.bands[index].setGain(gain);
  }
}
