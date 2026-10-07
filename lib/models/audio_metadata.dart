/// Represents low-level filesystem attributes of an audio file.
class FileInformation {
  /// Local absolute file path or media content URI.
  final String filePath;

  /// Physical file name with extension (e.g. '01 - Numb.mp3').
  final String fileName;

  /// File size in bytes.
  final int? fileSize;

  /// MIME type (e.g. 'audio/mpeg', 'audio/flac').
  final String? mimeType;

  const FileInformation({
    required this.filePath,
    required this.fileName,
    this.fileSize,
    this.mimeType,
  });

  FileInformation copyWith({
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) {
    return FileInformation(
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
    };
  }

  factory FileInformation.fromMap(Map<String, dynamic> map) {
    return FileInformation(
      filePath: map['filePath'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      fileSize: map['fileSize'] as int?,
      mimeType: map['mimeType'] as String?,
    );
  }

  @override
  String toString() =>
      'FileInformation(fileName: $fileName, fileSize: $fileSize, mimeType: $mimeType, filePath: $filePath)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileInformation &&
        other.filePath == filePath &&
        other.fileName == fileName &&
        other.fileSize == fileSize &&
        other.mimeType == mimeType;
  }

  @override
  int get hashCode => Object.hash(filePath, fileName, fileSize, mimeType);
}

/// Represents logical music tags / ID3 container metadata.
class MusicMetadata {
  /// Track song title.
  final String title;

  /// Primary performer / artist name.
  final String artist;

  /// Album name, if available.
  final String? album;

  /// Primary album artist, if distinguished from track artist.
  final String? albumArtist;

  /// Musical genre tag, if available.
  final String? genre;

  /// Release year.
  final int? year;

  /// Track position index on the album.
  final int? trackNumber;

  /// Disc number in multi-disc sets.
  final int? discNumber;

  /// Total duration of the audio playback.
  final Duration duration;

  /// Album artwork URI or identifier.
  final String? albumArtUri;

  const MusicMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration = Duration.zero,
    this.albumArtUri,
  });

  MusicMetadata copyWith({
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    Duration? duration,
    String? albumArtUri,
  }) {
    return MusicMetadata(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      duration: duration ?? this.duration,
      albumArtUri: albumArtUri ?? this.albumArtUri,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'genre': genre,
      'year': year,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'durationMs': duration.inMilliseconds,
      'albumArtUri': albumArtUri,
    };
  }

  factory MusicMetadata.fromMap(Map<String, dynamic> map) {
    return MusicMetadata(
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String?,
      albumArtist: map['albumArtist'] as String?,
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      trackNumber: map['trackNumber'] as int?,
      discNumber: map['discNumber'] as int?,
      duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
      albumArtUri: map['albumArtUri'] as String?,
    );
  }

  @override
  String toString() =>
      'MusicMetadata(title: $title, artist: $artist, album: $album, year: $year, trackNumber: $trackNumber, duration: $duration)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicMetadata &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.albumArtist == albumArtist &&
        other.genre == genre &&
        other.year == year &&
        other.trackNumber == trackNumber &&
        other.discNumber == discNumber &&
        other.duration == duration &&
        other.albumArtUri == albumArtUri;
  }

  @override
  int get hashCode => Object.hash(
        title,
        artist,
        album,
        albumArtist,
        genre,
        year,
        trackNumber,
        discNumber,
        duration,
        albumArtUri,
      );
}
