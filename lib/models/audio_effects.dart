/// Phase 4B audio-effects models.
///
/// The equalizer's band configuration is **not** hard-coded: it is queried from
/// the audio backend (Android's `android.media.audiofx.Equalizer` via
/// just_audio's `AndroidEqualizer`), so [EqBand] simply mirrors whatever the
/// device reports — including the gain range ([EqBandsConfig.minDecibels] /
/// [maxDecibels], spec §6). A preset is a *curve* of gain values (spec §8)
/// mapped onto the real band count ([EqPreset.sampleFor]) and is only offered
/// when it genuinely fits those bands ([EqPreset.appliesTo], spec §7).
library;

import 'dart:convert';

/// A single equalizer band, as reported by the audio backend.
class EqBand {
  const EqBand({
    required this.index,
    required this.centerFrequency,
    required this.lowerFrequency,
    required this.upperFrequency,
    this.gain = 0.0,
  });

  /// Zero-based position of this band within the equalizer.
  final int index;

  /// Center frequency of the band in hertz (e.g. 1000.0).
  final double centerFrequency;

  /// Lower edge of the band in hertz.
  final double lowerFrequency;

  /// Upper edge of the band in hertz.
  final double upperFrequency;

  /// Current gain for this band in decibels.
  final double gain;

  EqBand copyWith({double? gain}) {
    return EqBand(
      index: index,
      centerFrequency: centerFrequency,
      lowerFrequency: lowerFrequency,
      upperFrequency: upperFrequency,
      gain: gain ?? this.gain,
    );
  }

  /// Compact frequency label for the UI (e.g. `1k`, `3.6k`, `14k`).
  String get frequencyLabel => formatFrequency(centerFrequency);

  @override
  bool operator ==(Object other) {
    return other is EqBand &&
        other.index == index &&
        other.centerFrequency == centerFrequency &&
        other.lowerFrequency == lowerFrequency &&
        other.upperFrequency == upperFrequency &&
        other.gain == gain;
  }

  @override
  int get hashCode =>
      Object.hash(index, centerFrequency, lowerFrequency, upperFrequency, gain);

  @override
  String toString() => 'EqBand($index, $frequencyLabel, ${gain}dB)';
}

/// Formats a frequency in hertz as a short label: `60`, `1k`, `3.6k`, `14k`.
String formatFrequency(double hz) {
  if (hz >= 1000) {
    final khz = hz / 1000;
    final text = khz == khz.roundToDouble()
        ? khz.toStringAsFixed(0)
        : khz.toStringAsFixed(1);
    return '${text}k';
  }
  return hz.toStringAsFixed(0);
}

/// A named equalizer preset.
///
/// A preset is **just a list of gain values** (spec §8) — it never carries a
/// preamp or an enabled flag, so applying one only ever writes band gains.
/// [gains] is sampled at evenly spaced points from the lowest to the highest
/// frequency; Android equalizers expose different band counts per device
/// (commonly 5, sometimes 3 or 10), so [sampleFor] maps the curve onto the real
/// band count and [appliesTo] decides whether the preset can be offered at all
/// (spec §7).
class EqPreset {
  const EqPreset({
    required this.id,
    required this.label,
    required this.gains,
  });

  /// Stable id used for persistence (never the mutable [label]).
  final String id;

  /// Human-readable name shown in the preset list.
  final String label;

  /// Gain in decibels at evenly spaced points across the spectrum.
  final List<double> gains;

  /// Whether this preset can actually be applied to an equalizer with
  /// [bandCount] bands (spec §7).
  ///
  /// A preset whose curve has more points than the device has bands would have
  /// to drop curve points to fit, so it is **not** offered. More bands than the
  /// curve needs is fine — [sampleFor] stretches the curve over them.
  bool appliesTo(int bandCount) => bandCount > 0 && bandCount >= gains.length;

