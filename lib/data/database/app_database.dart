import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/albums.dart';
import 'tables/artists.dart';
import 'tables/audio_effects_settings.dart';
import 'tables/favorites.dart';
import 'tables/play_history.dart';
import 'tables/playlist_history.dart';
import 'tables/playlist_tracks.dart';
import 'tables/playlists.dart';
import 'tables/tracks.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tracks,
    Artists,
    Albums,
    PlayHistory,
    Favorites,
    Playlists,
    PlaylistTracks,
    PlaylistHistory,
    AudioEffectsSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(
          executor ??
              driftDatabase(
                name: 'music_player_database',
              ),
        );

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(
            tracks,
            tracks.isAvailable,
          );
        }
        if (from < 3) {
          await m.createTable(artists);
          await m.addColumn(
            tracks,
            tracks.artistId,
          );
        }
        if (from < 4) {
          await m.createTable(albums);
        }
        if (from < 5) {
          await m.createTable(playHistory);
        }
        if (from < 6) {
          await m.createTable(favorites);
        }
        if (from < 7) {
          await m.createTable(playlists);
          await m.createTable(playlistTracks);
        }
        if (from < 8) {
          await m.createTable(playlistHistory);
        }
        if (from < 9) {
          await m.createTable(audioEffectsSettings);
        }
        if (from < 10) {
          await m.addColumn(
            audioEffectsSettings,
            audioEffectsSettings.preampEnabled,
          );
        }
      },
    );
  }
}
