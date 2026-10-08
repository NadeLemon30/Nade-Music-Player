import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/database/app_database.dart';
import 'package:nades_music_player/data/repositories/audio_effects_preferences.dart';
import 'package:nades_music_player/data/repositories/music_repository.dart';

void main() {
  group('AudioEffectsPreferences', () {
    late AppDatabase db;
    late AudioEffectsPreferences repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = AudioEffectsPreferences(db);
    });

    tearDown(() => db.close());

    test('load returns null before anything is saved', () async {
      expect(await repo.load(), isNull);
    });

    test('save then load round-trips every setting', () async {
      await repo.save(
        const PersistedAudioEffectsSettings(
          equalizerEnabled: true,
          presetId: 'bass_boost',
          bandGains: [8, 5, 0, -2, -4],
          preampEnabled: true,
          preampDb: 2.5,
          bassBoostEnabled: true,
          bassBoostStrength: 0.75,
          virtualizerEnabled: true,
          virtualizerStrength: 0.25,
        ),
      );

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.equalizerEnabled, isTrue);
      expect(loaded.presetId, 'bass_boost');
      expect(loaded.bandGains, [8, 5, 0, -2, -4]);
      expect(loaded.preampEnabled, isTrue);
      expect(loaded.preampDb, 2.5);
      expect(loaded.bassBoostEnabled, isTrue);
      expect(loaded.bassBoostStrength, 0.75);
      expect(loaded.virtualizerEnabled, isTrue);
      expect(loaded.virtualizerStrength, 0.25);
    });

    test('saving twice updates the single row instead of inserting', () async {
      await repo.save(
        const PersistedAudioEffectsSettings(equalizerEnabled: true),
      );
      await repo.save(
        const PersistedAudioEffectsSettings(
          equalizerEnabled: false,
          presetId: 'rock',
        ),
      );

      final rows = await db.select(db.audioEffectsSettings).get();
      expect(rows, hasLength(1));

      final loaded = await repo.load();
      expect(loaded!.equalizerEnabled, isFalse);
      expect(loaded.presetId, 'rock');
    });

    test('an empty gain list round-trips as empty', () async {
      await repo.save(const PersistedAudioEffectsSettings());

      final loaded = await repo.load();
      expect(loaded!.bandGains, isEmpty);
    });

    test('clear removes the row', () async {
      await repo.save(const PersistedAudioEffectsSettings(preampDb: 1));
      await repo.clear();

      expect(await repo.load(), isNull);
    });
  });

  // Spec §16: equalizer settings are global playback preferences and must never
  // end up in the music tables.
  group('audio effects stay out of the music database (spec §16)', () {
    late AppDatabase db;
    late AudioEffectsPreferences repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = AudioEffectsPreferences(db);
    });

    tearDown(() => db.close());

    test('settings round-trip while every music table is empty', () async {
      await repo.save(
        const PersistedAudioEffectsSettings(
          equalizerEnabled: true,
          presetId: 'rock',
          bandGains: [4, 2, 0, -2, -4],
          preampEnabled: true,
          preampDb: 3,
        ),
      );

      // The settings live in their own table and reference no media at all.
      expect(await db.select(db.tracks).get(), isEmpty);
      expect(await db.select(db.albums).get(), isEmpty);
      expect(await db.select(db.artists).get(), isEmpty);
      expect(await db.select(db.playlists).get(), isEmpty);
      expect(await db.select(db.playHistory).get(), isEmpty);
      expect(await db.select(db.favorites).get(), isEmpty);

      final loaded = await repo.load();
      expect(loaded!.presetId, 'rock');
      expect(loaded.bandGains, [4, 2, 0, -2, -4]);
    });

    test('deleting a track never touches the stored effects', () async {
      await repo.save(
        const PersistedAudioEffectsSettings(
          equalizerEnabled: true,
          presetId: 'jazz',
          bandGains: [1, 2, 3, 4, 5],
        ),
      );

      // Deleting library media (the spec 23 purge) must leave the global
      // playback settings alone.
      await DriftMusicRepository(db).purgeTrackRelations(<String>{'gone'});

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.equalizerEnabled, isTrue);
      expect(loaded.presetId, 'jazz');
      expect(loaded.bandGains, [1, 2, 3, 4, 5]);
    });
  });
}
