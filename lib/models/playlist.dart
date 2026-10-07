/// An immutable playlist header: the playlist's identity, name, and creation
/// time (Phase 3J, spec 3J.6).
///
/// Deliberately metadata-only (3J.4) — the songs live separately in the
/// `playlist_tracks` one-to-many list (see [PlaylistTrack]) and the [id] is a
/// UUID v4 (3J.5) so a rename never changes the playlist's identity.
class Playlist {
  final String id;

  /// Display name (editable independently of the playlist's identity).
  final String name;

  /// When the playlist was created.
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Playlist copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}