import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';

/// Target source entity type for artwork extraction.
enum ArtworkSourceType {
  audio,
  album,
  artist,
}

/// Contract for extracting, caching, and serving audio cover art.
///
/// Implements a 2-tier cache (Memory LRU -> Persistent Disk File -> Extractor)
/// to ensure embedded artwork is extracted only once and never repeatedly from audio files.
abstract class ArtworkService {
  /// Retrieves artwork image bytes for a given identifier or audio file path.
  Future<Uint8List?> getArtwork({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
    int? size,
  });

  /// Retrieves album artwork bytes by Android MediaStore album ID.
  Future<Uint8List?> getAlbumArtwork(int albumId, {int? size});

  /// Retrieves the cached image [File] from disk if already cached.
  Future<File?> getArtworkFile({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
  });

  /// Builds the canonical cache key shared by the memory and disk caches for
  /// [id] (falling back to [filePath] when empty) under [sourceType]. Callers
  /// that check the memory cache synchronously must use this exact key so they
  /// hit the same entries [getArtwork] writes.
  String artworkCacheKey({
    required String id,
    String? filePath,
    required ArtworkSourceType sourceType,
  });

  /// Synchronously checks if artwork is present in the high-speed in-memory cache.
  Uint8List? getFromMemoryCache(String key);

  /// Preloads artwork for a list of tracks in the background.
  Future<void> preloadArtwork(List<Track> tracks);

  /// Clears in-memory and disk artwork cache.
  Future<void> clearCache();
}

/// Default implementation of [ArtworkService] with Memory + Disk caching and MediaStore/Local file extractors.
class DefaultArtworkService implements ArtworkService {
  final OnAudioQuery _audioQuery;
  final String? customCacheDir;

  // In-memory cache: maps cacheKey -> Uint8List? (null value indicates negative cache / no art)
  final Map<String, Uint8List?> _memoryCache = {};

  // Album artwork cache keyed by Android MediaStore albumId.
  // Shared across tracks that belong to the same album to avoid redundant lookups.
  final Map<int, Uint8List?> _albumCache = {};
  String? _resolvedCacheDir;

  DefaultArtworkService({
    OnAudioQuery? audioQuery,
    this.customCacheDir,
  }) : _audioQuery = audioQuery ?? OnAudioQuery();

  Future<String> _getCacheDirectory() async {
    if (customCacheDir != null) {
      final dir = Directory(customCacheDir!);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return customCacheDir!;
    }

    if (_resolvedCacheDir != null) {
      return _resolvedCacheDir!;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final artworkDir = Directory(p.join(tempDir.path, 'nade_artwork_cache'));
      if (!artworkDir.existsSync()) {
        await artworkDir.create(recursive: true);
      }
      _resolvedCacheDir = artworkDir.path;
      return _resolvedCacheDir!;
    } catch (e) {
      debugPrint('ArtworkService: Error resolving cache directory: $e');
      _resolvedCacheDir = Directory.systemTemp.path;
      return _resolvedCacheDir!;
    }
  }

  String _buildCacheKey(String id, ArtworkSourceType sourceType) {
    final sanitized = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '${sourceType.name}_$sanitized';
  }

  @override
  String artworkCacheKey({
    required String id,
    String? filePath,
    required ArtworkSourceType sourceType,
  }) {
    return _buildCacheKey(id.isNotEmpty ? id : (filePath ?? ''), sourceType);
  }

  @override
  Uint8List? getFromMemoryCache(String key) {
    return _memoryCache[key];
  }

