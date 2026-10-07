import 'package:drift/drift.dart';

/// Persisted audio-effects settings (Phase 4B).
///
/// A **single-row** table (the app has one equalizer configuration, not one per
/// track or playlist): the primary key is the constant [singletonId], so the
/// service can read the row on startup, apply it to the audio backend, and
/// write it back whenever a slider or preset changes.
///
/// Band gains are stored as a JSON array of decibels (see
/// `encodeBandGains`/`decodeBandGains`) because the band count is decided by the
/// platform and differs per device — persisting one column per band would bake
/// this device's configuration into the schema.
@DataClassName('AudioEffectsSettingsRow')
class AudioEffectsSettings extends Table {
  /// The only row id ever used (single-row table).
  static const int rowId = 1;

  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Whether the equalizer is engaged.
  BoolColumn get equalizerEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Id of the active preset (`eqPresets`), or null when the bands are custom.
  TextColumn get presetId => text().nullable()();

  /// JSON array of per-band gains in decibels.
  TextColumn get bandGains => text().withDefault(const Constant('[]'))();

  /// Whether the preamp is engaged.
  ///
  /// Stored separately from [equalizerEnabled] because the preamp is its own
  /// effect: it can be raised with the bands bypassed, and bypassing the bands
  /// must not switch the preamp off (spec §11).
  BoolColumn get preampEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Preamp gain in decibels (0 = no amplification, per Android's
  /// `LoudnessEnhancer`).
  RealColumn get preampDb => real().withDefault(const Constant(0))();

  /// Whether bass boost is engaged.
  BoolColumn get bassBoostEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Bass boost strength, 0.0–1.0.
  RealColumn get bassBoostStrength => real().withDefault(const Constant(0))();

  /// Whether the spatial (virtualizer) effect is engaged.
  BoolColumn get virtualizerEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Virtualizer strength, 0.0–1.0.
  RealColumn get virtualizerStrength => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
