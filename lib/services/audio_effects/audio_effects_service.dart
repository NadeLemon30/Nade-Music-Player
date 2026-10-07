import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../data/repositories/audio_effects_preferences.dart';
import '../../models/audio_effects.dart';
import 'audio_effects_backend.dart';
import 'native_effects_bridge.dart';

/// The single app-wide [AudioEffectsService]. It is **constructed** in `main()`
/// before `AudioService.init` so its pipeline can be baked into the one audio
/// player, and **initialized** after the handler exists so the player never waits
/// for optional effects (spec §17). Held in a plain global (mirroring
/// `globalAudioHandler`) so the Riverpod layer reaches the same instance the
/// engine uses. Null before main initializes it, and in unit tests (which inject
/// their own instance).
AudioEffectsService? globalAudioEffects;

/// The one place that owns audio-processing state (Phase 4B, spec §2).
///
/// Responsibilities:
///  - hands its [audioPipeline] to the app's **single** audio player, so the
///    equalizer rides the existing playback pipeline (spec §1 — no second player,
///    handler, or audio session);
///  - drives the **preamp** (`LoudnessEnhancer`) through [NativeEffectsBridge]
///    together with the bass boost and virtualizer, because just_audio's
///    `AndroidLoudnessEnhancer` is silently inaudible: writes that land before the
///    effect is attached to a live session are discarded, and the effect is
///    rebuilt from a platform-init snapshot on every session change, so a gain
///    set later reverts. The native path binds it to the session id the player
///    actually reports and rebuilds it on every change;
///  - queries the backend for its **dynamic** band configuration and builds the
///    UI-facing state from it (spec §5);
///  - drives bass boost / virtualizer through [NativeEffectsBridge], bound to
///    the player's own audio session id and re-bound whenever that id changes;
///  - restores and persists the user's settings.
///
/// The service is engine-agnostic beyond that: [AudioEffectsBackend] and
/// [NativeEffectsBridge] are injected, so unit tests run the exact same code
/// with fakes.
class AudioEffectsService {
  AudioEffectsService({
    this._preferences,
    AudioEffectsBackend? backend,
    NativeEffectsBridge? nativeBridge,
    this.bandUpdateThrottle = defaultBandUpdateThrottle,
    Future<void> Function(Duration duration, void Function() action)? delay,
  })  : _backend = backend ?? JustAudioEffectsBackend(),
        _nativeBridge = nativeBridge ?? MethodChannelNativeEffectsBridge(),
        _delay = delay ?? _defaultDelay;

  /// How long rapid changes to one band are coalesced (spec §24).
  ///
  /// A slider drag emits a change per frame; sending every one straight to the
  /// platform is wasted work. The **first** change of a burst still goes out
  /// immediately (so a single tap applies right away) and the rest are merged
  /// into one trailing update carrying the latest value.
  static const Duration defaultBandUpdateThrottle = Duration(milliseconds: 60);

  /// The gain a freshly engaged preamp starts at.
  ///
  /// Android's `LoudnessEnhancer` documents `0 mB` as "no amplification" — the
  /// effect only ever boosts, and at a zero target it does nothing at all — so a
  /// preamp engaged at 0 dB is silent. Starting a fresh engage here means the
  /// switch is audible straight away instead of needing a slider drag first.
  static const double defaultPreampDb = 6;

  static Future<void> _defaultDelay(Duration duration, void Function() action) =>
      Future<void>.delayed(duration, action);

  /// Persisted preferences (spec §15); null in tests, which then start clean.
  final AudioEffectsPreferences? _preferences;
  final AudioEffectsBackend _backend;
  final NativeEffectsBridge _nativeBridge;
  final Future<void> Function(Duration duration, void Function() action) _delay;

  /// The coalescing window for rapid band changes (spec §24).
  final Duration bandUpdateThrottle;

  final StreamController<AudioEffectsState> _stateController =
      StreamController<AudioEffectsState>.broadcast(sync: true);

  AudioEffectsState _state = const AudioEffectsState();
  StreamSubscription<int?>? _sessionIdSub;

