import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/audio_effects.dart';

/// Which of the three native effects the backend reported as usable, and the
/// ranges this device actually accepts (spec §12/§13, preamp §6).
class NativeEffectsSupport {
  const NativeEffectsSupport({
    this.preamp = false,
    this.bassBoost = false,
    this.virtualizer = false,
    this.bassBoostStrengthSupported = false,
    this.virtualizerStrengthSupported = false,
    this.preampMinDb = defaultPreampMinDb,
    this.preampMaxDb = defaultPreampMaxDb,
    this.bassBoostRange = StrengthRange.full,
    this.virtualizerRange = StrengthRange.full,
  });

  /// Android's `LoudnessEnhancer` documents `0 mB` as "no amplification" — the
  /// effect only ever boosts — and caps the target at 2000 mB. It exposes no
  /// public range query, so these are the documented platform bounds used until
  /// (or instead of) a real reading.
  static const double defaultPreampMinDb = 0;
  static const double defaultPreampMaxDb = 20;

  /// Whether `android.media.audiofx.LoudnessEnhancer` is available on this
  /// device.
  final bool preamp;

  /// Lowest preamp gain the device accepts, in decibels.
  final double preampMinDb;

  /// Highest preamp gain the device accepts, in decibels.
  final double preampMaxDb;

  /// Whether `android.media.audiofx.BassBoost` is available on this device.
  final bool bassBoost;

  /// Whether `android.media.audiofx.Virtualizer` is available on this device.
  final bool virtualizer;

  /// Whether the device lets us change the bass boost strength at all
  /// (`BassBoost.getStrengthSupported()`). False means the effect is switchable
  /// but has no usable strength slider.
  final bool bassBoostStrengthSupported;

  /// The same for `Virtualizer.getStrengthSupported()`.
  final bool virtualizerStrengthSupported;

  /// The strength scale the platform reported for bass boost.
  final StrengthRange bassBoostRange;

  /// The strength scale the platform reported for the virtualizer.
  final StrengthRange virtualizerRange;

  /// None of the effects are usable (desktop, web, or an unsupported device).
  bool get none => !preamp && !bassBoost && !virtualizer;
}

/// Bridge to the three audio effects driven natively — the preamp
/// (`LoudnessEnhancer`), bass boost and the spatial virtualizer (Phase 4B,
/// spec §2).
///
/// just_audio's [AudioPipeline] only covers an equalizer, so these are
/// implemented natively in `MainActivity` behind this channel and attached to
/// the *same* audio session the existing player uses — there is still exactly
/// one player, one handler and one audio session (spec §1).
///
/// The preamp deliberately lives here rather than on just_audio's
/// `AndroidLoudnessEnhancer`: that path silently does nothing when a write lands
/// before the effect is attached to a live session, and its effect is re-created
/// from a platform-init snapshot on every session change, so a gain the user set
/// afterwards reverts. Driving it from the session id the player actually reports
/// makes it deterministic, and lets the device report whether the effect exists
/// at all instead of the app silently claiming a preamp it cannot deliver.
///
/// Every method degrades to a no-op off Android and in tests, so UI and unit
/// tests never need a platform channel.
abstract class NativeEffectsBridge {
  /// Allows const subclasses.
  const NativeEffectsBridge();

  /// Applies all three native effects to [sessionId].
  ///
  /// Implementations must re-bind (release + recreate) when [sessionId] changes,
  /// because an Android `AudioEffect` is bound to the session it was created
  /// with. [bassBoostStrength]/[virtualizerStrength] are normalized 0.0–1.0 and
  /// [preampDb] is in decibels; the native side clamps each onto the range the
  /// platform accepts, so no fixed per-device scale is ever assumed on this side
  /// (spec §12, §6).
  ///
  /// Returns which effects the device supports, whether their strength is
  /// adjustable, and the ranges the platform reported.
  Future<NativeEffectsSupport> apply({
    required int sessionId,
    required bool preampEnabled,
    required double preampDb,
    required bool bassBoostEnabled,
    required double bassBoostStrength,
    required bool virtualizerEnabled,
    required double virtualizerStrength,
  });

  /// Releases both native effects (no-op when nothing is attached).
  Future<void> release();