  @override
  Future<Uint8List?> getArtwork({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
    int? size,
  }) async {
    if (id.trim().isEmpty && (filePath == null || filePath.trim().isEmpty)) {
      return null;
    }

    final cacheKey = artworkCacheKey(
      id: id,
      filePath: filePath,
      sourceType: sourceType,
    );

    // 1. Check Memory Cache (Tier 1)
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    try {
      final cacheDir = await _getCacheDirectory();
      final diskFile = File(p.join(cacheDir, '$cacheKey.jpg'));

      // 2. Check Disk Cache (Tier 2)
      if (await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _memoryCache[cacheKey] = bytes;
          return bytes;
        }
      }

      // 3. Extract Embedded Artwork (Tier 3)
      Uint8List? extractedBytes;

      // Try platform MediaStore extraction if ID is a numeric MediaStore ID
      final numericId = int.tryParse(id);
      if (numericId != null) {
        final queryType = switch (sourceType) {
          ArtworkSourceType.audio => ArtworkType.AUDIO,
          ArtworkSourceType.album => ArtworkType.ALBUM,
          ArtworkSourceType.artist => ArtworkType.ARTIST,
        };

        try {
          extractedBytes = await _audioQuery.queryArtwork(
            numericId,
            queryType,
            format: ArtworkFormat.JPEG,
            quality: 90,
            size: size ?? 500,
          );
        } catch (e) {
          debugPrint('ArtworkService: Platform extraction error: $e');
        }
      }

      // If MediaStore extraction yielded nothing, check local folder images
      if (extractedBytes == null && filePath != null && filePath.isNotEmpty) {
        extractedBytes = await _findLocalFolderArtwork(filePath);
      }

      // 4. Save to Disk Cache & Memory Cache
      if (extractedBytes != null && extractedBytes.isNotEmpty) {
        try {
          await diskFile.writeAsBytes(extractedBytes, flush: true);
        } catch (e) {
          debugPrint('ArtworkService: Failed to write to disk cache: $e');
        }
        _memoryCache[cacheKey] = extractedBytes;
        return extractedBytes;
      }

      // 5. Negative Cache to avoid repeated expensive lookups
      _memoryCache[cacheKey] = null;
      return null;
    } catch (e) {
      debugPrint('ArtworkService: Exception while getting artwork: $e');
      _memoryCache[cacheKey] = null;
      return null;
    }
  }

  @override
  Future<Uint8List?> getAlbumArtwork(int albumId, {int? size}) {
    if (_albumCache.containsKey(albumId)) {
      return Future.value(_albumCache[albumId]);
    }

    return getArtwork(
      id: albumId.toString(),
      sourceType: ArtworkSourceType.album,
      size: size,
    ).then((artwork) {
      _albumCache[albumId] = artwork;
      return artwork;
    });
  }

  @override
  Future<File?> getArtworkFile({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
  }) async {
    final cacheKey = _buildCacheKey(id.isNotEmpty ? id : (filePath ?? 'default'), sourceType);
    final cacheDir = await _getCacheDirectory();
    final file = File(p.join(cacheDir, '$cacheKey.jpg'));

    if (await file.exists()) {
      return file;
    }

    final bytes = await getArtwork(
      id: id,
      filePath: filePath,
      sourceType: sourceType,
    );

    if (bytes != null && await file.exists()) {
      return file;
    }

    return null;
  }

  @override
  Future<void> preloadArtwork(List<Track> tracks) async {
    for (final track in tracks) {
      final id = track.albumArtUri ?? track.id;
      if (id.isNotEmpty) {
        getArtwork(id: id, filePath: track.filePath);
      }
    }
  }

  @override
  Future<void> clearCache() async {
    _memoryCache.clear();
    _albumCache.clear();
    try {
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('ArtworkService: Error clearing disk cache: $e');
    }
  }

  /// Searches for standard album artwork image files in the audio file's directory.
  Future<Uint8List?> _findLocalFolderArtwork(String audioFilePath) async {
    try {
      final file = File(audioFilePath);
      if (!await file.exists()) return null;

      final dir = file.parent;
      const candidateNames = [
        'cover.jpg',
        'cover.png',
        'cover.jpeg',
        'folder.jpg',
        'folder.png',
        'folder.jpeg',
        'album.jpg',
        'album.png',
        'album.jpeg',
        'front.jpg',
        'front.png',
      ];

      for (final name in candidateNames) {
        final imgFile = File(p.join(dir.path, name));
        if (await imgFile.exists()) {
          final bytes = await imgFile.readAsBytes();
          if (bytes.isNotEmpty) {
            return bytes;
          }
        }
      }
    } catch (_) {
      // Ignored for platform permission or file system restrictions
    }
    return null;
  }
}

/// Mock implementation of [ArtworkService] for unit and widget testing.
class MockArtworkService implements ArtworkService {
  final Map<String, Uint8List?> _store;

  MockArtworkService([Map<String, Uint8List?>? initialData])
      : _store = initialData != null ? Map.from(initialData) : {};

  void setArtwork(String id, Uint8List? bytes, {ArtworkSourceType sourceType = ArtworkSourceType.audio}) {
    final key = '${sourceType.name}_$id';
    _store[key] = bytes;
    _store[id] = bytes;
  }

  @override
  String artworkCacheKey({
    required String id,
    String? filePath,
    required ArtworkSourceType sourceType,
  }) {
    return '${sourceType.name}_${id.isNotEmpty ? id : (filePath ?? '')}';
  }

  @override
  Uint8List? getFromMemoryCache(String key) {
    return _store[key];
  }

  @override
  Future<Uint8List?> getArtwork({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
    int? size,
  }) async {
    final key = '${sourceType.name}_$id';
    if (_store.containsKey(key)) return _store[key];
    if (_store.containsKey(id)) return _store[id];
    return null;
  }

  @override
  Future<Uint8List?> getAlbumArtwork(int albumId, {int? size}) async {
    return getArtwork(
      id: albumId.toString(),
      sourceType: ArtworkSourceType.album,
    );
  }

  @override
  Future<File?> getArtworkFile({
    required String id,
    String? filePath,
    ArtworkSourceType sourceType = ArtworkSourceType.audio,
  }) async {
    return null;
  }

  @override
  Future<void> preloadArtwork(List<Track> tracks) async {}

  @override
  Future<void> clearCache() async {
    _store.clear();
  }
}

/// Provider for [ArtworkService].
final artworkServiceProvider = Provider<ArtworkService>((ref) {
  return DefaultArtworkService();
});