  /// The player's audio session id, or null before the first source is loaded.
  int? _sessionId;

  /// Gains waiting for the backend to report its bands (Android only resolves
  /// them after the first load, so restored settings are held here until then).
  List<double> _pendingGains = const [];

  /// Bands with an open coalescing window, and the newest value each of them
  /// still owes the platform (spec §24).
  final Set<int> _coalescedBands = <int>{};
  final Map<int, double> _coalescedGains = <int, double>{};

  /// Invalidates armed windows when a preset/reset takes over every band.
  int _bandWindowGeneration = 0;

  /// Completes when the in-flight native push run (including any coalesced
  /// re-run it owes) has finished; null while no push is in flight.
  Completer<void>? _nativePushDrain;

  /// Set when the state changed while a native push was crossing the platform
  /// channel, so that push re-runs with the newest values instead of leaving the
  /// effect on a stale gain (spec §24, native side).
  bool _nativePushQueued = false;

  bool _initialized = false;
  bool _disposed = false;

  /// Completes when [initialize] finishes (see [ready]).
  final Completer<void> _readyCompleter = Completer<void>();

  /// The pipeline to attach to the app's single `ja.AudioPlayer`.
  ///
  /// Null when a non-`just_audio` backend is injected (tests), in which case the
  /// player is built without effects.
  ja.AudioPipeline? get audioPipeline {
    final backend = _backend;
    return backend is JustAudioEffectsBackend ? backend.audioPipeline : null;
  }

  /// Live audio-effects state.
  Stream<AudioEffectsState> get stateStream => _stateController.stream;

  /// Snapshot of the current audio-effects state.
  AudioEffectsState get state => _state;

  /// Whether the platform exposes a usable equalizer at all.
  bool get isSupported => _state.supported;

  /// Whether bass boost is available on this device.
  bool get bassBoostSupported => _state.bassBoostAvailable;

  /// Whether the spatial virtualizer is available on this device.
  bool get virtualizerSupported => _state.virtualizerAvailable;