  /// Whether the current platform can host native effects at all.
  bool get isAvailable;
}

/// [MethodChannel] implementation of [NativeEffectsBridge].
///
/// Talks to `MainActivity`'s `com.example.test_app/audio_effects` channel.
class MethodChannelNativeEffectsBridge extends NativeEffectsBridge {
  MethodChannelNativeEffectsBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.example.test_app/audio_effects';

  final MethodChannel _channel;

  NativeEffectsSupport _support = const NativeEffectsSupport();

  @override
  bool get isAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<NativeEffectsSupport> apply({
    required int sessionId,
    required bool preampEnabled,
    required double preampDb,
    required bool bassBoostEnabled,
    required double bassBoostStrength,
    required bool virtualizerEnabled,
    required double virtualizerStrength,
  }) async {
    if (!isAvailable) return _support;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'applyEffects',
        <String, Object?>{
          'sessionId': sessionId,
          'preampEnabled': preampEnabled,
          'preampDb': preampDb,
          'bassBoostEnabled': bassBoostEnabled,
          // Normalized 0…1 all the way down: the platform maps it onto the
          // strength range the effect itself reported, so no per-device integer
          // scale is ever assumed on this side (spec §12).
          'bassBoostStrength': bassBoostStrength,
          'virtualizerEnabled': virtualizerEnabled,
          'virtualizerStrength': virtualizerStrength,
        },
      );
      if (result == null) return _support;
      _support = NativeEffectsSupport(
        preamp: result['preamp'] == true,
        preampMinDb: _preampRange(result, 'preampGainMin', _support.preampMinDb),
        preampMaxDb: _preampRange(result, 'preampGainMax', _support.preampMaxDb),
        bassBoost: result['bassBoost'] == true,
        virtualizer: result['virtualizer'] == true,
        bassBoostStrengthSupported: result['bassBoostStrengthSupported'] == true,
        virtualizerStrengthSupported:
            result['virtualizerStrengthSupported'] == true,
        bassBoostRange: _range(result, 'bassBoost', _support.bassBoostRange),
        virtualizerRange:
            _range(result, 'virtualizer', _support.virtualizerRange),
      );
      return _support;
    } on PlatformException {
      return _support;
    } on MissingPluginException {
      return _support;
    }
  }

  @override
  Future<void> release() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('releaseEffects');
    } on PlatformException {
      // Nothing to release.
    } on MissingPluginException {
      // No native side registered (tests).
    }
  }

  /// Reads one bound of the preamp range the platform reported, converting the
  /// millibels `LoudnessEnhancer.setTargetGain` takes into decibels and keeping
  /// [fallback] when the value is missing or nonsensical.
  ///
  /// The map key carries the platform unit on purpose (`preampGainMin`), so the
  /// conversion lives in exactly one place instead of being done twice on two
  /// sides of the channel.
  static double _preampRange(
    Map<String, Object?> result,
    String key,
    double fallback,
  ) {
    final millibels = result[key];
    if (millibels is! num) return fallback;
    return millibels.toDouble() / 100.0;
  }

  /// Reads the `<effect>StrengthMin`/`Max` pair the platform reported, keeping
  /// [fallback] when the values are missing or nonsensical.
  static StrengthRange _range(
    Map<String, Object?> result,
    String effect,
    StrengthRange fallback,
  ) {
    final min = result['${effect}StrengthMin'];
    final max = result['${effect}StrengthMax'];
    if (min is! num || max is! num) return fallback;
    final low = min.toInt();
    final high = max.toInt();
    if (high <= low) return fallback;
    return StrengthRange(min: low, max: high);
  }
}

/// A bridge that does nothing — the default in tests and on platforms without
/// native effects, so callers never need to null-check.
class NoopNativeEffectsBridge extends NativeEffectsBridge {
  const NoopNativeEffectsBridge();

  @override
  bool get isAvailable => false;

  @override
  Future<NativeEffectsSupport> apply({
    required int sessionId,
    required bool preampEnabled,
    required double preampDb,
    required bool bassBoostEnabled,
    required double bassBoostStrength,
    required bool virtualizerEnabled,
    required double virtualizerStrength,
  }) async {
    return const NativeEffectsSupport();
  }

  @override
  Future<void> release() async {}
}
