import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/audio_effects.dart';
import '../database/app_database.dart';
import '../database/tables/audio_effects_settings.dart';
import 'music_repository.dart';

/// The persisted audio-effects configuration (Phase 4B, spec §15).
///
/// A plain, engine-free snapshot of the stored preferences:
/// `equalizerEnabled`, `presetId`, the per-band gains, the preamp, the bass
/// boost and virtualizer flags and strengths. [bandGains] holds one gain per
/// band in decibels (empty when nothing was stored yet), because the number of
/// bands is decided by the platform.
class PersistedAudioEffectsSettings {
  const PersistedAudioEffectsSettings({
    this.equalizerEnabled = false,
    this.presetId,
    this.bandGains = const [],
    this.preampEnabled = false,
    this.preampDb = 0,
    this.bassBoostEnabled = false,
    this.bassBoostStrength = 0,
    this.virtualizerEnabled = false,
    this.virtualizerStrength = 0,
  });

  final bool equalizerEnabled;
  final String? presetId;

  /// Per-band gains in decibels (empty when unset).
  final List<double> bandGains;

  final bool preampEnabled;
  final double preampDb;
  final bool bassBoostEnabled;

  /// 0.0–1.0.
  final double bassBoostStrength;

  final bool virtualizerEnabled;

  /// 0.0–1.0.
  final double virtualizerStrength;
}

/// Persistence for the audio-effects **preferences** (spec §15).
///
/// These are application settings, not music-library data, so the store is a
/// single-row key/value-style record with no relation to tracks at all. Drift is
/// used for the row (the app already owns one database, and it keeps the write
/// transactional with the rest of the app's persistence), but the surface is
/// deliberately "lightweight": [load]/[save]/[clear] over one
/// [PersistedAudioEffectsSettings] value, and nothing else.
///
/// Backed by the `audio_effects_settings` table: reads use the constant
/// singleton id and writes are an upsert. It deliberately knows nothing about
/// the audio engine — it only moves numbers in and out of storage.
class AudioEffectsPreferences {
  AudioEffectsPreferences(this._db);

  final AppDatabase _db;

  /// The stored preferences, or null when the app has never changed them.
  Future<PersistedAudioEffectsSettings?> load() async {
    final row = await (_db.select(_db.audioEffectsSettings)
          ..where((t) => t.id.equals(AudioEffectsSettings.rowId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _toSettings(row);
  }

  /// Inserts or updates the singleton preferences row.
  Future<void> save(PersistedAudioEffectsSettings settings) async {
    await _db.into(_db.audioEffectsSettings).insertOnConflictUpdate(
          AudioEffectsSettingsCompanion.insert(
            id: const Value(AudioEffectsSettings.rowId),
            equalizerEnabled: Value(settings.equalizerEnabled),
            presetId: Value(settings.presetId),
            bandGains: Value(encodeBandGains(settings.bandGains)),
            preampEnabled: Value(settings.preampEnabled),
            preampDb: Value(settings.preampDb),
            bassBoostEnabled: Value(settings.bassBoostEnabled),
            bassBoostStrength: Value(settings.bassBoostStrength),
            virtualizerEnabled: Value(settings.virtualizerEnabled),
            virtualizerStrength: Value(settings.virtualizerStrength),
          ),
        );
  }

  /// Deletes the preferences row (used by tests and by a future "reset" action).
  Future<void> clear() async {
    await (_db.delete(_db.audioEffectsSettings)
          ..where((t) => t.id.equals(AudioEffectsSettings.rowId)))
        .go();
  }

  PersistedAudioEffectsSettings _toSettings(AudioEffectsSettingsRow row) {
    return PersistedAudioEffectsSettings(
      equalizerEnabled: row.equalizerEnabled,
      presetId: row.presetId,
      bandGains: decodeBandGains(row.bandGains),
      preampEnabled: row.preampEnabled,
      preampDb: row.preampDb,
      bassBoostEnabled: row.bassBoostEnabled,
      bassBoostStrength: row.bassBoostStrength,
      virtualizerEnabled: row.virtualizerEnabled,
      virtualizerStrength: row.virtualizerStrength,
    );
  }
}

/// Provider for the singleton [AudioEffectsPreferences], backed by Drift.
final audioEffectsPreferencesProvider = Provider<AudioEffectsPreferences>((ref) {
  return AudioEffectsPreferences(ref.watch(appDatabaseProvider));
});
