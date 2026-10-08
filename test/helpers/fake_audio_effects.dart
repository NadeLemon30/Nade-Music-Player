import 'dart:async';

import 'package:nades_music_player/models/audio_effects.dart';
import 'package:nades_music_player/services/audio_effects/audio_effects_backend.dart';
import 'package:nades_music_player/services/audio_effects/native_effects_bridge.dart';

/// In-memory fake of [AudioEffectsBackend] that records every call and lets a
/// test decide what band configuration the "platform" reports.
///
/// The default is a realistic Android-like 5-band layout (60/230/910/3.6k/14k)
/// so tests exercise the same dynamic-band path the device uses.
class FakeAudioEffectsBackend extends AudioEffectsBackend {
  FakeAudioEffectsBackend({
    this.config = defaultFiveBands,
    this.resolveBandsImmediately = true,
  });

  /// A typical Android equalizer layout: 5 bands, ±12 dB.
  static const EqBandsConfig defaultFiveBands = EqBandsConfig(
    supported: true,
    minDecibels: -12,
    maxDecibels: 12,
    bands: <EqBand>[
      EqBand(
        index: 0,
        centerFrequency: 60,
        lowerFrequency: 30,
        upperFrequency: 120,
      ),
      EqBand(
        index: 1,
        centerFrequency: 230,
        lowerFrequency: 120,
        upperFrequency: 460,
      ),
      EqBand(
        index: 2,
        centerFrequency: 910,
        lowerFrequency: 460,
        upperFrequency: 1800,
      ),
      EqBand(
        index: 3,
        centerFrequency: 3600,
        lowerFrequency: 1800,
        upperFrequency: 7200,
      ),
      EqBand(
        index: 4,
        centerFrequency: 14000,
        lowerFrequency: 7200,
        upperFrequency: 21000,
      ),
    ],
  );

  /// What the backend reports when the service asks for its bands.
  EqBandsConfig config;

  /// When false, [bands] stays pending until [resolveBands] is called — models
  /// Android only reporting its layout after the first source is loaded.
  bool resolveBandsImmediately;

  final Completer<EqBandsConfig> _bandsCompleter = Completer<EqBandsConfig>();

  final List<String> calls = <String>[];

  /// When positive, every [setBandGain] call after this many has already been
  /// served throws — models an effect that dies in the middle of a drag
  /// (spec §22). Zero means the backend never fails.
  int failBandGainAfter = 0;

  int _bandGainCallCount = 0;

  /// Gains the backend was asked to set, by band index.
  final Map<int, double> bandGains = <int, double>{};

  bool _equalizerEnabled = false;

  @override
  bool get isSupported => config.supported;

  @override
  bool get equalizerEnabled => _equalizerEnabled;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    calls.add('setEqualizerEnabled($enabled)');
    _equalizerEnabled = enabled;
  }

  @override
  Future<EqBandsConfig> get bands {
    if (resolveBandsImmediately) return Future<EqBandsConfig>.value(config);
    return _bandsCompleter.future;
  }

  /// Lets a pending [bands] future complete — models the platform reporting its
  /// layout only after the first source is loaded.
  void resolveBands() {
    if (!_bandsCompleter.isCompleted) _bandsCompleter.complete(config);
  }

  @override
  Future<void> setBandGain(int index, double gain) async {
    _bandGainCallCount++;
    calls.add('setBandGain($index, $gain)');
    if (failBandGainAfter > 0 && _bandGainCallCount > failBandGainAfter) {
      throw StateError('equalizer effect died');
    }
    bandGains[index] = gain;
  }
}

/// Recording fake of [NativeEffectsBridge]: no platform channel, but it captures
/// every apply/release so tests can assert what the native side would receive.
class FakeNativeEffectsBridge extends NativeEffectsBridge {
  FakeNativeEffectsBridge({
    this.support = const NativeEffectsSupport(
      preamp: true,
      bassBoost: true,
      virtualizer: true,
      bassBoostStrengthSupported: true,
      virtualizerStrengthSupported: true,
    ),
    this.failWith,
  });

  /// What the "device" reports as supported.
  NativeEffectsSupport support;

  /// When set, every apply/release throws — models a platform channel that is
  /// missing or that refuses the effect (spec §22).
  Object? failWith;

  /// Awaited at the start of every [apply], before anything is recorded, so a
  /// test can hold a push open on the platform channel and issue a second one
  /// while it is still in flight.
  ///
  /// This is what a real slider drag does: a burst of fire-and-forget calls
  /// crossing the channel at once, which the native side applies in *completion*
  /// order. The index is the 0-based count of applies that have been entered.
  Future<void> Function(int index)? beforeApply;

  /// How many times [apply] has been entered.
  int applyCallCount = 0;

  final List<String> calls = <String>[];

  /// The last applied parameters (null until the first apply).
  int? lastSessionId;
  bool? lastPreampEnabled;
  double? lastPreampDb;
  bool? lastBassBoostEnabled;
  double? lastBassBoostStrength;
  bool? lastVirtualizerEnabled;
  double? lastVirtualizerStrength;

  @override
  bool get isAvailable => true;

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
    final index = applyCallCount++;
    final gate = beforeApply;
    if (gate != null) await gate(index);
    calls.add('apply($sessionId)');
    final failure = failWith;
    if (failure != null) throw failure;
    lastSessionId = sessionId;
    lastPreampEnabled = preampEnabled;
    lastPreampDb = preampDb;
    lastBassBoostEnabled = bassBoostEnabled;
    lastBassBoostStrength = bassBoostStrength;
    lastVirtualizerEnabled = virtualizerEnabled;
    lastVirtualizerStrength = virtualizerStrength;
    return support;
  }

  @override
  Future<void> release() async {
    calls.add('release');
    final failure = failWith;
    if (failure != null) throw failure;
  }
}
