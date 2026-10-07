import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../models/track.dart';
import '../database/app_database.dart';
import 'music_repository.dart';

/// Persistence layer for user-created playlists (Phase 3J, spec 3J.8).
///
/// The UI interacts with this repository — through [PlaylistService] — rather
/// than issuing SQL against [AppDatabase] directly.
class PlaylistRepository {
  PlaylistRepository(this._db);

  final AppDatabase _db;

  /// All playlists, oldest-created first.
  Future<List<Playlist>> getAll() async {
    final rows = await (_db.select(_db.playlists)
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
    return rows.map(_toPlaylist).toList();
  }

  /// The playlist with [id], or null when it does not exist.
  Future<Playlist?> getById(String id) async {
    final row = await (_db.select(_db.playlists)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toPlaylist(row);
  }

  /// Creates a playlist named [name] with a fresh UUID v4 id (3J.5) and
  /// returns it.
  Future<Playlist> create(String name) async {
    final trimmed = name.trim();
    final playlist = Playlist(
      id: generateUuidV4(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(
            id: playlist.id,
            name: trimmed,
            createdAt: Value(playlist.createdAt),
          ),
        );
    return playlist;
  }

  /// Renames the playlist with [playlistId]. No-op when it does not exist.
  Future<void> rename(String playlistId, String name) async {
    await (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(name: Value(name.trim())));
  }

  /// Deletes the playlist with [playlistId]; its `playlist_tracks` rows are
  /// removed by the ON DELETE CASCADE foreign key.
  Future<void> delete(String playlistId) async {
    await (_db.delete(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .go();
  }

  /// Track ids in [playlistId], ordered by `position`.
  Future<List<String>> getTrackIds(String playlistId) async {
    final rows = await (_db.select(_db.playlistTracks)
          ..where((r) => r.playlistId.equals(playlistId))
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    return rows.map((r) => r.trackId).toList();
  }

  /// Every playlist-track membership row, ordered by playlist then position.
  /// Restore uses this to rebuild per-playlist order without N+1 queries.
  Future<List<PlaylistTrack>> getAllTracks() async {
    final rows = await (_db.select(_db.playlistTracks)
          ..orderBy([
            (r) => OrderingTerm.asc(r.playlistId),
            (r) => OrderingTerm.asc(r.position),
          ]))
        .get();
    return [
      for (final r in rows)
        PlaylistTrack(
          playlistId: r.playlistId,
          trackId: r.trackId,
          position: r.position,
        ),
    ];
  }

  /// Appends [trackId] to playlist [playlistId] at the next [position]
  /// (idempotent: the composite PK makes a duplicate a no-op).
  Future<void> addTrack(String playlistId, String trackId) async {
    final rows = await (_db.select(_db.playlistTracks)
          ..where((r) => r.playlistId.equals(playlistId)))
        .get();
    await _db.into(_db.playlistTracks).insert(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: rows.length,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Appends [trackIds] to playlist [playlistId] in one transaction (spec 24),
  /// deduplicating against the rows already present so positions stay
  /// contiguous and the composite PK is never violated. Returns how many
  /// tracks were actually inserted.
  Future<int> addTracks(String playlistId, List<String> trackIds) async {
    if (trackIds.isEmpty) return 0;

    var added = 0;
    await _db.transaction(() async {
      final rows = await (_db.select(_db.playlistTracks)
            ..where((r) => r.playlistId.equals(playlistId)))
          .get();
      final existingIds = {for (final r in rows) r.trackId};

      final inserts = <PlaylistTracksCompanion>[];
      var position = rows.length;
      for (final trackId in trackIds) {
        if (existingIds.contains(trackId)) continue;
        inserts.add(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: position++,
          ),
        );
        added++;
      }

      if (inserts.isNotEmpty) {
        await _db.batch(
          (batch) => batch.insertAll(
            _db.playlistTracks,
            inserts,
            mode: InsertMode.insertOrIgnore,
          ),
        );
      }
    });
    return added;
  }

  /// Removes the link to [trackId] from playlist [playlistId]. Renumbering the
  /// survivors is left to [setTrackOrder].
  Future<void> removeTrack(String playlistId, String trackId) async {
    await (_db.delete(_db.playlistTracks)
          ..where(
            (r) => r.playlistId.equals(playlistId) & r.trackId.equals(trackId),
          ))
        .go();
  }

  /// Moves the track at [oldIndex] to [newIndex] within playlist [playlistId]
  /// (0-based, clamped), rewriting positions atomically.
  Future<void> reorderTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = await getTrackIds(playlistId);
    if (ids.isEmpty) return;
    final from = oldIndex.clamp(0, ids.length - 1);
    final to = newIndex.clamp(0, ids.length - 1);
    if (from == to) return;

    final trackId = ids.removeAt(from);
    ids.insert(to, trackId);
    await setTrackOrder(playlistId, ids);
  }

  /// Applies the authoritative order [trackIds] to playlist [playlistId]:
  /// deletes all of its rows and re-inserts them with `position = index`
  /// atomically. Used after removal, prune, and reorder so stored positions
  /// never drift from the service's in-memory order.
  Future<void> setTrackOrder(
    String playlistId,
    List<String> trackIds,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.playlistTracks)
            ..where((r) => r.playlistId.equals(playlistId)))
          .go();
      await _db.batch((batch) {
        batch.insertAll(
          _db.playlistTracks,
          [
            for (var i = 0; i < trackIds.length; i++)
              PlaylistTracksCompanion.insert(
                playlistId: playlistId,
                trackId: trackIds[i],
                position: i,
              ),
          ],
        );
      });
    });
  }

  /// All library tracks keyed by id, used to resolve playlist entries into
  /// full [Track] objects on restore. Extra beyond the recommended 3J.8
  /// surface, but playlist persistence must stay behind this repository.
  Future<Map<String, Track>> getTracksById() async {
    final rows = await _db.select(_db.tracks).get();
    return {for (final row in rows) row.id: _rowToTrack(row)};
  }

  Playlist _toPlaylist(PlaylistEntryData row) {
    return Playlist(id: row.id, name: row.name, createdAt: row.createdAt);
  }

  Track _rowToTrack(TrackEntry row) {
    return Track(
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album,
      albumArtist: row.albumArtist,
      genre: row.genre,
      year: row.year,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      duration: row.durationMs != null
          ? Duration(milliseconds: row.durationMs!)
          : null,
      filePath: row.filePath,
      fileName: row.fileName,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      albumId: row.albumId,
      albumArtUri: row.albumId?.toString(),
      isAvailable: row.isAvailable,
    );
  }
}

/// Provider for the singleton [PlaylistRepository], backed by Drift.
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(appDatabaseProvider));
});