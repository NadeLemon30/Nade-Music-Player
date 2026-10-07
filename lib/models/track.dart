/// Represents an immutable audio track entity with rich metadata.
class Track {
  /// Unique identifier for the track (e.g., MediaStore ID or UUID).
  final String id;

  /// Track title.
  final String title;

  /// Primary artist or performer name.
  final String artist;

  /// Album name.
  final String album;

  /// Primary album artist, if distinguished from track artist.
  final String albumArtist;

  /// Musical genre tag.
  final String genre;

  /// Release year.
  final int? year;

  /// Track number on the album.
  final int? trackNumber;

  /// Disc number in multi-disc sets.
  final int? discNumber;

  /// Total duration of the track.
  final Duration? duration;

  /// Local absolute file path or media content URI.
  final String filePath;

  /// File name with extension (e.g. 'song_title.mp3').
  final String fileName;

  /// File size in bytes.
  final int? fileSize;

  /// MIME type (e.g. 'audio/mpeg', 'audio/flac', 'audio/mp4').
  final String? mimeType;

  /// Whether the file is bundled as an asset rather than a device storage file.
  final bool isAsset;

  /// Android MediaStore artist identifier.
  final int? artistId;

  /// Android MediaStore album identifier, used to retrieve album artwork.
  final int? albumId;

  /// URI or identifier for the album artwork image.
  final String? albumArtUri;

  /// Whether the underlying audio file is still present on the device.
  final bool isAvailable;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.year,
    required this.trackNumber,
    required this.discNumber,
    required this.duration,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.isAsset = false,
    this.artistId,
    this.albumId,
    this.albumArtUri,
    this.isAvailable = true,
  });

  /// Alias for backward compatibility with initial asset demo tracks.
  String get assetPath => filePath;

  /// Alias for backward compatibility with earlier size property.
  int? get size => fileSize;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    Duration? duration,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
    bool? isAsset,
    int? artistId,
    int? albumId,
    String? albumArtUri,
    bool? isAvailable,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      isAsset: isAsset ?? this.isAsset,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumArtUri: albumArtUri ?? this.albumArtUri,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'genre': genre,
      'year': year,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'durationMs': duration?.inMilliseconds,
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'isAsset': isAsset,
      'artistId': artistId,
      'albumId': albumId,
      'albumArtUri': albumArtUri,
      'isAvailable': isAvailable,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String? ?? '',
      albumArtist: map['albumArtist'] as String? ?? '',
      genre: map['genre'] as String? ?? '',
      year: map['year'] as int?,
      trackNumber: map['trackNumber'] as int?,
      discNumber: map['discNumber'] as int?,
      duration: map['durationMs'] != null
          ? Duration(milliseconds: map['durationMs'] as int)
          : null,
      filePath: map['filePath'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      fileSize: map['fileSize'] as int?,
      mimeType: map['mimeType'] as String?,
      isAsset: map['isAsset'] as bool? ?? false,
      artistId: map['artistId'] as int?,
      albumId: map['albumId'] as int?,
      albumArtUri: map['albumArtUri'] as String?,
      isAvailable: map['isAvailable'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'Track(id: $id, title: $title, artist: $artist, album: $album, duration: $duration, filePath: $filePath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Track &&
        other.id == id &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.albumArtist == albumArtist &&
        other.genre == genre &&
        other.year == year &&
        other.trackNumber == trackNumber &&
        other.discNumber == discNumber &&
        other.duration == duration &&
        other.filePath == filePath &&
        other.fileName == fileName &&
        other.fileSize == fileSize &&
        other.mimeType == mimeType &&
        other.isAsset == isAsset &&
        other.artistId == artistId &&
        other.albumId == albumId &&
        other.albumArtUri == albumArtUri &&
        other.isAvailable == isAvailable;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        artist,
        album,
        albumArtist,
        genre,
        year,
        trackNumber,
        discNumber,
        duration,
        filePath,
        fileName,
        fileSize,
        mimeType,
        isAsset,
        artistId,
        albumId,
        albumArtUri,
        isAvailable,
      );
}
