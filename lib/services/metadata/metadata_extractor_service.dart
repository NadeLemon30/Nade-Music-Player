import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/audio_metadata.dart';
import '../../models/track.dart';

/// Contract for processing, enriching, and separating file information from audio metadata.
abstract class MetadataExtractorService {
  /// Assembles a domain [Track] by combining physical [FileInformation] and logical [MusicMetadata].
  Track combine({
    required String id,
    required FileInformation fileInfo,
    required MusicMetadata metadata,
    bool isAsset = false,
  });

  /// Sanitizes raw tags and applies filename heuristic parsing if tags are missing or generic.
  MusicMetadata sanitizeAndEnrich(
    MusicMetadata metadata, {
    required String fileName,
  });

  /// Extracts [FileInformation] from a file path and optional file attributes.
  FileInformation extractFileInfo(
    String filePath, {
    int? fileSize,
    String? mimeType,
  });
}

/// Default implementation providing robust tag sanitization, MIME inference, and filename parsing heuristics.
class DefaultMetadataExtractorService implements MetadataExtractorService {
  static final RegExp _trackAndTitlePattern = RegExp(
    r'^(?:(?<disc>\d+)-)?(?<track>\d{1,3})[\s\.\-_]+(?<title>.+)$',
  );

  static final RegExp _artistAndTitlePattern = RegExp(
    r'^(?:(?<track>\d{1,3})[\s\.\-_]+)?(?<artist>[^-]+)\s*-\s*(?<title>[^-]+)(?:\s*-\s*(?<extra>.*))?$',
  );

  @override
  Track combine({
    required String id,
    required FileInformation fileInfo,
    required MusicMetadata metadata,
    bool isAsset = false,
  }) {
    final enriched = sanitizeAndEnrich(
      metadata,
      fileName: fileInfo.fileName,
    );

    return Track(
      id: id,
      title: enriched.title,
      artist: enriched.artist,
      album: enriched.album ?? 'Unknown Album',
      albumArtist: enriched.albumArtist ?? 'Unknown Artist',
      genre: enriched.genre ?? 'Unknown Genre',
      year: enriched.year,
      trackNumber: enriched.trackNumber,
      discNumber: enriched.discNumber,
      duration: enriched.duration,
      filePath: fileInfo.filePath,
      fileName: fileInfo.fileName,
      fileSize: fileInfo.fileSize,
      mimeType: fileInfo.mimeType,
      isAsset: isAsset,
      albumArtUri: enriched.albumArtUri,
    );
  }

  @override
  MusicMetadata sanitizeAndEnrich(
    MusicMetadata metadata, {
    required String fileName,
  }) {
    String? cleanedTitle = _cleanString(metadata.title);
    String? cleanedArtist = _cleanString(metadata.artist);
    String? cleanedAlbum = _cleanString(metadata.album);
    String? cleanedAlbumArtist = _cleanString(metadata.albumArtist);
    String? cleanedGenre = _cleanString(metadata.genre);
    int? trackNumber = metadata.trackNumber;
    int? discNumber = metadata.discNumber;

    // If title or artist are missing/unknown, derive from filename without extension
    final baseName = _removeExtension(fileName);

    if (cleanedTitle == null || cleanedTitle.isEmpty || cleanedTitle.toLowerCase() == 'unknown title') {
      final parsed = _parseFromFileName(baseName);
      cleanedTitle = parsed.title;
      cleanedArtist ??= parsed.artist;
      trackNumber ??= parsed.trackNumber;
      discNumber ??= parsed.discNumber;
    }

    if (cleanedArtist == null || cleanedArtist.isEmpty || cleanedArtist.toLowerCase() == 'unknown artist') {
      final parsed = _parseFromFileName(baseName);
      if (parsed.artist != null && parsed.artist!.isNotEmpty) {
        cleanedArtist = parsed.artist;
      } else {
        cleanedArtist = 'Unknown Artist';
      }
    }

    cleanedTitle = cleanedTitle.isNotEmpty ? cleanedTitle : baseName;

    return metadata.copyWith(
      title: cleanedTitle,
      artist: cleanedArtist,
      album: cleanedAlbum,
      albumArtist: cleanedAlbumArtist,
      genre: cleanedGenre,
      trackNumber: trackNumber,
      discNumber: discNumber,
    );
  }

  @override
  FileInformation extractFileInfo(
    String filePath, {
    int? fileSize,
    String? mimeType,
  }) {
    final fileName = filePath.contains('/')
        ? filePath.split('/').last
        : (filePath.contains('\\') ? filePath.split('\\').last : filePath);

    final resolvedMime = mimeType ?? _inferMimeType(fileName);

    return FileInformation(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: resolvedMime,
    );
  }

  String? _cleanString(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty ||
        trimmed == '<unknown>' ||
        trimmed.toLowerCase() == 'unknown' ||
        trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  String _removeExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot > 0) {
      return fileName.substring(0, lastDot);
    }
    return fileName;
  }

  _ParsedFileName _parseFromFileName(String baseName) {
    // 1. Check for "Artist - Title" or "01 - Artist - Title"
    final artistMatch = _artistAndTitlePattern.firstMatch(baseName);
    if (artistMatch != null) {
      final trackStr = artistMatch.namedGroup('track');
      final artist = artistMatch.namedGroup('artist')?.trim();
      final title = artistMatch.namedGroup('title')?.trim();

      int? track;
      if (trackStr != null) {
        track = int.tryParse(trackStr);
      }

      if (title != null && title.isNotEmpty) {
        return _ParsedFileName(
          title: title,
          artist: artist,
          trackNumber: track,
        );
      }
    }

    // 2. Check for "01 - Title" or "1-01 - Title"
    final trackMatch = _trackAndTitlePattern.firstMatch(baseName);
    if (trackMatch != null) {
      final discStr = trackMatch.namedGroup('disc');
      final trackStr = trackMatch.namedGroup('track');
      final title = trackMatch.namedGroup('title')?.trim();

      int? disc;
      int? track;

      if (discStr != null) disc = int.tryParse(discStr);
      if (trackStr != null) track = int.tryParse(trackStr);

      if (title != null && title.isNotEmpty) {
        return _ParsedFileName(
          title: title,
          trackNumber: track,
          discNumber: disc,
        );
      }
    }

    // 3. Fallback: replace underscores with spaces
    final fallbackTitle = baseName.replaceAll('_', ' ').trim();
    return _ParsedFileName(title: fallbackTitle);
  }

  String? _inferMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac') || lower.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    if (lower.endsWith('.ogg') || lower.endsWith('.oga') || lower.endsWith('.opus')) {
      return 'audio/ogg';
    }
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.wma')) return 'audio/x-ms-wma';
    return null;
  }
}

class _ParsedFileName {
  final String title;
  final String? artist;
  final int? trackNumber;
  final int? discNumber;

  _ParsedFileName({
    required this.title,
    this.artist,
    this.trackNumber,
    this.discNumber,
  });
}

/// Provider for [MetadataExtractorService].
final metadataExtractorServiceProvider = Provider<MetadataExtractorService>((ref) {
  return DefaultMetadataExtractorService();
});