  /// Resamples this curve onto [bandCount] bands, clamping each value to
  /// [minDecibels]/[maxDecibels] — the range the backend actually reported.
  List<double> sampleFor(int bandCount, {double? minDecibels, double? maxDecibels}) {
    if (bandCount <= 0) return const [];
    final min = minDecibels ?? -12;
    final max = maxDecibels ?? 12;

    double clamp(double value) => value.clamp(min, max).toDouble();

    if (gains.isEmpty) return List<double>.filled(bandCount, 0);
    if (bandCount == 1) return [clamp(gains.first)];

    return List<double>.generate(bandCount, (band) {
      final position = band / (bandCount - 1) * (gains.length - 1);
      final lower = position.floor();
      final upper = position.ceil();
      if (lower == upper) return clamp(gains[lower]);
      final t = position - lower;
      return clamp(gains[lower] + (gains[upper] - gains[lower]) * t);
    });
  }

  @override
  String toString() => 'EqPreset($id)';
}

/// The "Normal" preset: every band flat. Always present, and the target
/// `Reset` restores (spec §10).
const EqPreset eqNormalPreset = EqPreset(
  id: 'normal',
  label: 'Normal',
  gains: [0, 0, 0, 0, 0],
);

/// The built-in equalizer presets (spec §7).
///
/// Each is a five-point curve (the most common Android band count), so a device
/// with 3 bands is only offered presets it can genuinely apply (none) while 5-
/// and 10-band devices get the full row. Adding or retuning a preset is a
/// one-line change here.
const List<EqPreset> eqPresets = <EqPreset>[
  eqNormalPreset,
  EqPreset(id: 'acoustic', label: 'Acoustic', gains: [4, 3, 0, 2, 3]),
  EqPreset(id: 'bass_booster', label: 'Bass Booster', gains: [8, 5, 0, -2, -4]),
  EqPreset(id: 'bass_reducer', label: 'Bass Reducer', gains: [-8, -5, 0, 2, 4]),
  EqPreset(id: 'classical', label: 'Classical', gains: [5, 3, 0, -2, -4]),
  EqPreset(id: 'dance', label: 'Dance', gains: [7, 4, 0, 2, 5]),
  EqPreset(id: 'deep', label: 'Deep', gains: [7, 6, 2, 0, -3]),
  EqPreset(id: 'electronic', label: 'Electronic', gains: [6, 3, 0, 3, 7]),
  EqPreset(id: 'hip_hop', label: 'Hip-Hop', gains: [7, 4, 1, -1, 2]),
  EqPreset(id: 'jazz', label: 'Jazz', gains: [4, 2, 0, 2, 4]),
  EqPreset(id: 'pop', label: 'Pop', gains: [-2, 2, 4, 2, -1]),
  EqPreset(id: 'rock', label: 'Rock', gains: [6, 3, -2, -1, 5]),
  EqPreset(id: 'vocal', label: 'Vocal', gains: [-3, 2, 5, 3, -1]),
];

/// The presets that can be applied to an equalizer with [bandCount] bands
/// (spec §7 — presets that don't fit are never offered).
List<EqPreset> eqPresetsFor(int bandCount) => eqPresets
    .where((preset) => preset.appliesTo(bandCount))
    .toList(growable: false);

