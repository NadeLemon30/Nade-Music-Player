/// Represents an album entity at the album-artwork level of the library.
class Album {
  /// Android MediaStore album identifier.
  final int id;

  /// Album title.
  final String title;

  /// Primary artist credited on the whole album (distinct from per-track artist).
  final String albumArtist;

  /// Android MediaStore artist identifier for the album artist, when known.
  final int? artistId;

  /// Release year.
  final int? year;

  /// Number of tracks on the album.
  final int trackCount;

  /// Key identifying the album artwork (image is cached outside SQLite).
  final String? artworkKey;

  const Album({
    required this.id,
    required this.title,
    required this.albumArtist,
    required this.artistId,
    required this.year,
    required this.trackCount,
    required this.artworkKey,
  });

  Album copyWith({
    int? id,
    String? title,
    String? albumArtist,
    int? artistId,
    int? year,
    int? trackCount,
    String? artworkKey,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      albumArtist: albumArtist ?? this.albumArtist,
      artistId: artistId ?? this.artistId,
      year: year ?? this.year,
      trackCount: trackCount ?? this.trackCount,
      artworkKey: artworkKey ?? this.artworkKey,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'albumArtist': albumArtist,
      'artistId': artistId,
      'year': year,
      'trackCount': trackCount,
      'artworkKey': artworkKey,
    };
  }

  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? 'Unknown Album',
      albumArtist: map['albumArtist'] as String? ?? '',
      artistId: map['artistId'] as int?,
      year: map['year'] as int?,
      trackCount: map['trackCount'] as int? ?? 0,
      artworkKey: map['artworkKey'] as String?,
    );
  }

  @override
  String toString() =>
      'Album(id: $id, title: $title, albumArtist: $albumArtist, year: $year, trackCount: $trackCount)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Album &&
        other.id == id &&
        other.title == title &&
        other.albumArtist == albumArtist &&
        other.artistId == artistId &&
        other.year == year &&
        other.trackCount == trackCount &&
        other.artworkKey == artworkKey;
  }

  @override
  int get hashCode =>
      Object.hash(id, title, albumArtist, artistId, year, trackCount, artworkKey);
}