  /// Restores the persisted settings and resolves the backend's bands.
  ///
  /// Called after the audio handler exists, and **never awaited on the audio
  /// path**: audio playback must not wait for optional effects (spec §17). Every
  /// step is individually guarded, so a failing store, backend or platform call
  /// disables that one effect and leaves playback running. [ready] completes
  /// either way, and later calls are a no-op.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final persisted = await _preferences?.load();
      if (persisted != null) {
        _state = _state.copyWith(
          equalizerEnabled: persisted.equalizerEnabled,
          presetId: persisted.presetId,
          preampEnabled: persisted.preampEnabled,
          preampDb: _clampPreamp(persisted.preampDb),
          bassBoostEnabled: persisted.bassBoostEnabled,
          bassBoostStrength: persisted.bassBoostStrength,
          virtualizerEnabled: persisted.virtualizerEnabled,
          virtualizerStrength: persisted.virtualizerStrength,
        );
        _pendingGains = List<double>.unmodifiable(persisted.bandGains);
      }
    } catch (_) {
      // The preferences store is optional: start from the defaults instead of
      // failing startup (spec §17).
    }
    _emit();

    // Safe before the player has loaded a source: just_audio stores the value
    // and re-applies it when the effect becomes active. Guarded so a backend
    // that cannot offer an equalizer simply ends up unsupported instead of
    // breaking playback (spec §22). The preamp, bass boost and virtualizer need
    // no startup call at all — they are `AudioEffect`s bound to the player's
    // audio session, so `_pushNativeEffects` (run on the session id stream)
    // applies them as soon as a session actually exists.
    await _guard(
      () => _backend.setEqualizerEnabled(_state.equalizerEnabled),
      onFailure: _markEqualizerUnavailable,
    );

    unawaited(_guard(_resolveBands));
    unawaited(_guard(_pushNativeEffects));
    _readyCompleter.complete();
  }

  /// Completes when the startup restore finished — successfully or not.
  ///
  /// Nothing on the audio path awaits this (spec §17/§18); it exists so the UI
  /// can wait for the restored settings if it wants to.
  Future<void> get ready => _readyCompleter.future;

  /// Runs an optional effect step, turning any failure into "that effect is
  /// unavailable" instead of an exception that could reach the audio path
  /// (spec §22). [onFailure] is where the state learns about it, so the UI can
  /// show a plain message instead of an Android exception.
  Future<void> _guard(
    Future<void> Function() step, {
    void Function()? onFailure,
  }) async {
    try {
      await step();
    } catch (_) {
      onFailure?.call();
    }
  }

  /// Marks the equalizer itself unusable (spec §22) while leaving the stored
  /// settings alone, so playback continues and the UI can say the device does
  /// not support it.
  void _markEqualizerUnavailable() {
    if (_disposed || !_state.supported) return;
    _state = _state.copyWith(supported: false, parametersReady: false);
    _emit();
  }

  /// Marks the native effects unusable (spec §22).
  ///
  /// The preamp, bass boost and virtualizer each fail independently, so the
  /// device's own report of what it supports is written straight into the
  /// snapshot. A preamp that cannot be created only disables **itself** — the
  /// equalizer's band curve and presets stay exactly as they were, because they
  /// live outside this path entirely.
  ///
  /// The stored settings are never touched, so a device that recovers can be
  /// re-enabled: any later successful push writes the device's own report back
  /// into the snapshot.
  void _markNativeEffectsUnavailable() {
    if (_disposed) return;
    if (!_state.preampAvailable &&
        !_state.bassBoostAvailable &&
        !_state.virtualizerAvailable) {
      return;
    }
    _state = _state.copyWith(
      preampAvailable: false,
      bassBoostAvailable: false,
      virtualizerAvailable: false,
      bassBoostStrengthSupported: false,
      virtualizerStrengthSupported: false,
    );
    _emit();
  }

  Future<void> _resolveBands() async {
    final config = await _backend.bands;
    if (_disposed) return;

    final bands = config.bands;
    var state = _state.copyWith(
      supported: config.supported,
      parametersReady: config.supported,
      resolved: true,
      minDecibels: config.minDecibels,
      maxDecibels: config.maxDecibels,
      bands: bands,
    );
    // The stored preamp gain is re-clamped once the effect has reported the
    // range it actually accepts; until then the documented platform bounds stand.
    state = state.copyWith(preampDb: _clampPreamp(state.preampDb));

    if (config.supported && bands.isNotEmpty) {
      // Re-apply the restored gains onto the real band layout, clamped to the
      // range this backend actually reports.
      double clamp(double gain) =>
          gain.clamp(config.minDecibels, config.maxDecibels).toDouble();
      final gains = List<double>.generate(
        bands.length,
        (index) => clamp(_resample(_pendingGains, index, bands.length)),
        growable: false,
      );
      state = state.copyWith(
        bands: bands
            .map((band) => band.copyWith(gain: gains[band.index]))
            .toList(growable: false),
      );
      for (var index = 0; index < gains.length; index++) {
        await _sendBandGain(index, gains[index]);
      }
    }

    _state = state;
    _pendingGains = const [];

    // Resolving the bands means the audio session is finally up. The preamp is
    // not on the just_audio pipeline (it is created natively against this very
    // session id), so nothing extra is re-sent here — `_pushNativeEffects` runs
    // from the session id stream and applies it.
    _emit();
  }

  /// Maps a stored gain curve onto [bandCount] bands, returning 0 dB when
  /// nothing was stored. A device that reports a different band count than the
  /// one that saved the settings gets the curve resampled, not dropped.
  double _resample(List<double> stored, int index, int bandCount) {
    if (stored.isEmpty || bandCount <= 0) return 0;
    if (stored.length == bandCount) return stored[index];
    if (stored.length == 1) return stored.first;
    final position = index / (bandCount - 1) * (stored.length - 1);
    final lower = position.floor().clamp(0, stored.length - 1);
    final upper = position.ceil().clamp(0, stored.length - 1);
    if (lower == upper) return stored[lower];
    final t = position - lower;
    return stored[lower] + (stored[upper] - stored[lower]) * t;
  }

  double _clampGain(double gain) =>
      gain.clamp(_state.minDecibels, _state.maxDecibels).toDouble();

  /// Clamps a preamp gain to the **preamp's own** range, not the bands' range.
  ///
  /// Android's loudness enhancer only boosts (`0 dB` = no amplification) and
  /// documents nothing below that, so clamping a preamp to the equalizer's
  /// -12 dB floor would ask the platform for a gain it does not perform.
  double _clampPreamp(double decibels) =>
      decibels.clamp(_state.preampMinDecibels, _state.preampMaxDecibels).toDouble();

  /// Routes the player's audio session id stream in (called by the audio handler
  /// when the single player is created).
  ///
  /// The native bass boost / virtualizer are bound to that session, and Android
  /// requires them to be re-created whenever the session id changes.
  void bindSessionIdStream(Stream<int?> sessionIds) {
    _sessionIdSub?.cancel();
    _sessionIdSub = sessionIds.listen(_onSessionIdChanged);
  }

  /// A new session id means every effect attached to the old one is gone.
  ///
  /// The native effects are re-created for the new session here, and the
  /// equalizer's enabled flag + band gains are re-sent too: just_audio rebuilds
  /// its own `AudioEffect` objects from a snapshot taken at platform-init time
  /// whenever the session changes, so without this a curve the user set after
  /// startup would silently revert to whatever it was at first play. This is the
  /// session-change half of spec §20; `reapplyEffects()` is the explicit hook.
  void _onSessionIdChanged(int? sessionId) {
    if (_disposed || sessionId == _sessionId) return;
    _sessionId = sessionId;
    if (sessionId == null) {
      unawaited(_guard(_nativeBridge.release));
      return;
    }
    unawaited(reapplyEffects());
  }

  /// Re-applies every effect to the current audio session (spec §20).
  ///
  /// Android can recreate or swap the underlying audio session whenever the
  /// output device changes (phone speaker → wired headphones → Bluetooth → USB
  /// DAC → Bluetooth speaker), and both a just_audio `AudioEffect` and a native
  /// `AudioEffect` are bound to the session they were created with — so the
  /// equalizer's gains and the preamp/bass boost/virtualizer all have to be
  /// pushed again afterwards. This is that explicit entry point; the session id
  /// stream calls it automatically, and it can be wired to the remaining
  /// device-change callbacks too.
  ///
  /// It only ever re-sends the current settings, so it can never interrupt the
  /// current song, the playback position, the queue or background playback
  /// (spec §19).
  Future<void> reapplyEffects() async {
    if (_disposed) return;
    await _guard(
      () => _backend.setEqualizerEnabled(_state.equalizerEnabled),
      onFailure: _markEqualizerUnavailable,
    );
    final bands = _state.bands;
    for (var index = 0; index < bands.length; index++) {
      await _sendBandGain(index, bands[index].gain);
    }
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Applies the preamp, bass boost and virtualizer to the current session.
  ///
  /// Pushes are **serialized and coalesced, newest value wins** — the same reason
  /// the band gains get a throttle window (spec §24). Every slider callback here
  /// is fire-and-forget, so a drag used to leave a dozen `apply` calls crossing
  /// the platform channel at once; they complete out of order and the native
  /// side applies `setTargetGain` in *completion* order, so the gain the effect
  /// ended up with was whichever value happened to land last — in practice an
  /// early one. For the preamp that is close to a silent bug, because Android
  /// documents `0 mB` as "no amplification": the slider showed a large boost
  /// while the effect sat at no boost at all.
  ///
  /// So a push that arrives while one is in flight is not queued behind it as an
  /// independent call — it marks the run dirty and lets the in-flight run loop
  /// once more with the newest state. The last push issued therefore always
  /// carries the current values, and callers awaiting a queued push wait for that
  /// drain to finish.
  Future<void> _pushNativeEffects() async {
    if (_disposed) return;
    final drain = _nativePushDrain;
    if (drain != null) {
      _nativePushQueued = true;
      return drain.future;
    }
    final completer = Completer<void>();
    _nativePushDrain = completer;
    try {
      do {
        _nativePushQueued = false;
        await _pushNativeEffectsOnce();
      } while (_nativePushQueued && !_disposed);
    } finally {
      _nativePushDrain = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// One round trip to the native side, carrying the state as it is right now.
  ///
  /// A no-op until a session id exists — all three are `AudioEffect`s that cannot
  /// be constructed before the player owns a session, so there is nothing to
  /// report yet ([AudioEffectsState.nativeResolved] stays false and the UI shows
  /// a waiting state rather than claiming the device lacks the effect).
  Future<void> _pushNativeEffectsOnce() async {
    final sessionId = _sessionId;
    if (_disposed || sessionId == null) return;
    final support = await _nativeBridge.apply(
      sessionId: sessionId,
      preampEnabled: _state.preampEnabled,
      preampDb: _state.preampDb,
      bassBoostEnabled: _state.bassBoostEnabled,
      bassBoostStrength: _state.bassBoostStrength,
      virtualizerEnabled: _state.virtualizerEnabled,
      virtualizerStrength: _state.virtualizerStrength,
    );
    if (_disposed) return;
    // Availability, ranges and the device's own strength capabilities live in
    // the snapshot so the UI rebuilds the moment the session makes them usable.
    // The reported preamp range replaces the documented platform bounds, and the
    // stored gain is re-clamped onto it so a slider is never shown a value the
    // effect will refuse (spec §6).
    _state = _state.copyWith(
      preampAvailable: support.preamp,
      preampMinDecibels: support.preampMinDb,
      preampMaxDecibels: support.preampMaxDb,
      nativeResolved: true,
      bassBoostAvailable: support.bassBoost,
      bassBoostStrengthSupported: support.bassBoostStrengthSupported,
      virtualizerAvailable: support.virtualizer,
      virtualizerStrengthSupported: support.virtualizerStrengthSupported,
      bassBoostRange: support.bassBoostRange,
      virtualizerRange: support.virtualizerRange,
    );
    _state = _state.copyWith(preampDb: _clampPreamp(_state.preampDb));
    _emit();
  }

  /// Engages or bypasses the equalizer.
  Future<void> setEqualizerEnabled(bool enabled) async {
    _state = _state.copyWith(equalizerEnabled: enabled);
    _emit();
    await _guard(
      () => _backend.setEqualizerEnabled(enabled),
      onFailure: _markEqualizerUnavailable,
    );
    _persist();
  }

  /// Sets the gain of the band at [index] (in decibels, clamped to the
  /// backend's range).
  ///
  /// The state (and therefore the slider) updates **immediately**, but the
  /// platform is only told about one change per throttle window, with the latest
  /// value winning (spec §24). Nothing here reloads or restarts the player
  /// (spec §23) — it is a single band-gain update.
  Future<void> setBandGain(int index, double gain) async {
    final clamped = _clampGain(gain);
    final bands = _state.bands;
    if (index < 0 || index >= bands.length) return;

    _state = _state.copyWith(
      bands: bands
          .map((band) => band.index == index ? band.copyWith(gain: clamped) : band)
          .toList(growable: false),
      presetId: null,
    );
    _pendingGains = List<double>.unmodifiable(_state.bandGains);
    _emit();
    await _pushBandGain(index, clamped);
  }

  /// Sends one band gain, coalescing a rapid burst into a single trailing
  /// update (spec §24).
  Future<void> _pushBandGain(int index, double gain) async {
    if (_disposed) return;
    if (_coalescedBands.contains(index)) {
      // A window is already open for this band: remember the newest value and
      // let the open window deliver it.
      _coalescedGains[index] = gain;
      return;
    }

    _coalescedBands.add(index);
    final generation = _bandWindowGeneration;
    unawaited(
      _delay(bandUpdateThrottle, () {
        if (_disposed || generation != _bandWindowGeneration) return;
        _coalescedBands.remove(index);
        final latest = _coalescedGains.remove(index) ?? gain;
        unawaited(_sendBandGain(index, latest));
      }),
    );
    await _sendBandGain(index, gain);
  }

  Future<void> _sendBandGain(int index, double gain) async {
    if (_disposed) return;
    await _guard(
      () => _backend.setBandGain(index, gain),
      onFailure: _markEqualizerUnavailable,
    );
    _persist();
  }

  /// Sends any band gains still waiting behind an open throttle window.
  ///
  /// Used by [dispose] so a drag that ended a moment before shutdown is not
  /// lost, and by tests that want the coalesced update to land deterministically.
  Future<void> flushBandGains() async {
    if (_coalescedGains.isEmpty) return;
    final pending = Map<int, double>.from(_coalescedGains);
    _coalescedGains.clear();
    for (final entry in pending.entries) {
      await _sendBandGain(entry.key, entry.value);
    }
  }

  /// Drops any band gain still waiting behind a throttle window.
  ///
  /// A preset or a reset writes every band itself, so a coalesced slider value
  /// from before must not land on top of it afterwards. Bumping the generation
  /// makes the already-armed windows no-ops.
  void _supersedePendingBandGains() {
    _bandWindowGeneration++;
    _coalescedBands.clear();
    _coalescedGains.clear();
  }

  /// Engages or bypasses the preamp.
  ///
  /// Independent of the equalizer's own switch: the preamp is a separate effect
  /// (spec §11), so raising it does not require the band sliders to be engaged.
  /// Bypassing never clears the stored gain.
  ///
  /// Engaging from nothing starts at [defaultPreampDb] rather than at the stored
  /// 0 dB: Android documents `0 mB` as "no amplification", so switching the preamp
  /// on while its gain was still at the bottom did nothing at all and read as a
  /// dead control. A gain the user chose — or one restored from the preferences —
  /// is never overwritten, so this only fires on a genuinely fresh engage.
  Future<void> setPreampEnabled(bool enabled) async {
    var state = _state.copyWith(preampEnabled: enabled);
    if (enabled &&
        !_state.preampEnabled &&
        state.preampDb <= _state.preampMinDecibels) {
      state = state.copyWith(preampDb: _clampPreamp(defaultPreampDb));
    }
    _state = state;
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Sets the preamp gain (in decibels), clamped to the **preamp's own** range
  /// (spec §6).
  ///
  /// The range is the one the platform reported for `LoudnessEnhancer` (`0 dB` =
  /// no amplification up to its documented maximum), so the preamp is never
  /// mapped onto the bands' symmetric ±12 dB range, which the effect does not
  /// perform. Both the state and the engine are updated; nothing about playback
  /// is touched (spec §19).
  Future<void> setPreampGain(double decibels) async {
    final clamped = _clampPreamp(decibels);
    _state = _state.copyWith(preampDb: clamped);
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Engages or bypasses bass boost.
  Future<void> setBassBoostEnabled(bool enabled) async {
    _state = _state.copyWith(bassBoostEnabled: enabled);
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Sets the bass boost strength (0.0–1.0).
  Future<void> setBassBoost(double strength) async {
    final clamped = strength.clamp(0.0, 1.0).toDouble();
    _state = _state.copyWith(bassBoostStrength: clamped);
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Engages or bypasses the spatial (virtualizer) effect.
  Future<void> setVirtualizerEnabled(bool enabled) async {
    _state = _state.copyWith(virtualizerEnabled: enabled);
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Sets the virtualizer strength (0.0–1.0).
  Future<void> setVirtualizer(double strength) async {
    final clamped = strength.clamp(0.0, 1.0).toDouble();
    _state = _state.copyWith(virtualizerStrength: clamped);
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  /// Applies a named preset, resampled onto the backend's real band count.
  ///
  /// A preset carries gains only (spec §8), so nothing but the band gains and
  /// the active [EqPreset] id change here — the preamp and the native effects
  /// are deliberately left as they are. Every band is sent in one go (a discrete
  /// action, not a drag), and any coalesced slider value still waiting is
  /// dropped so it cannot overwrite the curve afterwards (spec §24).
  Future<void> applyPreset(EqPreset preset) async {
    _supersedePendingBandGains();
    final bands = _state.bands;
    final gains = preset.sampleFor(
      bands.length,
      minDecibels: _state.minDecibels,
      maxDecibels: _state.maxDecibels,
    );
    if (bands.isNotEmpty) {
      _state = _state.copyWith(
        bands: bands
            .map((band) => band.copyWith(gain: gains[band.index]))
            .toList(growable: false),
      );
      for (var index = 0; index < gains.length; index++) {
        await _sendBandGain(index, gains[index]);
      }
    }
    _pendingGains = List<double>.unmodifiable(gains);
    _state = _state.copyWith(presetId: preset.id);
    _emit();
    _persist();
  }

  /// Applies a preset by id; unknown ids are ignored.
  Future<void> applyPresetById(String id) async {
    final preset = eqPresetById(id);
    if (preset == null) return;
    await applyPreset(preset);
  }

  /// Resets the equalizer (spec §10): flat band gains, the "Normal" preset,
  /// a zeroed preamp, and bass boost + virtualizer off.
  ///
  /// Only audio processing is touched — volume, the queue, the playback
  /// position, favorites, playlists and playback history are untouched because
  /// they live outside this service entirely.
  Future<void> reset() async {
    await applyPreset(eqNormalPreset);
    _state = _state.copyWith(
      preampEnabled: false,
      preampDb: 0,
      bassBoostEnabled: false,
      bassBoostStrength: 0,
      virtualizerEnabled: false,
      virtualizerStrength: 0,
    );
    _emit();
    _persist();
    await _guard(_pushNativeEffects, onFailure: _markNativeEffectsUnavailable);
  }

  void _emit() {
    if (_disposed || _stateController.isClosed) return;
    _stateController.add(_state);
  }

  void _persist() {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(preferences.save(_toPersisted()));
  }

  PersistedAudioEffectsSettings _toPersisted() {
    return PersistedAudioEffectsSettings(
      equalizerEnabled: _state.equalizerEnabled,
      presetId: _state.presetId,
      bandGains: _pendingGains.isNotEmpty
          ? _pendingGains
          : _state.bandGains,
      preampEnabled: _state.preampEnabled,
      preampDb: _state.preampDb,
      bassBoostEnabled: _state.bassBoostEnabled,
      bassBoostStrength: _state.bassBoostStrength,
      virtualizerEnabled: _state.virtualizerEnabled,
      virtualizerStrength: _state.virtualizerStrength,
    );
  }

  /// Releases the native effects and closes the state stream.
  ///
  /// A band value still waiting behind a throttle window is sent first, so a
  /// drag that ended moments earlier is not lost (spec §24).
  Future<void> dispose() async {
    if (_disposed) return;
    await flushBandGains();
    _supersedePendingBandGains();
    _disposed = true;
    await _sessionIdSub?.cancel();
    await _guard(_nativeBridge.release);
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }
}

/// Provider for the app-wide [AudioEffectsService].
///
/// Uses the instance created in `main()` when available (the one whose effects
/// are baked into the real player's pipeline) and otherwise creates a detached
/// instance so tests never depend on `main()` having run.
///
/// Only a **detached** instance is disposed with the container: the app-wide
/// service outlives every UI container, so a widget, route or test container
/// going away can never release the effects that are still processing audio in
/// the background (spec §18 — the UI is never what keeps the equalizer alive,
/// and never what kills it either).
final audioEffectsServiceProvider = Provider<AudioEffectsService>((ref) {
  final shared = globalAudioEffects;
  if (shared != null) return shared;
  final service = AudioEffectsService();
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive audio-effects state (spec §2's reactive state requirement).
///
/// Yields the current snapshot, then every change — including the moment the
/// backend reports its band configuration.
final audioEffectsStateProvider = StreamProvider<AudioEffectsState>((ref) async* {
  final service = ref.watch(audioEffectsServiceProvider);
  unawaited(service.initialize());
  yield service.state;
  yield* service.stateStream;
});