/// Looks up a preset by its [id]; null when unknown.
EqPreset? eqPresetById(String? id) {
  if (id == null) return null;
  for (final preset in eqPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Encodes band gains as a JSON list of doubles (persistence format).
String encodeBandGains(List<double> gains) => jsonEncode(gains);

/// Decodes a persisted JSON list of band gains; returns an empty list when the
/// payload is missing or malformed.
List<double> decodeBandGains(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map((value) => value is num ? value.toDouble() : double.nan)
        .where((value) => !value.isNaN)
        .toList();
  } on FormatException {
    return const [];
  }
}

/// The equalizer configuration reported by the audio backend.
///
/// Deliberately dynamic (spec §5): [bands] is whatever the platform exposes —
/// Android equalizers commonly report 5 bands, but the count and center
/// frequencies are device-specific, so the UI is built from this instead of a
/// hard-coded 60/230/910/3.6k/14k layout.
class EqBandsConfig {
  const EqBandsConfig({
    this.supported = false,
    this.minDecibels = -12,
    this.maxDecibels = 12,
    this.bands = const [],
  });

  /// An empty config: the platform has no usable equalizer.
  static const EqBandsConfig unsupported = EqBandsConfig();

  /// Whether the backend exposes a usable equalizer.
  final bool supported;

  /// Minimum gain in decibels.
  final double minDecibels;

  /// Maximum gain in decibels.
  final double maxDecibels;

  /// The backend's bands, in order.
  final List<EqBand> bands;

  /// Number of exposed bands.
  int get bandCount => bands.length;
}

/// The strength range a native effect actually supports on this device
/// (spec §12/§13).
///
/// `BassBoost` and `Virtualizer` expose their own `getStrengthRange()`, and it is
/// **not** guaranteed to be the documented 0–1000 per-mille scale, so the app
/// never assumes it: strengths are stored normalized (0.0–1.0) and mapped onto
/// whatever the platform reports.
class StrengthRange {
  const StrengthRange({this.min = 0, this.max = 1000});

  /// The full per-mille range every Android audio effect documents; used until
  /// the platform reports its own range.
  static const StrengthRange full = StrengthRange();

  /// Lowest strength the device accepts.
  final int min;

  /// Highest strength the device accepts.
  final int max;

  /// Maps a normalized 0.0–1.0 strength onto this device's range.
  int map(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0);
    return min + (clamped * (max - min)).round();
  }

  /// Whether this is the documented 0–1000 range.
  bool get isDefault => min == full.min && max == full.max;

  @override
  bool operator ==(Object other) =>
      other is StrengthRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'StrengthRange($min..$max)';
}

/// An immutable snapshot of every audio-processing setting (Phase 4B).
class AudioEffectsState {
  const AudioEffectsState({
    this.supported = false,
    this.parametersReady = false,
    this.resolved = false,
    this.equalizerEnabled = false,
    this.bands = const [],
    this.minDecibels = -12,
    this.maxDecibels = 12,
    this.preampEnabled = false,
    this.preampAvailable = false,
    this.nativeResolved = false,
    this.preampMinDecibels = 0,
    this.preampMaxDecibels = 20,
    this.preampDb = 0,
    this.bassBoostEnabled = false,
    this.bassBoostStrength = 0,
    this.bassBoostAvailable = false,
    this.bassBoostStrengthSupported = false,
    this.bassBoostRange = StrengthRange.full,
    this.virtualizerEnabled = false,
    this.virtualizerStrength = 0,
    this.virtualizerAvailable = false,
    this.virtualizerStrengthSupported = false,
    this.virtualizerRange = StrengthRange.full,
    this.presetId,
  });

  /// Whether the platform/backend exposes a usable equalizer at all (false on
  /// desktop/web and on devices without the effect).
  final bool supported;

  /// Whether the backend's band configuration has been resolved yet. Android
  /// only reports its bands after the first source is loaded, so the UI shows a
  /// waiting state until then.
  final bool parametersReady;

  /// Whether the backend has answered at all. `false` means "not known yet"
  /// (the query is still pending), which is different from [supported] being
  /// `false` ("answered: no equalizer on this device").
  final bool resolved;

  /// Whether the equalizer is engaged.
  final bool equalizerEnabled;

  /// The backend's bands, each carrying its current gain.
  final List<EqBand> bands;

  /// How many bands the backend exposed.
  int get bandCount => bands.length;

  /// Minimum gain in decibels supported by the backend.
  final double minDecibels;

  /// Maximum gain in decibels supported by the backend.
  final double maxDecibels;

  /// Whether the preamp is engaged.
  ///
  /// The preamp is a separate effect from the equalizer, so it has its own
  /// engage flag: it can be raised with the band sliders bypassed, and
  /// bypassing it never clears the stored gain.
  final bool preampEnabled;

  /// Whether the backend reported the preamp as available. Part of the snapshot
  /// (not just the service) so the UI rebuilds when a failure disables it
  /// without ever touching the equalizer (spec §22).
  final bool preampAvailable;

