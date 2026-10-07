/// A single ordered membership link between a playlist and a track (Phase 3J,
/// spec 3J.7).
///
/// This is the raw `playlist_id` / `track_id` / `position` row of the
/// `playlist_tracks` one-to-many table — deliberately not the resolved audio
/// [Track]; the playlist UI reads resolved tracks through the service layer.
class PlaylistTrack {
  final String playlistId;

  /// The id of the [Track] that belongs to the playlist.
  final String trackId;

  /// 0-based index of this entry within the playlist's custom ordering.
  final int position;

  const PlaylistTrack({
    required this.playlistId,
    required this.trackId,
    required this.position,
  });
}