  /// Whether the native bridge has reported what this device supports yet.
  ///
  /// The preamp, bass boost and virtualizer are `AudioEffect`s bound to the
  /// player's audio session, so nothing can be created until a track is playing
  /// and the session id exists. `false` therefore means "not known yet" — which
  /// is what the UI shows before the first song — and is deliberately different
  /// from [preampAvailable] being `false` ("the device has no such effect").
  /// Without this the preamp screen claimed "not available on this device" for
  /// every user who opened it before playing anything.
  final bool nativeResolved;

  /// Lowest preamp gain in decibels the backend accepts.
  ///
  /// Independent of [minDecibels]: Android's loudness enhancer documents
  /// `0 dB` as "no amplification" and only ever boosts, so a preamp slider
  /// spanning the equalizer's -12 dB floor is asking the platform for
  /// something it does not do.
  final double preampMinDecibels;

  /// Highest preamp gain in decibels the backend accepts.
  final double preampMaxDecibels;

  /// Preamp gain in decibels (Android's `LoudnessEnhancer`).
  final double preampDb;

  /// Whether bass boost is engaged.
  final bool bassBoostEnabled;

  /// Bass boost strength, 0.0–1.0.
  final double bassBoostStrength;

  /// Whether the native bridge reported bass boost as available. Part of the
  /// snapshot (not just the service) so the UI rebuilds the moment the audio
  /// session makes the effect usable.
  final bool bassBoostAvailable;

  /// Whether the device lets the bass boost strength be changed at all
  /// (`BassBoost.getStrengthSupported()`). When false the effect is still
  /// switchable but its slider is hidden with an explanation.
  final bool bassBoostStrengthSupported;

  /// The strength scale this device's bass boost accepts (spec §12).
  final StrengthRange bassBoostRange;

  /// Whether the spatial (virtualizer) effect is engaged.
  final bool virtualizerEnabled;

  /// Virtualizer strength, 0.0–1.0.
  final double virtualizerStrength;

  /// Whether the native bridge reported the virtualizer as available.
  final bool virtualizerAvailable;

  /// Whether the virtualizer's strength can be changed on this device.
  final bool virtualizerStrengthSupported;

  /// The strength scale this device's virtualizer accepts (spec §13).
  final StrengthRange virtualizerRange;

  /// Id of the active preset, or null when the bands are custom.
  final String? presetId;

  /// Whether any effect is currently engaged.
  bool get anyEnabled =>
      equalizerEnabled || preampEnabled || bassBoostEnabled || virtualizerEnabled;

  /// The active preset, or null when the bands are custom/unknown.
  EqPreset? get preset => eqPresetById(presetId);

  /// Current gains in decibels, one per band.
  List<double> get bandGains =>
      bands.map((band) => band.gain).toList(growable: false);

  /// Whether the current gains differ from the [preset] (i.e. the user has
  /// hand-edited them).
  bool get isCustom => eqPresetById(presetId) == null;

  AudioEffectsState copyWith({
    bool? supported,
    bool? parametersReady,
    bool? resolved,
    bool? equalizerEnabled,
    List<EqBand>? bands,
    double? minDecibels,
    double? maxDecibels,
    bool? preampEnabled,
    bool? preampAvailable,
    bool? nativeResolved,
    double? preampMinDecibels,
    double? preampMaxDecibels,
    double? preampDb,
    bool? bassBoostEnabled,
    double? bassBoostStrength,
    bool? bassBoostAvailable,
    bool? bassBoostStrengthSupported,
    StrengthRange? bassBoostRange,
    bool? virtualizerEnabled,
    double? virtualizerStrength,
    bool? virtualizerAvailable,
    bool? virtualizerStrengthSupported,
    StrengthRange? virtualizerRange,
    Object? presetId = _unset,
  }) {
    return AudioEffectsState(
      supported: supported ?? this.supported,
      parametersReady: parametersReady ?? this.parametersReady,
      resolved: resolved ?? this.resolved,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      bands: bands ?? this.bands,
      minDecibels: minDecibels ?? this.minDecibels,
      maxDecibels: maxDecibels ?? this.maxDecibels,
      preampEnabled: preampEnabled ?? this.preampEnabled,
      preampAvailable: preampAvailable ?? this.preampAvailable,
      nativeResolved: nativeResolved ?? this.nativeResolved,
      preampMinDecibels: preampMinDecibels ?? this.preampMinDecibels,
      preampMaxDecibels: preampMaxDecibels ?? this.preampMaxDecibels,
      preampDb: preampDb ?? this.preampDb,
      bassBoostEnabled: bassBoostEnabled ?? this.bassBoostEnabled,
      bassBoostStrength: bassBoostStrength ?? this.bassBoostStrength,
      bassBoostAvailable: bassBoostAvailable ?? this.bassBoostAvailable,
      bassBoostStrengthSupported:
          bassBoostStrengthSupported ?? this.bassBoostStrengthSupported,
      bassBoostRange: bassBoostRange ?? this.bassBoostRange,
      virtualizerEnabled: virtualizerEnabled ?? this.virtualizerEnabled,
      virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
      virtualizerAvailable:
          virtualizerAvailable ?? this.virtualizerAvailable,
      virtualizerStrengthSupported:
          virtualizerStrengthSupported ?? this.virtualizerStrengthSupported,
      virtualizerRange: virtualizerRange ?? this.virtualizerRange,
      presetId: identical(presetId, _unset) ? this.presetId : presetId as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AudioEffectsState &&
        other.supported == supported &&
        other.parametersReady == parametersReady &&
        other.resolved == resolved &&
        other.equalizerEnabled == equalizerEnabled &&
        other.minDecibels == minDecibels &&
        other.maxDecibels == maxDecibels &&
        other.preampEnabled == preampEnabled &&
        other.preampAvailable == preampAvailable &&
        other.nativeResolved == nativeResolved &&
        other.preampMinDecibels == preampMinDecibels &&
        other.preampMaxDecibels == preampMaxDecibels &&
        other.preampDb == preampDb &&
        other.bassBoostEnabled == bassBoostEnabled &&
        other.bassBoostStrength == bassBoostStrength &&
        other.bassBoostAvailable == bassBoostAvailable &&
        other.bassBoostStrengthSupported == bassBoostStrengthSupported &&
        other.bassBoostRange == bassBoostRange &&
        other.virtualizerEnabled == virtualizerEnabled &&
        other.virtualizerStrength == virtualizerStrength &&
        other.virtualizerAvailable == virtualizerAvailable &&
        other.virtualizerStrengthSupported == virtualizerStrengthSupported &&
        other.virtualizerRange == virtualizerRange &&
        other.presetId == presetId &&
        _listEquals(other.bands, bands);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        supported,
        parametersReady,
        resolved,
        equalizerEnabled,
        minDecibels,
        maxDecibels,
        preampEnabled,
        preampAvailable,
        nativeResolved,
        preampMinDecibels,
        preampMaxDecibels,
        preampDb,
        bassBoostEnabled,
        bassBoostStrength,
        bassBoostAvailable,
        bassBoostStrengthSupported,
        bassBoostRange,
        virtualizerEnabled,
        virtualizerStrength,
        virtualizerAvailable,
        virtualizerStrengthSupported,
        virtualizerRange,
        presetId,
        Object.hashAll(bands),
      ]);

  @override
  String toString() {
    return 'AudioEffectsState(supported: $supported, eq: $equalizerEnabled, '
        'bands: ${bands.length}, '
        'preamp: ${preampEnabled ? '+' : ''}${preampDb}dB '
        '(available: $preampAvailable, resolved: $nativeResolved), '
        'bass: $bassBoostEnabled@$bassBoostStrength '
        '(available: $bassBoostAvailable, adjustable: $bassBoostStrengthSupported), '
        'virtualizer: $virtualizerEnabled@$virtualizerStrength '
        '(available: $virtualizerAvailable, adjustable: $virtualizerStrengthSupported))';
  }
}

const Object _unset = Object();

bool _listEquals(List<EqBand> a, List<EqBand> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
